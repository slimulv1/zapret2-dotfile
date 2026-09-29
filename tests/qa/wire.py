"""Đo kích thước đoạn TCP đầu trên dây — phục vụ INV-DESYNC-1.

Bẫy lớn nhất: **offload**. `tcp-segmentation-offload: on` ⇒ kernel đưa cả khối
lớn xuống NIC, NIC mới chia trên dây. Mọi công cụ bắt gói chạy trên host đều
nằm TRƯỚC bước chia, nên sẽ thấy MỘT khối lớn dù trên dây có nhiều đoạn nhỏ.
Đo mà quên tắt thì ra số hoàn toàn sai — kể cả `tcpdump`.

Vì vậy `offload()` ở đây là context manager: tắt trước, **bật lại trong
`finally`**, kể cả khi test fail hay nổi exception. Bỏ sót lệnh bật lại thì giảm
hiệu năng toàn hệ thống — đó là thiệt hại do chính phép thử gây ra.
"""

from __future__ import annotations

import contextlib
import socket
import struct
import time

from .host import Result, run

ETH_P_ALL = 0x0003
TCP_PROTO, ET_IP, ET_IP6, ET_VLAN = 6, 0x0800, 0x86DD, 0x8100


@contextlib.contextmanager
def offload(iface: str, on: bool):
    """Đặt TSO/GSO/GRO theo `on`, và **khôi phục đúng trạng thái gốc từng khoá**.

    Hai điểm từng làm hỏng phép đo:
      * Không tắt offload ⇒ host thấy MỘT khối lớn, số đo sai hoàn toàn.
      * Bật lại mù quáng bằng `on` ⇒ nếu máy vốn đã tắt một khoá nào đó, ta
        vô tình BẬT nó lên và để lại thiệt hại hiệu năng cho cả hệ thống.
        Nên đọc trạng thái gốc, rồi trả về đúng từng khoá.
    """
    before = _offload_state(iface)
    want = "off" if on else "on"
    for k in before:
        run(["ethtool", "-K", iface, k, want], sudo=True, timeout=30)
    try:
        yield _offload_state(iface)      # trạng thái ĐANG có, để test kiểm chứng
    finally:
        now = _offload_state(iface)
        for k, v in before.items():
            if now.get(k) != v:
                run(["ethtool", "-K", iface, k, v], sudo=True, timeout=30)


def _offload_state(iface: str) -> dict[str, str]:
    res = run(["ethtool", "-k", iface], sudo=True, timeout=30)
    keys = ("tcp-segmentation-offload", "generic-segmentation-offload",
            "generic-receive-offload")
    out = {}
    for line in res.out.splitlines():
        k, _, v = line.partition(":")
        if k in keys:
            out[k] = v.split()[0]
    return out


def _parse(pkt: bytes):
    if len(pkt) < 14:
        return None
    et = struct.unpack("!H", pkt[12:14])[0]
    off = 14
    while et in (ET_VLAN, 0x88A8):
        if len(pkt) < off + 4:
            return None
        et = struct.unpack("!H", pkt[off + 2:off + 4])[0]
        off += 4
    fam = None
    if et == ET_IP and len(pkt) >= off + 20 and pkt[off + 9] == TCP_PROTO:
        ihl = (pkt[off] & 0x0F) * 4
        if struct.unpack("!H", pkt[off + 6:off + 8])[0] & 0x1FFF:
            return None
        fam = "v4"
        poff = off + ihl
    elif et == ET_IP6 and len(pkt) >= off + 40 and pkt[off + 6] == TCP_PROTO:
        fam = "v6"
        poff = off + 40
    else:
        return None
    if len(pkt) < poff + 20:
        return None
    sp, dp = struct.unpack("!HH", pkt[poff:poff + 4])
    doff = (pkt[poff + 12] >> 4) * 4
    flags = pkt[poff + 13]
    # `raw` giữ nguyên tải trả về (không phải chuỗi hex) — cần byte thô để đọc
    # SNI. 6 byte đầu thì không đủ: ClientHello có tên miền hay không chỉ lộ ra
    # sau khi tách hết cấu trúc TLS.
    return dict(sp=sp, dp=dp, fam=fam, flags=flags,
                syn=bool(flags & 0x02),
                pay=len(pkt[poff + doff:]), head=pkt[poff + doff:poff + doff + 6].hex(),
                raw=pkt[poff + doff:])


def first_segments(iface: str, dport: int = 443, seconds: float = 12.0):
    """Bắt gói trong `seconds`, trả về đoạn đầu tiên mang dữ liệu của mỗi luồng.

    Gọi từ trong `offload()`; xem cảnh báo ở đầu tệp.
    """
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    s.settimeout(0.5)
    s.bind((iface, 0))
    flows: dict[tuple, dict] = {}
    end = time.time() + seconds
    try:
        while time.time() < end:
            try:
                pkt = s.recv(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            r = _parse(pkt)
            if not r or r["dp"] != dport:
                continue
            key = (r["sp"], r["dp"])
            if r["syn"] and not (r["flags"] & 0x10):
                flows[key] = {"fam": r["fam"], "segs": []}
                continue
            if key not in flows or r["pay"] == 0:
                continue
            flows[key]["segs"].append((r["pay"], r["head"], r["raw"]))
    finally:
        s.close()
    out = []
    for f in flows.values():
        if not f["segs"]:
            continue
        out.append({
            "fam": f["fam"],
            "first": f["segs"][0][0],
            "first_head": f["segs"][0][1],
            # byte thô của đoạn đầu: cần để đọc SNI, tức trả lời "một DPI
            # chỉ soi đoạn đầu thì có thấy tên miền không".
            "first_bytes": f["segs"][0][2],
            "all_bytes": [p for p, _, _ in f["segs"]],
            "total": sum(p for p, _, _ in f["segs"]),
            "nseg": len(f["segs"]),
        })
    return out
