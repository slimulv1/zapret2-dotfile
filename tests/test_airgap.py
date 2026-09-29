"""Mất mạng / thiếu công cụ — nhóm T5. Phải chết SẠCH, không treo, không cài nửa vời.

Mô phỏng bằng cách thu hẹp `PATH` để lệnh cần thiết biến mất, thay vì cắm
mạng thật. Cách này tự tái lập và không đụng đường truyền của máy.
"""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from qa.host import INSTALL_SH, LONG_TIMEOUT, run

FAKE = Path("/tmp/z2d-qa/fakebin")
KEEP = ("bash", "sh", "sed", "grep", "awk", "cat", "cp", "mv", "rm", "mkdir",
        "chmod", "chown", "ln", "tar", "git", "make", "gcc", "curl", "dig",
        "nft", "ufw", "systemctl", "ip", "uname", "id", "stat", "dirname",
        "basename", "date", "printf", "readlink", "tr", "sort", "comm",
        "find", "ls", "touch", "mktemp", "env", "getent", "install", "sleep",
        "expr", "tee", "head", "tail", "wc", "cut", "seq", "realpath")


@pytest.fixture
def no_pacman():
    """PATH không có `pacman` — mô phỏng máy không phải Arch."""
    if FAKE.exists():
        shutil.rmtree(FAKE)
    FAKE.mkdir(parents=True)
    for c in KEEP:
        src = shutil.which(c)
        if src:
            (FAKE / c).symlink_to(src)
    assert shutil.which("pacman", path=str(FAKE)) is None, "giả lập hỏng rồi"
    yield f"PATH={FAKE}"
    shutil.rmtree(FAKE, ignore_errors=True)


@pytest.mark.airgap
@pytest.mark.destructive
def test_dies_cleanly_when_pacman_missing(no_pacman, destructive, nd_id):
    """Không có `pacman` ⇒ chết với thông báo nói rõ, và **không** đụng gì.

    Yêu cầu: rc ≠ 0, có nhắc tới pacman, và vân tay trạng thái không đổi.
    """
    def fingerprint():
        return (run(["sh", "-c", "ufw status 2>/dev/null | grep -cE '(ALLOW|DENY)'"],
                    sudo=True, timeout=30).out.strip(),
                run(["sh", "-c", "systemctl is-active zapret2"],
                    sudo=True, timeout=30).out.strip())

    before = fingerprint()
    # KHÔNG truyền env={"PATH": FAKE} cho `run`: biến môi trường đó áp cho
    # chính lệnh `sudo`, mà `sudo` nằm ngoài FAKE ⇒ rc=127 "không có lệnh sudo"
    # và ta tưởng installer chạy được. PATH hẹp phải áp cho LỆNH BÊN TRONG.
    res = run(["env", no_pacman, "bash", str(INSTALL_SH), "--nd-id", nd_id],
              sudo=True, timeout=LONG_TIMEOUT)
    assert res.rc != 0, "không có pacman mà vẫn báo thành công"
    assert "pacman" in (res.out + res.err), \
        f"thông báo không nhắc tới pacman: {res.out[-200:]!r}"
    assert fingerprint() == before, "máy đã đổi dù installer phải dừng ở bước 1"


@pytest.mark.airgap
@pytest.mark.network
def test_help_works_without_touching_anything():
    """`--help` phải chạy được, in hướng dẫn, và thoát 0 — kể cả khi mất mạng."""
    res = run(["bash", str(INSTALL_SH), "--help"], sudo=True, timeout=60)
    assert res.rc == 0, f"--help trả rc={res.rc}: {res.describe()}"
    assert "--nd-id" in res.out and "--uninstall" in res.out, \
        "--help thiếu mô tả cờ"
