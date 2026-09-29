#!/usr/bin/env python3
"""DPI GIẢ LẬP — mô phỏng bộ lọc nhà mạng chặn theo tên miền trong ClientHello.

MÔ HÌNH, VÀ GIỚI HẠN CỦA NÓ (đọc trước khi tin kết quả)
----------------------------------------------------------
Cái này **KHÔNG phải** DPI thật của nhà mạng Việt Nam. Nó mô phỏng đúng MỘT
kiểu cài đặt phổ biến: chỉ soi **đoạn TCP đầu tiên** rồi quyết định, không
chờ ghép lại các đoạn sau.

  * zapret2 CHẠY   → đoạn đầu = 1 byte (0x16). DPI soi đoạn đó, không thấy
    tên miền ⇒ cho qua. Rồi mọi đoạn sau được chuyển tiếp bình thường.
  * zapret2 DỪNG   → đoạn đầu = nguyên ClientHello (~1.4 KB). DPI thấy tên
    miền trong đó ⇒ chặn.

Giới hạn phải nói thẳng: một DPI **ghép lại** các đoạn thì vẫn đọc được tên
miền và sẽ chặn. Vì vậy lab này chứng minh *"desync làm tên miền biến mất
khỏi đoạn đầu"*, KHÔNG chứng minh *"đánh bại được DPI thật của ISP"*. Muốn
kết luận điều sau thì phải thay bằng DPI thật hoặc capture của mạng thật.

Giao diện:
    dpi.py --listen 10.99.0.2:443 --blocked github.com \\
           --upstream github.com=20.205.243.166 --upstream kernel.org=172.105.4.254
"""
from __future__ import annotations

import argparse
import socket
import struct
import sys
import threading
import time

LOG_LOCK = threading.Lock()


def log(msg: str) -> None:
    with LOG_LOCK:
        sys.stderr.write(f"[dpi] {msg}\n")
        sys.stderr.flush()


def parse_sni(data: bytes) -> str | None:
    """Rút Server Name Name từ một phần ClientHello TLS.

    Trả None nếu `data` KHÔNG đủ để có SNI — đó là kết quả hợp lệ và quan
    trọng: nghĩa là đoạn đầu tiên không mang tên miền.
    """
    try:
        if len(data) < 5 or data[0] != 0x16:
            return None
        rec_len = struct.unpack("!H", data[3:5])[0]
        if len(data) < 5 + rec_len:
            return None                      # chưa nhận hết bản ghi
        p = 5
        if data[p] != 0x01:                   # ClientHello
            return None
        p += 1 + 3                            # type + handshake length
        p += 2                                # client_version
        p += 32                               # random
        sid = data[p]; p += 1 + sid           # session_id
        cs = struct.unpack("!H", data[p:p + 2])[0]; p += 2 + cs
        cm = data[p]; p += 1 + cm             # compression_methods
        if p + 2 > len(data):
            return None
        ext_total = struct.unpack("!H", data[p:p + 2])[0]
        p += 2
        end = min(p + ext_total, len(data))
        while p + 4 <= end:
            etype, elen = struct.unpack("!HH", data[p:p + 4])
            p += 4
            if etype == 0x0000:              # server_name
                if p + 5 <= len(data):
                    nlen = struct.unpack("!H", data[p + 3:p + 5])[0]
                    return data[p + 5:p + 5 + nlen].decode("ascii", "replace")
                return None
            p += elen
        return None
    except (IndexError, struct.error):
        return None


def pump(src: socket.socket, dst: socket.socket) -> None:
    try:
        while True:
            b = src.recv(65536)
            if not b:
                break
            dst.sendall(b)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def handle(conn: socket.socket, addr, blocked: set[str], upstream: dict[str, str]) -> None:
    with conn:
        # MỘT lần recv: đúng mô hình "chỉ soi đoạn đầu tiên".
        conn.settimeout(2.0)
        try:
            first = conn.recv(65536)
        except socket.timeout:
            first = b""
        if not first:
            return
        sni = parse_sni(first)
        log(f"tu {addr[0]} · doan dau {len(first)} byte · SNI={sni!r}")
        if sni and sni in blocked:
            log(f"  → CHẶN (SNI {sni} trong danh sach)")
            conn.close()                        # im lặng, không báo lý do
            return
        # Server đích suy từ ĐỊA CHỈ ĐÍCH của socket — thứ luôn nhìn thấy
        # được. DPI thật cũng biết server là ai; nó chỉ cần SNI để QUYẾT ĐỊNH
        # có chặn không. Chọn upstream theo SNI là sai mô hình: desync giấu
        # SNI, nên DPI sẽ tự đóng kết nối dù đáng lẽ phải cho qua.
        dst = conn.getsockname()[0]
        if dst not in upstream:
            log(f"  → khong ro server nao cho dich {dst}; dong ket noi")
            conn.close()
            return
        up = upstream[dst]
        h, _, port = up.partition(":")
        try:
            srv = socket.create_connection((h, int(port or 443)), timeout=8)
        except OSError as e:
            log(f"  → khong noi duoc upstream {up}: {e}")
            conn.close()
            return
        log(f"  → CHO QUA, chuyen tiep toi {up}")
        srv.sendall(first)
        t = threading.Thread(target=pump, args=(conn, srv), daemon=True)
        t.start()
        pump(srv, conn)
        t.join(timeout=5)
        srv.close()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", default="0.0.0.0:443")
    ap.add_argument("--blocked", default="", help="danh sach SNI bị chặn, cách nhau dấu phẩy")
    ap.add_argument("--upstream", action="append", default=[],
                    help="DICH_IP=upstream_ip[:port], lặp lại. DPI chọn server để "
                         "chuyển tiếp theo ĐỊA CHỈ ĐÍCH, không theo SNI — vì "
                         "SNI thì desync cố tình giấu, chọn theo nó thì tự đứt.")
    a = ap.parse_args()
    h, _, p = a.listen.rpartition(":")
    up = dict(x.split("=", 1) for x in a.upstream)
    log_up = up
    blocked = {s for s in a.blocked.split(",") if s}
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((h, int(p)))
    s.listen(16)
    log(f"nghe {a.listen} · chan {sorted(blocked) or 'khong'} · "
        f"dich→server {log_up}")
    while True:
        try:
            c, addr = s.accept()
        except OSError:
            break
        threading.Thread(target=handle, args=(c, addr, blocked, up), daemon=True).start()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
