#!/usr/bin/env python3
"""Đo từng chiến lược desync của zapret2 trên chính máy này.

MỤC ĐÍCH
    Trả lời bằng phép đo: một cấu hình desync có đáng dùng không. Ba câu hỏi, đo
    riêng, không suy ra nhau:

      1. CÓ DPI KHÔNG        — dừng zapret2, thử vài trang. Không trang nào chết
                              ⇒ đường này không có gì để vượt, mọi so sánh
                              "vượt tốt hơn" đều vô nghĩa ở đây.
      2. DESYNC CÓ BẮN KHÔNG — bắt gói thẳng trên dây, đo đoạn đầu TCP.
      3. TỐN BAO NHIÊU       — độ trễ tới byte đầu, và thời gian CPU của nfqws2
                              trên một số lượt yêu cầu cố định.

VÌ SAO CẦN ĐO CHI PHÍ KHI KHÔNG ĐO ĐƯỢC LỢI ÍCH
    Ở máy này không có DPI (xem docs/RESEARCH-DESIGN), nên không đo được "vượt
    tốt hơn". Đo được phần còn lại: chi phí. Cấu hình yếu hơn mà rẻ hơn thì mới
    là lựa chọn đúng. Đây là lập luận ngược, dựa trên số đo thật, không phải
    suy đoán.

CÁCH DÙNG
    sudo python3 tests/bench-dpi.py --list
    sudo python3 tests/bench-dpi.py --run baseline,docs-minimal
    sudo python3 tests/bench-dpi.py --run all --repeats 6

MỌI THAY ĐỔI ĐỀU ĐẢO NGƯỢC
    Ứng dụng cấu hình ứng viên thì sao lưu `/opt/zapret2/config` trước, và luôn
    khôi phục trong `finally` — kể cả khi đo giữa chừng thì bị SIGINT.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import statistics as st
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from qa.host import run                                    # noqa: E402
from qa.wire import first_segments, offload                # noqa: E402

CONFIG = "/opt/zapret2/config"
IFACE = "enp8s0"

#: Trang dùng để đo. Gồm cả trang quen thuộc lẫn trang hay bị chặn, vì chặn ở
#: Việt Nam thiên về tên miền chứ không phải IP.
SITES = [
    ("github.com", "https://github.com/"),
    ("youtube.com", "https://www.youtube.com/"),
    ("facebook.com", "https://www.facebook.com/"),
    ("telegram.org", "https://web.telegram.org/"),
    ("reddit.com", "https://www.reddit.com/"),
]

#: ---------------------------------------------------------------------------
# Ứng viên. Mỗi cái là một NFQWS2_OPT, kèm lý do.
#
# `baseline` = đang chạy trên máy. Phần còn lại theo tài liệu, xem
# docs/RESEARCH-DPI.md mục 3.
#
# Công thức chuẩn lấy nguyên văn từ wiki.zapret.moe/Zapret2/desync/fake:
#   "Типовая боевая связка fake + multisplit"
#     --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid,padencap
#     --lua-desync=multisplit:pos=1,midsld
# và cho QUIC (wiki.zapret.moe/Zapret2/desync/fake):
#     --lua-desync=fake:blob=fake_default_quic:ip_ttl=1:ip6_ttl=1
# ---------------------------------------------------------------------------
TLS_HEAD = "--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello"
HTTP_HEAD = "--filter-tcp=80 --filter-l7=http --payload=http_req"

#: Profile 80 không đổi suốt thí nghiệm — nó đã có `tcp_md5` nên đúng, giữ nguyên
#: để mọi khác biệt đo được đều đến từ profile 443.
PORT80 = f"{HTTP_HEAD} --lua-desync=fake:blob=fake_default_http:tcp_md5 " \
         f"--lua-desync=multisplit:pos=method+2"

CANDIDATES: dict[str, dict] = {
    "baseline": {
        "desc": "đang chạy: multisplit trần, không fake, không fooling",
        "tcp80": PORT80,
        "tcp443": f"{TLS_HEAD} --lua-desync=multisplit:pos=1",
    },
    "canonical": {
        "desc": "wiki.zapret.moe «типовая боевая связка»: fake+tcp_md5+tls_mod rồi multisplit:pos=1,midsld",
        "tcp80": PORT80,
        "tcp443": f"{TLS_HEAD} "
                  f"--lua-desync=fake:blob=fake_default_tls:tcp_md5:"
                  f"tls_mod=rnd,rndsni,dupsid,padencap "
                  f"--lua-desync=multisplit:pos=1,midsld",
    },
    "canonical+quic": {
        "desc": "canonical + profile QUIC udp/443 (fake + ip_ttl=1, không split — datagram tự chứa)",
        "tcp80": PORT80,
        "tcp443": f"{TLS_HEAD} "
                  f"--lua-desync=fake:blob=fake_default_tls:tcp_md5:"
                  f"tls_mod=rnd,rndsni,dupsid,padencap "
                  f"--lua-desync=multisplit:pos=1,midsld",
        "udp443": "--filter-udp=443 --filter-l7=quic --payload=quic_initial "
                  "--lua-desync=fake:blob=fake_default_quic:ip_ttl=1:ip6_ttl=1",
    },
    "fakeddisorder": {
        "desc": "chiến lược mạnh hơn: fake + tách + gửi NGƯỢC thứ tự (2 đoạn, 6 gói)",
        "tcp80": PORT80,
        "tcp443": f"{TLS_HEAD} "
                  f"--lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up",
    },
    "nofool-fake": {
        "desc": "THỬ ĐỂ BÁC BỎ: fake KHÔNG có fooling — bol-van cảnh báo «гарантированный слом»",
        "tcp80": PORT80,
        "tcp443": f"{TLS_HEAD} "
                  f"--lua-desync=fake:blob=fake_default_tls "
                  f"--lua-desync=multisplit:pos=1,midsld",
    },
}


OPT_KEY_ORDER = ["tcp80", "tcp443", "udp443"]


# --------------------------------------------------------------------------- #
# Cài ứng viên
# --------------------------------------------------------------------------- #
def build_opt(name: str) -> str:
    c = CANDIDATES[name]
    parts = []
    for k in OPT_KEY_ORDER:
        v = c.get(k)
        if v:
            parts.append(f"  {v} --new")
    return "\n".join(parts)


def _replace_nfqws_opt(text: str, opt: str) -> str:
    """Thay đúng khối `NFQWS2_OPT="…"` trong config, giữ nguyên phần còn lại.

    Dùng tìm-vị-trí thay vì regex: nội dung nhiều dòng, mà regex `[^"]*` lỡ
    dính dấu nháy kép trong tham số thì cắt đúng khối luôn.
    """
    key = 'NFQWS2_OPT="'
    i = text.find(key)
    if i < 0:
        raise ValueError("không tìm thấy NFQWS2_OPT trong config")
    j = text.find('"', i + len(key))
    if j < 0:
        raise ValueError("NFQWS2_OPT mở nhưng không đóng")
    return text[:i] + key + opt + '"' + text[j + 1:]


def install_candidate(name: str) -> tuple[bool, str]:
    """Ghi NFQWS2_OPT rồi khởi động lại. Trả (thành công, giải thích)."""
    cur = run(["cat", CONFIG], sudo=True, timeout=30).out
    try:
        new = _replace_nfqws_opt(cur, build_opt(name))
    except ValueError as e:
        return False, str(e)
    tmp = "/tmp/z2d-qa/bench-config.new"
    Path(tmp).write_text(new, encoding="utf-8")
    r = run(["install", "-o", "root", "-g", "root", "-m", "644", tmp, CONFIG],
            sudo=True, timeout=60)
    if not r.ok:
        return False, f"không ghi được config: {r.err.strip()[:200]}"
    run(["systemctl", "restart", "zapret2"], sudo=True, timeout=90)
    time.sleep(4)
    act = run(["systemctl", "is-active", "zapret2"], sudo=True, timeout=30).out.strip()
    if act != "active":
        j = run(["journalctl", "-u", "zapret2", "--since", "-30sec", "--no-pager"],
                sudo=True, timeout=30).out.strip().splitlines()[-4:]
        return False, "nfqws2 không khởi động được: " + " | ".join(j)
    return True, "ok"


# --------------------------------------------------------------------------- #
# Đo
# --------------------------------------------------------------------------- #
def probe_site(url: str, timeout: int = 20, http3: bool = False) -> tuple[int, float]:
    """Trả (mã HTTP, ms tới byte đầu). Không có mã ⇒ 0.

    `http3=True` ép curl đi qua QUIC. Đây là phép thử riêng, không suy ra được
    từ phép thử TCP: profile UDP/443 có thể làm hỏng HTTP/3 trong khi TCP vẫn
    200 — hoặc ngược lại.
    """
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code} %{time_starttransfer}",
           "-m", str(timeout)]
    if http3:
        cmd.append("--http3")
    cmd.append(url)
    res = run(cmd, timeout=timeout + 15)
    parts = res.out.strip().split()
    if len(parts) != 2 or not parts[0].isdigit():
        return 0, 0.0
    try:
        return int(parts[0]), float(parts[1]) * 1000
    except ValueError:
        return 0, 0.0


def measure_desync(seconds: float = 10.0) -> dict:
    """Bắt gói thẳng trên dây, đo từng đoạn và **đọc SNI của đoạn đầu**.

    VÌ SAO ĐỌC SNI CHỨ KHÔNG ĐO CHIỀU DÀI

    Bản đầu của bộ đo chỉ xem kích thước đoạn đầu rồi kết luận "desync có
    chạy". Chạy thử lập tức lộ ra lỗi: ứng viên `docs-minimal` bơm gói **fake**
    trước dữ liệu thật, nên đoạn đầu trên dây là gói giả 680 byte chứ không
    phải đoạn tách 1 byte. Số đo đúng cho "desync có chạy" nhưng SAI cho câu
    hỏi quan trọng hơn — "desync có **ẩn** tên miền không".

    Câu hỏi đúng là: *một DPI chỉ soi đoạn đầu thì có thấy tên miền không?*
    Nên phải đọc SNI trong đoạn đầu, dùng đúng bộ tách SNI của lab DPI.
    """
    import threading
    sys.path.insert(0, str(Path(__file__).resolve().parent / "lab"))
    from dpi import parse_sni                                   # noqa: E402

    def traffic():
        time.sleep(2)
        for _, url in SITES[:3]:
            run(["curl", "-s", "-o", "/dev/null", "-m", "10", url], timeout=20)
            time.sleep(0.5)

    t = threading.Thread(target=traffic, daemon=True)
    t.start()
    with offload(IFACE, on=True):
        segs = first_segments(IFACE, 443, seconds=seconds)
    t.join(timeout=5)
    if not segs:
        return {"fired": None, "sni_hidden": None,
                "detail": "không bắt được luồng nào"}

    per = []
    for s in segs:
        per.append({"fam": s["fam"], "first": s["first"],
                    "sni": parse_sni(s["first_bytes"]),
                    "nseg": s["nseg"]})
    snis = [p["sni"] for p in per]
    return {
        "fired": True,
        "sni_hidden": all(v is None for v in snis),
        "first_snis": snis,
        "first_bytes": [p["first"] for p in per],
        "segment_counts": [p["nseg"] for p in per],
        "families": [p["fam"] for p in per],
        "detail": (f"SNI đoạn đầu {snis} · kích thước {[p['first'] for p in per]} "
                   f"byte · số đoạn {[p['nseg'] for p in per]}"),
    }


def measure_cpu(requests: int = 6) -> float:
    """Giây CPU của nfqws2 trong lúc gửi `requests` yêu cầu."""
    pid = run(["sh", "-c", "pgrep -x nfqws2 | head -1"], sudo=True, timeout=30).out.strip()
    if not pid.isdigit():
        return 0.0

    def cpu(pid: str) -> float:
        f = run(["sh", "-c",
                 f"awk '{{print $14+$15}}' /proc/{pid}/stat 2>/dev/null"],
                sudo=True, timeout=30).out.strip()
        try:
            return int(f) / os.sysconf("SC_CLK_TCK")
        except ValueError:
            return 0.0

    before = cpu(pid)
    for _, url in SITES:
        run(["curl", "-s", "-o", "/dev/null", "-m", "10", url], timeout=20)
    return round(cpu(pid) - before, 2)


def run_one(name: str, repeats: int) -> dict:
    ok, why = install_candidate(name)
    if not ok:
        return {"name": name, "desc": CANDIDATES[name]["desc"], "usable": False, "why": why}
    lat, codes = [], {}
    for _ in range(repeats):
        for host, url in SITES:
            code, ms = probe_site(url)
            codes[host] = code
            if ms:
                lat.append(ms)
    # HTTP/3 đo riêng, sau TCP, để không lẫn nhiễu. Cần riêng vì profile
    # UDP/443 có thể hỏng QUIC mà TCP vẫn bình thường.
    h3 = {h: probe_site(u, http3=True)[0] for h, u in SITES}
    des = measure_desync()
    cpu = measure_cpu()
    return {
        "name": name, "desc": CANDIDATES[name]["desc"], "usable": True,
        "codes": codes,
        "http3_codes": h3,
        "latency_ms": {"TB": round(st.median(lat), 1) if lat else None,
                       "min": round(min(lat), 1) if lat else None},
        "desync": des,
        "nfqws2_cpu_s": cpu,
    }


# --------------------------------------------------------------------------- #
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="liệt kê ứng viên rồi thoát")
    ap.add_argument("--run", default="", help="tên ứng viên, cách nhau bởi dấu phẩy, hoặc 'all'")
    ap.add_argument("--repeats", type=int, default=4)
    ap.add_argument("--iface", default=IFACE)
    a = ap.parse_args()

    if a.list:
        for k, v in CANDIDATES.items():
            print(f"{k:16} {v['desc']}")
        return 0
    if not a.run:
        ap.print_help()
        return 2

    if os.geteuid() != 0:
        print("cần chạy bằng root", file=sys.stderr)
        return 1
    for n in ("curl", "systemctl", "journalctl"):
        if shutil.which(n) is None:
            print(f"thiếu lệnh {n}", file=sys.stderr)
            return 1

    names = list(CANDIDATES) if a.run == "all" else a.run.split(",")
    bad = [n for n in names if n not in CANDIDATES]
    if bad:
        print(f"không có ứng viên: {bad}", file=sys.stderr)
        return 2

    bak = "/tmp/z2d-qa/bench-config.bak"
    Path("/tmp/z2d-qa").mkdir(parents=True, exist_ok=True)
    shutil.copy2(CONFIG, bak)

    # --- kiểm tra nền: có DPI không ---
    print("== kiểm tra nền: tắt zapret2 rồi thử trực tiếp ==", flush=True)
    run(["systemctl", "stop", "zapret2"], sudo=True, timeout=60)
    time.sleep(3)
    baseline_codes = {h: probe_site(u)[0] for h, u in SITES}
    run(["systemctl", "start", "zapret2"], sudo=True, timeout=60)
    time.sleep(3)
    dead = [h for h, c in baseline_codes.items() if c == 0]
    has_dpi = bool(dead)
    print(f"   zapret2 TẮT → {baseline_codes}")
    print(f"   kết luận: {'CÓ DPI' if has_dpi else 'KHÔNG có DPI — không đo được lợi ích vượt, chỉ đo được chi phí'}")

    results = []
    try:
        for n in names:
            print(f"\n== ứng viên: {n} — {CANDIDATES[n]['desc']} ==", flush=True)
            r = run_one(n, a.repeats)
            results.append(r)
            if not r["usable"]:
                print(f"   KHÔNG dùng được: {r['why']}")
            else:
                print(f"   mã HTTP : {r['codes']}")
                print(f"   HTTP/3  : {r['http3_codes']}")
                print(f"   độ trễ  : trung vị {r['latency_ms']['TB']} ms · nhanh nhất {r['latency_ms']['min']} ms")
                print(f"   trên dây: {r['desync']['detail']}")
                print(f"   SNI ẩn  : {r['desync']['sni_hidden']}  (DPI chỉ soi đoạn đầu có thấy tên miền không)")
                print(f"   CPU     : {r['nfqws2_cpu_s']} s nfqws2 cho 5 yêu cầu")
    finally:
        shutil.copy2(bak, CONFIG)
        run(["systemctl", "restart", "zapret2"], sudo=True, timeout=90)
        time.sleep(3)
        print("\n== đã khôi phục config gốc ==")

    out = {"dpi_detected": has_dpi, "baseline_without_zapret2": baseline_codes,
           "results": results}
    Path("/tmp/z2d-qa/bench.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))
    print("  → /tmp/z2d-qa/bench.json")

    ok = [r for r in results if r["usable"]]
    if ok:
        print("\n== so sánh ==")
        for r in sorted(ok, key=lambda x: x["latency_ms"]["TB"] or 1e9):
            broke = [h for h, c in r["codes"].items() if c == 0]
            h3bad = [h for h, c in r["http3_codes"].items() if c == 0]
            print(f"   {r['name']:17} trễ {r['latency_ms']['TB']:>7} ms · "
                  f"CPU {r['nfqws2_cpu_s']:>4} s · "
                  f"SNI ẩn={str(r['desync']['sni_hidden']):5} · "
                  f"TCP hỏng={broke or 'không'} · "
                  f"HTTP/3 hỏng={h3bad or 'không'}")
        if not has_dpi:
            print("\n   LƯU Ý: không có DPI ⇒ cột 'SNI ẩn' chỉ nói về *nguyên lý* của")
            print("   chiến lược, KHÔNG phải bằng chứng vượt được gì. Ở đây không có")
            print("   gì để vượt.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
