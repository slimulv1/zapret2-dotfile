"""Lab tầng 3 — `INV-IN-1`: từ NGOÀI LAN chỉ KDE Connect được vào.

Không có máy thứ hai trong nhà, nên dựng một "máy ngoài" bằng network namespace
nối qua veth. Gói của nó đi đúng chuỗi prerouting → INPUT của máy thật, nên
đây là phép thử thật, không phải mô phỏng bằng cách đọc cấu hình.

Kết quả mong đợi:
    nguồn TRONG 192.168.0.0/16  → 1716 open (tường cho qua + kdeconnectd nghe)
                                 các cổng khác filtered
    nguồn NGOAI 192.168.0.0/16  → TẤT CẢ filtered, kể cả 1716

ĐỐI CHỨNG BẮT BUỘC: phải xác nhận `kdeconnectd` thật sự đang lắng nghe trước khi
kết luận "bị chặn". Không có bước này thì "1716 filtered" cũng đúng với máy
đã tắt dịch vụ — tức phép thử không phân biệt được tường với dịch vụ chết.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from qa.host import LONG_TIMEOUT, run

pytestmark = [pytest.mark.destructive, pytest.mark.network, pytest.mark.slow]

REPO = Path(__file__).resolve().parent.parent
SETUP = REPO / "tests" / "lab" / "inet_scan.sh"
SCAN = REPO / "tests" / "lab" / "scan.py"
HOST_IP = "192.168.1.24"          # địa chỉ LAN thật của máy
KDE_PORT = "1716"

#: Những cổng KHÔNG được mở cho bất kỳ ai. Chọn cả cổng có dịch vụ thật
#: (53 của resolved) lẫn cổng không có (3306) để phép thử không phụ thuộc vào
#: việc máy đang chạy gì.
MUST_BE_BLOCKED = ["22", "53", "80", "443", "3306", "5432", "8080"]


def _lab(action: str, src: str | None = None):
    cmd = ["bash", str(SETUP), action] + ([src] if src else [])
    return run(cmd, sudo=True, timeout=LONG_TIMEOUT)


def _scan(ports: str | None = None) -> dict[str, str]:
    # PHẢI chạy trong netns. Bản đầu gọi thẳng `python3` nên quét ngay trên
    # máy thật — tức KHÔNG đi qua INPUT, và cả 2 ca đỏ trong 0.46 giây, quá
    # nhanh để là quét thật (timeout 2s/cổng).
    cmd = ["ip", "netns", "exec", "z2d_in",
           "python3", str(SCAN), "--host", HOST_IP, "--timeout", "2"]
    if ports:
        cmd += ["--ports", ports]
    res = run(cmd, sudo=True, timeout=120)
    out = {}
    for line in res.out.splitlines():
        p, _, st = line.partition("\t")
        if p.strip().isdigit():
            out[p.strip()] = st.strip()
    return out


def _kde_is_listening() -> bool:
    return "1716" in run(["sh", "-c", "ss -tlnp 2>/dev/null | grep ':1716'"],
                         sudo=True, timeout=30).out


@pytest.fixture(scope="module")
def in_lab(require_installed):
    _lab("down")
    yield
    _lab("down")
    left = run(["sh", "-c",
                "ip netns list 2>/dev/null | grep -c z2d_in; "
                "ip link show v2in0 2>/dev/null | wc -l"],
               sudo=True, timeout=30).out.split()
    assert left == ["0", "0"], f"lab để lại dấu vết: netns={left[0]} veth={left[1]}"


@pytest.mark.parametrize("src,expect_kde", [
    ("192.168.99.2", "open"),      # trong 192.168.0.0/16
    ("203.0.113.5", "filtered"),    # ngoài 192.168.0.0/16
], ids=["trong-LAN", "ngoai-subnet"])
def test_input_from_outside_is_blocked_except_kde_connect(in_lab, src, expect_kde):
    _lab("up", src)
    assert _kde_is_listening(), (
        "kdeconnectd không lắng nghe 1716 — nếu quét thấy 'filtered' thì đó là do "
        "DỊCH VỤ TẮT chứ không phải do tường, phép thử vô nghĩa. Cần dịch vụ chạy "
        "thật để kết luận."
    )
    res = _scan()

    for port in MUST_BE_BLOCKED:
        assert res.get(port) == "filtered", (
            f"cổng {port} từ nguồn {src} trả {res.get(port)!r}, mong đợi 'filtered'"
        )
    assert res.get(KDE_PORT) == expect_kde, (
        f"cổng {KDE_PORT} từ nguồn {src} trả {res.get(KDE_PORT)!r}, "
        f"mong đợi {expect_kde!r}\n  toàn bộ: {res}"
    )
