"""Fixture cho khung kiểm thử install.sh.

Nguyên tắc bắt buộc ở đây:
  * Mọi `subprocess` đều có timeout. Lệnh treo vô hạn làm treo cả phiên test.
  * Fixture nào làm ĐỔI MÁY thì phải hoàn nguyên trong `finally`, kể cả khi
    test fail. Phép thử không được để lại thiệt hại trên máy thật.
  * Thiếu điều kiện thì báo BLOCKED kèm danh sách thứ còn thiếu — tuyệt đối
    không trả về giá trị "0" rồi tưởng là đã kiểm.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from qa import archshim, state                      # noqa: E402
from qa.host import Blocked, Result, run           # noqa: E402

REPO = Path(__file__).resolve().parent.parent
INSTALL_SH = REPO / "install.sh"


# --------------------------------------------------------------------------- #
# Tuỳ chọn dòng lệnh — `pytest -m invariants --snapshot=2026.09 …`
# --------------------------------------------------------------------------- #
def pytest_addoption(parser):
    g = parser.getgroup("z2d", "hệ mạng 3 tầng")
    g.addoption("--snapshot", default="khong-gan",
                 help="nhãn snapshot OS, vd 2026.09 — ghi vào báo cáo lỗi")
    g.addoption("--kernel", default="auto", help="nhãn kernel, vd linux-cachyos")
    g.addoption("--nd-id", default=None, help="ID NextDNS để dùng khi cài/gỡ")
    g.addoption("--iface", default="enp8s0", help="NIC đo gói (chỉ wired)")
    g.addoption("--run-destructive", action="store_true", default=False,
                 help="cho phép chạy cài/gỡ thật. KHÔNG bật khi đang dùng máy "
                      "thật mà chưa có bản chụp.")


def pytest_configure(config):
    config.addinivalue_line("markers", "invariants: quét invariant §4")
    config.addinivalue_line("markers", "install: cần chạy cài")
    config.addinivalue_line("markers", "uninstall: cần chạy gỡ")
    config.addinivalue_line("markers", "destructive: đổi máy thật — cần --run-destructive")
    config.addinivalue_line("markers", "network: cần mạng thật")
    config.addinivalue_line("markers", "slow: chạy lâu")


# --------------------------------------------------------------------------- #
# Bắt buộc: testinfra phải biết pacman
# --------------------------------------------------------------------------- #
@pytest.fixture(scope="session", autouse=True)
def _patch_testinfra_for_pacman():
    archshim.install()
    yield


# --------------------------------------------------------------------------- #
# Hậu cần
# --------------------------------------------------------------------------- #
def pytest_report_header(config):
    k = run(["uname", "-r"], timeout=10).out.strip() or "?"
    return [
        f"z2d · snapshot={config.getoption('--snapshot')} · kernel={k} "
        f"({config.getoption('--kernel')})",
        f"z2d · iface={config.getoption('--iface')} · "
        f"destructive={'CHO PHEP' if config.getoption('--run-destructive') else 'khoang'}",
    ]


@pytest.fixture(scope="session")
def iface(pytestconfig):
    return pytestconfig.getoption("--iface")


@pytest.fixture(scope="session")
def nd_id(pytestconfig):
    v = pytestconfig.getoption("--nd-id")
    if not v:
        pytest.skip("thiếu --nd-id; cần ID NextDNS 6 ký tự để cài/gỡ")
    return v


@pytest.fixture(scope="session")
def sudo_ready():
    """Chỉ cho chạy phép cần quyền quản trị khi đã chuẩn bị đúng cách."""
    if not os.environ.get("SUDO_ASKPASS"):
        pytest.skip("thiếu SUDO_ASKPASS — chạy:  SUDO_ASKPASS=/tmp/.zz.sh pytest …")
    if not Path(os.environ["SUDO_ASKPASS"]).exists():
        pytest.skip(f"SUDO_ASKPASS trỏ tới tệp không tồn tại: {os.environ['SUDO_ASKPASS']}")
    return True


@pytest.fixture(scope="session")
def destructive(pytestconfig):
    if not pytestconfig.getoption("--run-destructive"):
        pytest.skip("phép thử phá huỷ — bật bằng --run-destructive khi đã có bản chụp")
    return True


# --------------------------------------------------------------------------- #
# Cô lập cho test phá-huỷ — thay thế cho snapshot của VM
# --------------------------------------------------------------------------- #
#   VÌ SAO CẦN: đặc tả PHA 3 cô lập bằng snapshot VM (revert trong `finally`).
#   Máy này không có VM, nếu không làm thay thế thì các test phá-huỷ sẽ để lại
#   máy ở trạng thái của test trước, và test sau sẽ hỏng vì lý do sai —
#   tệ hơn nhiều so với không có test.
#
#   Cách làm: ghi nhớ trạng thái ĐẦU PHIÊN, đảm bảo mỗi test có đúng tiền đề
#   kiện nó cần, và cuối phiên trả máy về đúng trạng thái ban đầu.
def _is_installed() -> bool:
    from qa import state
    return bool(state.nft_z2d_tables())


@pytest.fixture(scope="session", autouse=True)
def _restore_machine_at_session_end(request, pytestconfig):
    """Trả máy về đúng trạng thái lúc ĐẦU PHIÊN, kể cả khi test fail.

    BẪY ĐÃ DÍNH: bản đầu viết `if was != now: uninstall(...)` — nghĩa là chạy
    uninstall để "khôi phục", nhưng uninstall chỉ đưa máy về SẠCH. Nếu đầu
    phiên máy ĐANG CÀI thì sau khi uninstall ta còn phải CÀI LẠI, không phải
    uninstall thêm. Phiên đầu tiên lộ ra: assert `_is_installed() == was` đỏ
    với `where False = _is_installed()`.
    """
    was = _is_installed()
    nd = pytestconfig.getoption("--nd-id")
    yield
    now = _is_installed()
    if was == now:
        return
    from qa.host import INSTALL_SH, LONG_TIMEOUT, run
    if now and not was:
        run(["bash", str(INSTALL_SH), "--uninstall"], sudo=True, timeout=LONG_TIMEOUT)
    elif was and not now:
        if not nd:
            pytest.fail(
                "phiên bắt đầu lúc hệ ĐANG CÀI, giờ đã bị gỡ, mà không có --nd-id "
                "để cài lại. Hãy chạy lại bằng:  --nd-id <id> --run-destructive"
            )
        r = run(["bash", str(INSTALL_SH), "--nd-id", nd], sudo=True, timeout=LONG_TIMEOUT)
        assert r.rc == 0, "không cài lại được để trả máy về trạng thái đầu phiên"
    assert _is_installed() == was, (
        f"không trả lại được trạng thái đầu phiên (cần {'đã cài' if was else 'chưa cài'})"
    )


@pytest.fixture
def needs_installed():
    """BỎ QUA (kèm lý do) nếu hệ chưa cài — cho test chỉ đọc.

    Vì sao không `fail`: test chỉ đọc phải chạy được trên máy CHƯA cài mà không
    đỏ vì lý do không liên quan. Bản đầu `test_config.py` giả định hệ đang cài
    mà không khai báo, nên khi phiên bắt đầu lúc máy đã gỡ, 4 test đỏ vì
    "thiếu tệp" — hoàn toàn không liên quan tới chất lượng cấu hình.

    Chạy đầy đủ:  pytest --nd-id <id> --run-destructive
    """
    if not _is_installed():
        pytest.skip(
            "hệ 3 tầng chưa cài — test này kiểm cấu hình khi đang chạy. "
            "Chạy kèm `--run-destructive --nd-id <id>` để kiểm đầy đủ."
        )
    return True


@pytest.fixture
def require_installed(destructive, nd_id):
    """Bảo đảm hệ đang CÀI trước khi chạy test — tiền đề kiện, không phải hành động.

    Thiếu nó thì test có thể xanh vì hệ thống KHÔNG CÓ GÌ, hoặc đỏ vì hệ thống
    chưa cài. Cả hai đều là kết quả vô nghĩa.
    """
    from qa.host import INSTALL_SH, LONG_TIMEOUT, run
    if not _is_installed():
        r = run(["bash", str(INSTALL_SH), "--nd-id", nd_id],
                sudo=True, timeout=LONG_TIMEOUT)
        assert r.rc == 0, "không cài được để chuẩn bị tiền đề kiện: " + r.describe()
    return True


@pytest.fixture
def require_clean(destructive, nd_id):
    """Bảo đảm hệ KHÔNG có gì trước khi chạy test."""
    from qa.host import INSTALL_SH, LONG_TIMEOUT, run
    if _is_installed():
        run(["bash", str(INSTALL_SH), "--uninstall"], sudo=True, timeout=LONG_TIMEOUT)
    return True
    """Bảo đảm hệ KHÔNG có gì trước khi chạy test."""
    from qa.host import INSTALL_SH, LONG_TIMEOUT, run
    if _is_installed():
        run(["bash", str(INSTALL_SH), "--uninstall"], sudo=True, timeout=LONG_TIMEOUT)
    return True


# --------------------------------------------------------------------------- #
# `vm` — đúng như đặc tả PHA 3, nhưng phải báo BLOCKED thay vì bịa
# --------------------------------------------------------------------------- #
_MISSING_VM = ("qemu-system-x86_64", "qemu-img")


@pytest.fixture(scope="session")
def vm(destructive):
    """VM QEMU boot từ snapshot sạch; `finally` revert về ảnh gốc.

    Đặc tả yêu cầu mọi thực thi trong VM. Máy này **không có** QEMU, nên
    fixture này BLOCKED — báo đúng thứ còn thiếu thay vì âm thầm chạy test
    phá-huỷ ngay trên máy thật. Khi đã cài QEMU, chỗ cần điền là `_boot()`.
    """
    missing = [b for b in _MISSING_VM if shutil.which(b) is None]
    if missing:
        raise Blocked(
            "Thiếu công cụ VM: " + ", ".join(missing) + ". "
            "Đặc tả PHA 2 yêu cầu mọi thực thi trong VM. "
            "Cách thay thế: chạy với backend `local` + `--run-destructive`, "
            "chụp `/var/backups` + nft ruleset trước mỗi lớp test."
        )
    raise Blocked("chưa cài đặt ảnh ISO/snapshot — cần hoàn thiện _boot()")


# --------------------------------------------------------------------------- #
# Đoạn đo trạng thái — "nguồn sự thật" (nhóm T8)
# --------------------------------------------------------------------------- #
@pytest.fixture
def state_marker():
    return state.marker()


@pytest.fixture(scope="session")
def raw_socket():
    """Bắt gói thẳng trên NIC cần `CAP_NET_RAW` — tức phải là root.

    Đặc tả PHA 3 giả định chạy trong VM nên luôn là root. Trên máy thật thì
    phải nâng cả phiên pytest, không nâng riêng một test (nâng riêng thì fixture
    `offload_off` sẽ tắt offload bằng user thường rồi hỏng giữa chừng).

    Không tự ý `sudo` bên trong test: test chạy vô hình dưới quyền khác là
    mất khả năng khôi phục khi hỏng. Thay vào đó báo rõ cách chạy.
    """
    if os.geteuid() != 0:
        pytest.skip(
            "cần root cho CAP_NET_RAW (bắt gói trên NIC). Chạy:  "
            "SUDO_ASKPASS=/tmp/.zz.sh sudo -A <python> -m pytest …"
        )
    return True


@pytest.fixture
def offload_off(iface):
    """Tắt offload khi đo gói; BẬT LẠI trong `finally` kể cả khi test fail."""
    from qa.wire import offload
    with offload(iface, on=True) as current:
        # `current` là trạng thái SAU khi tắt — đó là thứ test cần kiểm chứng.
        # Trạng thái GỐC được `offload()` giữ và tự khôi phục trong `finally`.
        yield current
