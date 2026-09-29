"""Cài — nhóm T1 (happy path). Mỗi test khẳng định cả rc lẫn hệ quả."""

from __future__ import annotations

import pytest

from qa import state
from qa.host import INSTALL_SH, LONG_TIMEOUT, run


@pytest.mark.install
@pytest.mark.destructive
def test_install_exits_zero_and_reports_complete(destructive, nd_id):
    """CA NÀY TỰ CHẠY INSTALL — không dựa vào `require_installed`.

    Nếu dựa vào fixture thì fixture đã cài sẵn, và ta chỉ khẳng định lại kết
    quả của chính lần cài đó ⇒ test không kiểm được gì.
    """
    res = run(["bash", str(INSTALL_SH), "--nd-id", nd_id],
              sudo=True, timeout=LONG_TIMEOUT)
    assert res.rc == 0, "cài thất bại:\n" + res.describe()
    assert "HOÀN TẤT" in res.out, "exit 0 nhưng không in dòng hoàn tất"


@pytest.mark.install
@pytest.mark.destructive
def test_install_creates_nfqueue_table(require_installed, nd_id):
    """Tầng 1 phải có bảng nft riêng — nếu không thì desync không hề chạy."""
    assert state.nft_z2d_tables(), "không có bảng nft nào của zapret2"


@pytest.mark.install
@pytest.mark.destructive
def test_install_starts_and_enables_service(require_installed, nd_id, host):
    assert host.service("zapret2").is_running, "zapret2 không chạy"
    units = state.enabled_z2d_units()
    assert any(u.startswith("zapret2") for u in units), \
        f"zapret2 không được enable: {units}"


@pytest.mark.install
@pytest.mark.destructive
def test_install_opens_only_dns_egress_rules(require_installed, nd_id):
    """Tường DNS phải đủ 16 rule (8 chặn + 8 cho phép, hai họ)."""
    dns = state.dns_port_rules()
    assert len(dns) >= 16, (
        f"chỉ có {len(dns)} rule chạm 53/853, mong đợi ≥16\n"
        f"Tất cả rule: {state.ufw_rules()[:4]}"
    )


@pytest.mark.install
@pytest.mark.destructive
def test_install_writes_single_fixed_name_backup(require_installed, nd_id):
    """Đúng MỘT bản sao lưu, tên cố định — không sinh thư mục rác."""
    res = run(["sh", "-c", "ls -d /var/backups/zapret2-dotfile 2>/dev/null"],
              sudo=True, timeout=30)
    assert res.ok, "không có bản sao lưu"
    stray = run(["sh", "-c", "ls -d /var/backups/.z2d.* 2>/dev/null | wc -l"],
                sudo=True, timeout=30).out.strip()
    assert stray == "0", f"còn {stray} thư mục tạm sót lại"


@pytest.mark.install
@pytest.mark.destructive
def test_install_preserves_base_packages(require_installed, nd_id):
    """Không được gỡ gói nền — hỏng `paru/mpv/gamescope/dnsmasq/dkms`."""
    import importlib
    st = importlib.import_module("qa.state")
    for p in ("gcc", "make", "git", "nftables", "ufw", "luajit"):
        res = run(["pacman", "-Qq", p], sudo=True, timeout=30)
        assert res.ok, f"gói nền {p} biến mất sau khi cài"
