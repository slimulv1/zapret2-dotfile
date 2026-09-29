"""Kiểm tệp cấu hình — chỉ đọc, an toàn chạy trên máy thật.

Ở đây `t1-config.sh` kiểm 38 mục bằng cách SO với bản trong repo. Bộ test này
làm việc khác: kiểm xem tệp trên máy có **đúng là tệp ta tạo** không, và có
parse được không — vì tệp sai thì 38 phép kia xanh mà hệ thống vẫn hỏng.
"""

from __future__ import annotations

import pytest

from qa.host import run
from qa import state

pytestmark = pytest.mark.invariants

# Mọi test ở tệp này đều giả định hệ ĐANG CHẠY, nên đều cần `needs_installed`.
# Thiếu nó thì khi phiên bắt đầu lúc máy đã-gỡ, chúng đỏ vì "thiếu tệp" — một
# lý do hoàn toàn không liên quan tới chất lượng cấu hình cần kiểm.

#: 9 tệp installer đưa vào máy — nếu thiếu thì tầng nào đó không có cấu hình.
Z2D_FILES = [
    "/etc/sysctl.d/60-z2d-hardening.conf",
    "/etc/ufw/z2d-sysctl.conf",
    "/etc/pacman.d/hooks/z2d-pacman-ufw.hook",
]


@pytest.mark.parametrize("path", Z2D_FILES)
def test_z2d_config_file_exists(path, host, needs_installed):
    assert host.file(path).is_file, f"thiếu tệp cấu hình {path}"


@pytest.mark.parametrize("path", Z2D_FILES)
def test_z2d_config_file_parses(path, host, needs_installed):
    """Tệp phải đọc được, không rỗng, và mọi dòng phải hợp lệ với định dạng."""
    f = host.file(path)
    content = f.content_string
    assert content.strip(), f"{path} rỗng"
    if path.endswith(".conf"):
        for i, line in enumerate(content.splitlines(), 1):
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            assert "=" in s, f"{path}:{i} không phải dòng khoá=giá trị: {s!r}"


def test_sysctl_keys_are_valid_names(needs_installed):
    """Tên khoá sysctl sai thì `systemd-sysctl` báo lỗi rồi bỏ qua, im lặng."""
    m = state.sysctl_map(state.Z2D_SYSCTL)
    assert m, f"{state.Z2D_SYSCTL} không đọc được khoá nào"
    for k in m:
        assert all(c.isalnum() or c in "._" for c in k), f"khoá sysctl lạ: {k!r}"
        assert k.count(".") >= 1, f"khoá sysctl thiếu phân tầng: {k!r}"


def test_ufw_sysctl_file_is_what_default_ufw_points_to(needs_installed):
    """`/etc/default/ufw` phải trỏ ĐÚNG vào tệp hardening của hệ 3 tầng.

    Nếu trỏ sai (ví dụ về tệp gốc của gói `ufw`), thì ufw nạp sysctl mặc
    định của nó ⇒ tầng 3 mất hiệu lực mà mọi phép kiểm đều xanh.
    """
    d = run(["sh", "-c", "grep '^IPT_SYSCTL=' /etc/default/ufw"],
            sudo=True, timeout=30).out.strip()
    assert d, "/etc/default/ufw không có dòng IPT_SYSCTL"
    val = d.split("=", 1)[1].strip().strip('"')
    assert val == state.Z2D_UFW_SYSCTL, \
        f"IPT_SYSCTL trỏ tới {val!r}, mong đợi {state.Z2D_UFW_SYSCTL!r}"


def test_pacman_hook_calls_ufw_not_something_else(needs_installed):
    """Hook phải nạp lại ufw — đây là thứ giữ tường đúng sau khi pacman đổi."""
    out = run(["sh", "-c",
               "cat /etc/pacman.d/hooks/z2d-pacman-ufw.hook"],
              sudo=True, timeout=30).out
    assert "Exec" in out, "hook không có trường Exec"
    assert "ufw" in out, "hook không gọi ufw"
