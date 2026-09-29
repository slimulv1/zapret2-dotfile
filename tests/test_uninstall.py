"""Gỡ cài — nhóm "uninstall clean" của đặc tả.

Nguyên tắc: "gỡ xong" **không** phải là "script in dòng OK". Phải là **state-diff
rỗng** so với trước khi cài, phần chênh còn lại đều phải là thứ có tài liệu.

Đây là nơi hai lỗi S2 từng lọt qua: bản sao lưu bị "đầu" làm
`/etc/default/ufw` không bao giờ về bản gốc của gói, và cờ `ENABLED` của ufw
không được khôi phục. `test_package_files_returned_to_pristine` và
`test_ufw_enabled_state_restored` là hai cái lưới bắt đúng hai lỗi đó.
"""

from __future__ import annotations

import pytest

from qa import state
from qa.host import INSTALL_SH, LONG_TIMEOUT, run


def _backup_read(name: str) -> str:
    return run(["sh", "-c", f"cat /var/backups/zapret2-dotfile/{name} 2>/dev/null"],
               sudo=True, timeout=30).out.strip()


@pytest.mark.uninstall
@pytest.mark.destructive
def test_uninstall_restores_backed_up_package_file_to_pristine(destructive, nd_id):
    """Tệp của GÓI mà hệ 3 tầng sửa và CÓ sao lưu ⇒ phải về đúng byte gốc.

    Giới hạn phạm vi: chỉ `/etc/default/ufw`.

    Bản đầu của test này đòi "không tệp gói nào còn khác byte" và **sai**:
      * `/etc/ufw/user.rules` + `user6.rules` — `ufw` tự viết lại (khai báo
        chuỗi `:ufw-*-logging-*`), đây là sổ của nó, không phải dấu vết của ta.
        Đo được: sau uninstall còn **0** dòng chứa `45.90.` / `2a07:a8c` / `1714`.
      * `/etc/ufw/ufw.conf` — khác đúng dòng `ENABLED`. Máy này vốn đã bật ufw
        trước khi cài, nên khôi phục về `yes` là **đúng**, đòi về `no` mới sai.
    Đòi byte-pristine cho tất cả là đòi sai, nên test đỏ vì lý do không liên
    quan. Bản đúng: kiểm tệp ta thật sự sửa, và kiểm sạch về mặt CHỨC NĂNG.
    """
    run(["bash", str(INSTALL_SH), "--uninstall"], sudo=True, timeout=LONG_TIMEOUT)
    dirty = state.pacman_modified_files().get("ufw", [])
    assert "/etc/default/ufw" not in dirty, (
        f"/etc/default/ufw vẫn khác bản gốc của gói sau uninstall. "
        f"Đây là lỗi S2 'F-item không revert'. Nguyên nhân thường gặp — bản sao lưu "
        f"đã bị 'đầu' (chứa tệp ĐÃ sửa):\n"
        f"  sudo grep -c z2d /var/backups/zapret2-dotfile/etc/default/ufw\n"
        f"  ra 1 ⇒ cần: sudo rm -rf /var/backups/zapret2-dotfile rồi cài lại từ đầu."
    )


@pytest.mark.uninstall
@pytest.mark.destructive
def test_uninstall_leaves_no_z2d_content_in_ufw_rules(destructive, nd_id):
    """Sau gỡ, KHÔNG còn dấu vết của hệ 3 tầng trong bảng rule — theo nội dung.

    Đây là tiêu chí đúng: `ufw` viết lại tệp của nó theo cách riêng, nên phải
    kiểm NỘI DUNG thay vì so byte. Đo được 0 dòng chứa các mẫu dưới đây.
    """
    run(["bash", str(INSTALL_SH), "--uninstall"], sudo=True, timeout=LONG_TIMEOUT)
    for f in ("/etc/ufw/user.rules", "/etc/ufw/user6.rules"):
        res = run(["sh", "-c", f"grep -cE '45\\.90\\.|2a07:a8c|1714|z2d' {f}"],
                  sudo=True, timeout=30)
        n = res.out.strip()
        assert n == "0", f"{f} còn {n} dòng dấu vết của hệ 3 tầng"


@pytest.mark.uninstall
@pytest.mark.destructive
def test_ufw_enabled_state_restored(require_installed, nd_id):
    """Cờ bật/tắt của ufw phải về đúng trạng thái trước khi cài.

    Bẫy đã dính: cờ `ENABLED` nằm trong `/etc/ufw/ufw.conf`, KHÔNG phải trong
    `ufw-policy-in.txt` (file đó chỉ lưu allow/deny). Không lưu cờ này thì
    uninstall để lại tường bật dù người dùng chưa từng bật.
    """
    saved = _backup_read("ufw-enabled.txt")
    assert saved in ("yes", "no"), \
        f"backup không lưu trạng thái bật/tắt của ufw (đọc được {saved!r}) — " \
        f"uninstall sẽ không khôi phục được"
    now = run(["sh", "-c", "sed -n 's/^ENABLED=//p' /etc/ufw/ufw.conf"],
              sudo=True, timeout=30).out.strip()
    assert now == saved, \
        f"ufw đang {now!r} nhưng trước khi cài là {saved!r}"


@pytest.mark.uninstall
@pytest.mark.destructive
def test_uninstall_leaves_no_z2d_trace_in_rules(require_installed, nd_id):
    """Không còn rule nào ghi chú z2d."""
    run(["bash", str(INSTALL_SH), "--uninstall"], sudo=True, timeout=LONG_TIMEOUT)
    left = [r for r in state.ufw_rules() if "z2d" in r]
    assert not left, f"còn {len(left)} rule z2d sót lại: {left[:5]}"


@pytest.mark.uninstall
@pytest.mark.destructive
def test_uninstall_removes_nfqueue_table(require_installed, nd_id):
    run(["bash", str(INSTALL_SH), "--uninstall"], sudo=True, timeout=LONG_TIMEOUT)
    assert not state.nft_z2d_tables(), \
        f"bảng nft của zapret2 còn sót: {state.nft_z2d_tables()}"
