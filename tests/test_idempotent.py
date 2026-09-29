"""Chạy lại nhiều lần phải an toàn — nhóm T2 của đặc tả."""

from __future__ import annotations

import pytest

from qa import state
from qa.host import INSTALL_SH, LONG_TIMEOUT, run


def _install(nd_id, timeout):
    return run(["bash", str(INSTALL_SH), "--nd-id", nd_id],
               sudo=True, timeout=timeout)


@pytest.mark.install
@pytest.mark.destructive
def test_install_twice_does_not_duplicate_rules(require_installed, nd_id):
    """Cài hai lần ⇒ số rule không nhân đôi.

    Đây là ca đã bắt được lỗi `ufw_has` không bỏ qua rule đã có: bản đầu
    thêm trùng nên 20 rule biến thành 36.
    """
    _install(nd_id, LONG_TIMEOUT)
    n1 = len(state.ufw_rules())
    _install(nd_id, LONG_TIMEOUT)
    n2 = len(state.ufw_rules())
    assert n1 == n2, f"cài lần 2 làm rule nhân bản: {n1} → {n2}"


@pytest.mark.install
@pytest.mark.destructive
def test_second_install_does_not_poison_backup(require_installed, nd_id):
    """Bản sao lưu phải giữ bản ĐẦU, không bị ghi đè bằng tệp đã sửa.

    Đây là lỗi S2 đã sửa: `rm -rf "$BACKUP"` ở cuối bước 2 khiến lần cài sau
    chép lại chính tệp đã sửa ⇒ uninstall không bao giờ về bản gốc của gói.
    """
    _install(nd_id, LONG_TIMEOUT)
    first = run(["sh", "-c",
                 "sha256sum /var/backups/zapret2-dotfile/etc/default/ufw 2>/dev/null"],
                sudo=True, timeout=30).out.split()[0]
    _install(nd_id, LONG_TIMEOUT)
    second = run(["sh", "-c",
                  "sha256sum /var/backups/zapret2-dotfile/etc/default/ufw 2>/dev/null"],
                 sudo=True, timeout=30).out.split()[0]
    assert first == second, (
        f"bản sao lưu bị ghi đè giữa hai lần cài: {first[:12]} → {second[:12]}"
    )
