"""Chạy lệnh trên máy đang kiểm, có chặn trên timeout bắt buộc."""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

#: Không có timeout thì một lệnh chờ vô hạn sẽ treo cả phiên test. Bắt buộc.
DEFAULT_TIMEOUT = 30

#: Lệnh cài/gỡ mất vài phút (git clone + make). Tách riêng để nhìn thấy.
LONG_TIMEOUT = 900

#: Đường dẫn tới installer — đặt ở đây để test nào cũng dùng chung một nguồn,
#: không mỗi tệp tự chế đường dẫn rồi lệch nhau.
REPO = Path(__file__).resolve().parent.parent.parent
INSTALL_SH = REPO / "install.sh"


class Blocked(Exception):
    """Không thể chạy phép kiểm vì thiếu điều kiện — KHÁC với "kiểm ra fail".

    Dùng exception này thay vì `pytest.skip` khi người đọc cần biết *còn thiếu
    gì*. `pytest.skip` in "skipped" trống trơn, dễ bị đọc nhầm là đã kiểm.
    """


@dataclass(frozen=True)
class Result:
    cmd: list[str]
    rc: int
    out: str
    err: str
    timed_out: bool = False

    @property
    def ok(self) -> bool:
        return self.rc == 0 and not self.timed_out

    def describe(self) -> str:
        head = " ".join(self.cmd[:6])
        if self.timed_out:
            return f"{head} → HẾT GIỜ ({self.cmd and ''}{DEFAULT_TIMEOUT}s)"
        return f"{head} → rc={self.rc}\n  stdout: {self.out.strip()[:300]}\n  stderr: {self.err.strip()[:300]}"


def run(cmd, *, timeout: int = DEFAULT_TIMEOUT, sudo: bool = False,
        env: dict | None = None, stdin: str | None = None) -> Result:
    """Chạy một lệnh. `timeout` là tham số bắt buộc về mặt ý nghĩa.

    `sudo` đi qua `sudo -A` (askpass) chứ không `printf | sudo -S`: cái sau
    làm PAM conversation hỏng và có thể khoá tài khoản.
    """
    if timeout is None:
        raise ValueError("timeout=None không được phép — lệnh sẽ treo vô hạn")
    argv = list(cmd) if isinstance(cmd, (list, tuple)) else ["sh", "-c", cmd]
    if sudo:
        if not os.environ.get("SUDO_ASKPASS"):
            raise Blocked(
                "Cần SUDO_ASKPASS trỏ tới chương trình in mật khẩu quản trị. "
                "Cách dùng: SUDO_ASKPASS=/tmp/.zz.sh pytest …  "
                "(KHÔNG dùng `printf | sudo -S` — PAM conversation hỏng.)"
            )
        argv = ["sudo", "-A", *argv]
    e = dict(os.environ)
    e.setdefault("LC_ALL", "C.UTF-8")   # đệm theo ký tự, không theo byte
    if env:
        e.update(env)
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                           env=e, input=stdin)
        return Result(argv, p.returncode, p.stdout, p.stderr)
    except subprocess.TimeoutExpired as ex:
        out = ex.stdout.decode() if isinstance(ex.stdout, bytes) else (ex.stdout or "")
        err = ex.stderr.decode() if isinstance(ex.stderr, bytes) else (ex.stderr or "")
        return Result(argv, 124, out, err, timed_out=True)
    except FileNotFoundError as ex:
        return Result(argv, 127, "", f"không có lệnh: {ex}")


def have(cmd: str) -> bool:
    return shutil.which(cmd) is not None
