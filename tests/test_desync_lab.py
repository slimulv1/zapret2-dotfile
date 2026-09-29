"""Lab DPI giả lập — đóng phần CHỨC NĂNG của INV-DESYNC-1.

Vì sao cần lab: trên mạng thật của tôi, dừng zapret2 thì mọi trang vẫn trả
200 ⇒ **không có DPI nào** để chứng minh desync có tác dụng hay không. Đo được
1 byte chỉ chứng minh CƠ CHẾ, không chứng minh TÁC DỤNG.

Lab dựng một DPI giả trong network namespace, đi qua đúng đường có hook
NFQUEUE. Nó mô phỏng **một** kiểu cài đặt phổ biến: chỉ soi đoạn TCP đầu
tiên, không ghép lại các đoạn sau.

GIỚI HẠN PHẢI NÓI THẲNG: DPI thật mà GHÉP LẠI đoạn thì vẫn thấy tên miền và
vẫn chặn. Lab này chứng minh "desync làm tên miền biến mất khỏi đoạn đầu",
KHÔNG chứng minh "đánh bại được DPI của nhà mạng Việt Nam".
"""
from __future__ import annotations

import subprocess
import time
from pathlib import Path

import pytest

from qa.host import LONG_TIMEOUT, run

pytestmark = [pytest.mark.destructive, pytest.mark.network, pytest.mark.slow]

REPO = Path(__file__).resolve().parent.parent
SETUP = REPO / "tests" / "lab" / "setup.sh"
BLOCKED_IP = "198.51.100.1"      # đóng vai github.com — SNI bị DPI chặn
ALLOWED_IP = "198.51.100.2"      # đóng vai kernel.org — SNI được phép


def _lab(action: str):
    return run(["bash", str(SETUP), action], sudo=True, timeout=LONG_TIMEOUT)


def _fetch(hostname: str, ip: str) -> int:
    """Mã HTTP, 0 = không thành công. Dùng --resolve nên không cần DNS."""
    res = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-m", "30",
               "--resolve", f"{hostname}:443:{ip}", f"https://{hostname}/"],
              timeout=60)
    return int(res.out.strip() or 0)


def _dpi_saw() -> list[str]:
    log = run(["sh", "-c", "tail -20 /tmp/z2d-qa/dpi.log 2>/dev/null"],
              sudo=True, timeout=30).out
    return [l.strip() for l in log.splitlines() if l.strip()]


@pytest.fixture(scope="module")
def lab(require_installed):
    _lab("up")
    yield
    _lab("down")
    # Sau khi gỡ, KHÔNG được còn dấu vết. Bắt được: có lần `down` để lại 1
    # tiến trình dpi và 10 rule ufw gắn nhãn "z2d lab DPI".
    # BẫY: dict {"a": "0"} vẫn truthy, nên `not _lab_scratch()` luôn False và
    # teardown luôn đỏ dù lab đã dọn sạch. Phải so TỪNG GIÁ TRỊ.
    residue = {k: v for k, v in _lab_scratch().items() if str(v).strip() != "0"}
    assert not residue, f"lab để lại dấu vết: {residue}"


def _lab_scratch() -> dict:
    nft = run(["sh", "-c", "nft list tables 2>/dev/null | grep -c z2d_lab"],
              sudo=True, timeout=30).out.strip()
    ufw = run(["sh", "-c", "ufw status 2>/dev/null | grep -c 'z2d lab DPI'"],
              sudo=True, timeout=30).out.strip()
    pid = run(["sh", "-c", "ps -eo args --no-headers | grep -c '[l]ab/dpi.py'"],
              sudo=True, timeout=30).out.strip()
    return {"nft_table": nft, "ufw_rules": ufw, "dpi_procs": pid}


def _zapret2(state: str):
    run(["systemctl", state, "zapret2"], sudo=True, timeout=60)
    time.sleep(4)          # cần thời gian để hook NFQUEUE dựng lại
    assert run(["sh", "-c", "systemctl is-active zapret2"],
               sudo=True, timeout=30).out.strip() == ("active" if state == "start" else "inactive")


def test_desync_defeats_sni_based_dpi(lab):
    """Cùng một lệnh, chỉ khác zapret2 bật/tắt ⇒ kết quả phải đảo.

    · zapret2 CHẠY → đoạn đầu 1 byte → DPI không thấy tên miền → HTTP 200
    · zapret2 DỪNG  → DPI thấy nguyên ClientHello → chặn        → HTTP 0
    · domain KHÔNG bị chặn phải 200 Ở CẢ HAI nhánh, nếu không thì lab chỉ
      đang làm hỏng mọi thứ chứ không chứng minh gì.
    """
    _zapret2("start")
    ok_on = _fetch("github.com", BLOCKED_IP)
    ctl_on = _fetch("kernel.org", ALLOWED_IP)
    saw_on = _dpi_saw()

    _zapret2("stop")
    ok_off = _fetch("github.com", BLOCKED_IP)
    ctl_off = _fetch("kernel.org", ALLOWED_IP)
    saw_off = _dpi_saw()
    _zapret2("start")

    assert ctl_on == 200 and ctl_off == 200, (
        f"domain đối chứng phải 200 ở cả hai nhánh, thực tế {ctl_on} / {ctl_off}"
    )
    assert ok_on == 200, f"zapret2 chạy mà domain bị chặn vẫn không vào được ({ok_on})"
    assert ok_off == 0, f"zapret2 dừng mà domain bị chặn vẫn vào được ({ok_off})"
    assert any("SNI=None" in l for l in saw_on), \
        f"không thấy dấu hiệu SNI bị giấu khi zapret2 chạy: {saw_on[-4:]}"
    assert any("github.com" in l and "CHẶN" in "".join(saw_off) for l in saw_off) or \
           "CHẶN" in "".join(saw_off), \
        f"DPI không ghi nhận chặn khi zapret2 dừng: {saw_off[-4:]}"
