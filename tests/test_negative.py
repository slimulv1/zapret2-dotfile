"""Ca âm — đường lỗi. Đo được bằng cách chạy thật, không giả định.

Mỗi ca kiểm MỘT hành vi: cho một đầu vào sai, installer phải **từ chối rõ
ràng** và **không để lại thay đổi**.
"""

from __future__ import annotations

import pytest

from qa.host import INSTALL_SH, LONG_TIMEOUT, run


def _state_fingerprint() -> tuple:
    """Vân tay trạng thái: đủ để chứng minh "không đổi gì cả"."""
    rules = run(["sh", "-c", "ufw status 2>/dev/null | grep -cE '(ALLOW|DENY)'"],
                sudo=True, timeout=30).out.strip()
    zap = run(["sh", "-c", "systemctl is-active zapret2"], sudo=True, timeout=30).out.strip()
    opt = run(["sh", "-c", "test -e /opt/zapret2 && echo co || echo khong"],
              sudo=True, timeout=30).out.strip()
    return (rules, zap, opt)


@pytest.mark.destructive
def test_rejects_bad_nd_id_and_changes_nothing(require_clean):
    """ID NextDNS sai định dạng phải bị chặn, và máy phải y nguyên."""
    before = _state_fingerprint()
    res = run(["bash", str(INSTALL_SH), "--dry", "--nd-id", "fffff"],
              sudo=True, timeout=120)
    assert res.rc != 0, f"installer chấp nhận ID sai: rc={res.rc}"
    # BẪY: `die()` in ra STDERR, không phải stdout. Chỉ soi `res.out` thì
    # thấy "OK đủ lệnh cần thiết" và tưởng installer chấp nhận ID sai.
    blob = res.out + res.err
    assert "6 ký tự hex" in blob or "hex" in blob.lower(), \
        f"thông báo lỗi không nói rõ chỗ sai: {blob[-250:]!r}"
    assert _state_fingerprint() == before, "máy đã đổi dù installer phải dừng"


@pytest.mark.destructive
def test_rejects_unknown_flag_without_touching_system(require_clean):
    before = _state_fingerprint()
    res = run(["bash", str(INSTALL_SH), "--khong-co-that"],
              sudo=True, timeout=120)
    assert res.rc != 0, "installer chấp nhận cờ không tồn tại"
    assert _state_fingerprint() == before, "máy đã đổi dù installer phải dừng"


@pytest.mark.destructive
def test_rejects_nd_id_with_leading_dash(require_clean):
    """Giá trị bắt đầu bằng `-` có thể bị parser nuốt thành cờ."""
    before = _state_fingerprint()
    res = run(["bash", str(INSTALL_SH), "--dry", "--nd-id", "--uninstall"],
              sudo=True, timeout=120)
    assert res.rc != 0, "installer nuốt mất giá trị cờ — nguy hiểm"
    assert _state_fingerprint() == before, "máy đã đổi"


@pytest.mark.destructive
def test_missing_installed_file_is_recreated_by_reinstall(require_clean, nd_id):
    """Tệp cấu hình đã cài mà bị mất ⇒ cài lại phải tự tạo lại.

    GHI ĐÁNH LƯU Ý SAI ĐÃ GHI NHẦM: tôi từng viết test "thiếu tệp config thì
    installer phải báo lỗi", và nó đỏ. Đo thì ra:
        `install.sh --dry --nd-id …` vẫn exit 0.
    Nguyên nhân: dòng "đủ 9 tệp config" kiểm tra thư mục `config/` CỦA REPO,
    không kiểm `/etc`. Đó là thiết kế — cài lại sẽ tự tạo lại tệp trên `/etc`.
    Nên đòi hành vi cũ là đòi sai. Bản đúng là khoá lại hành vi THẬT: tự chữa
    lành. Và nó vẫn bắt được lỗi nếu bước ghi cấu hình bị hỏng.
    """
    src = "/etc/sysctl.d/60-z2d-hardening.conf"
    run(["bash", str(INSTALL_SH), "--nd-id", nd_id], sudo=True,
        timeout=LONG_TIMEOUT)
    assert run(["sh", "-c", f"test -e {src}"], sudo=True, timeout=30).ok, \
        "cài xong mà chưa có tệp cấu hình"
    run(["rm", "-f", src], sudo=True, timeout=30)
    assert not run(["sh", "-c", f"test -e {src}"], sudo=True, timeout=30).ok, \
        "xoá không được — phép thử vô nghĩa"
    res = run(["bash", str(INSTALL_SH), "--nd-id", nd_id], sudo=True,
              timeout=LONG_TIMEOUT)
    assert res.rc == 0, "cài lại thất bại:\n" + res.describe()
    assert run(["sh", "-c", f"test -e {src}"], sudo=True, timeout=30).ok, \
        f"cài lại xong mà {src} vẫn mất — tầng 3 mất cấu hình"
