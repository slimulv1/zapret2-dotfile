"""Chụp và so trạng thái hệ thống — "nguồn sự thật" của PHA 2 / nhóm T8.

Vì sao cần: `install.sh` in ra 16 phép kiểm riêng, nhưng chúng in ra **ý kiến
của chính script**. Muốn biết script có đúng không thì phải so trạng thái thật
trước / sau, không tin lời script.

Phân loại mọi khác biệt thành đúng ba loại, không có loại thứ tư:
    BẢN THÂN    — hệ 3 tầng chủ động tạo ra, cần có
    INTENTIONAL — có tài liệu nói rõ, chấp nhận
    LEFTOVER    — còn sót sau uninstall ⇒ nghi vấn, phải điều tra
"""

from __future__ import annotations

import re
import time
from pathlib import Path

from .host import Result, run

#: sysctl do gói `cachyos-settings` sở hữu — KHÔNG được coi là LEFTOVER
#: (đặc tả PHA 1: mọi sysctl-diff phải whitelist theo gói này).
CACHYOS_SYSCTL_OWNER = "/usr/lib/sysctl.d/70-cachyos-settings.conf"

#: Đường dẫn do hệ 3 tầng tạo — đối chiếu được, tồn tại là BẢN THÂN.
Z2D_OWNED = (
    "/etc/sysctl.d/60-z2d-hardening.conf",
    "/etc/ufw/z2d-sysctl.conf",
    "/etc/pacman.d/hooks/z2d-pacman-ufw.hook",
    "/etc/systemd/system/ufw.service.d",
)

#: Tệp của GÓI mà hệ 3 tầng sửa có chủ đích (khôi phục được nhờ backup).
#: Nằm trong danh sách backup của install.sh — nếu thoát khỏi danh sách đó
#: thì uninstall không còn khôi phục được ⇒ phải báo LEFTOVER.
Z2D_MODIFIES = ("/etc/default/ufw",)

#: sysctl mà hệ 3 tầng đặt. Dùng để tách khỏi khoá của gói CachyOS.
Z2D_SYSCTL = "/etc/sysctl.d/60-z2d-hardening.conf"

#: Tệp mà `IPT_SYSCTL` trong /etc/default/ufw PHẢI trỏ tới.
#: LƯU Ý: nó KHÁC tệp trên. Ban đầu tôi viết test so
#: `/etc/ufw/60-z2d-hardening.conf` ⇒ FAIL, rồi tưởng máy hỏng. Máy đúng;
#: tên tệp trong test là sai. Đo lại:
#:     IPT_SYSCTL=/etc/ufw/z2d-sysctl.conf
Z2D_UFW_SYSCTL = "/etc/ufw/z2d-sysctl.conf"


def _r(res: Result, default: str = "") -> str:
    return res.out if res.ok else default


def pacman_modified_files(pkgs=("ufw", "nftables", "systemd")) -> dict[str, list[str]]:
    """Tệp của gói mà nội dung đã khác bản gốc — nhờ `pacman -Qkk`.

    BẪY ĐÃ DÍNH: `pacman -Qkk` KHÔNG dùng chữ `modified:`. Nó ghi
    `"... (SHA256 checksum mismatch)"`. Lọc bằng `grep modified:` cho **0 giả**,
    tưởng không tệp nào bị sửa — trong khi thật ra có 4. Đừng lọc kiểu đó.
    """
    out: dict[str, list[str]] = {}
    for p in pkgs:
        res = run(["pacman", "-Qkk", p], sudo=True, timeout=60)
        hits = []
        for line in res.out.splitlines():
            if "SHA256 checksum mismatch" not in line:
                continue
            m = re.search(r": (\S+) \(SHA256", line)
            if m:
                hits.append(m.group(1))
        out[p] = sorted(hits)
    return out


def sysctl_map(path: str) -> dict[str, str]:
    """Đọc một tệp sysctl.d thành {khoá: giá trị}. Không đoán tệp thiếu."""
    res = run(["sh", "-c", f"cat {path} 2>/dev/null"], sudo=True, timeout=30)
    out = {}
    for line in res.out.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip()
    return out


def sysctl_conflicts() -> dict[str, tuple[str, str]]:
    """Khoá bị đặt ở CẢ `60-z2d-hardening.conf` LẪN tệp của cachyos-settings.

    `systemd-sysctl` áp theo thứ tự TÊN tệp, không theo thứ tự thư mục, nên
    `70-` chạy SAU `60-` và thắng. Trùng khoá ⇒ cấu hình z2d bị ghi đè im lặng.
    """
    z = sysctl_map(Z2D_SYSCTL)
    c = sysctl_map(CACHYOS_SYSCTL_OWNER)
    return {k: (z[k], c[k]) for k in sorted(set(z) & set(c))}


def enabled_z2d_units() -> list[str]:
    """Tên unit đang enable, giữ nguyên hậu tố (vd `zapret2.service`)."""
    res = run(["sh", "-c", "systemctl list-unit-files --state=enabled"],
              sudo=True, timeout=30)
    return sorted(l.split()[0] for l in res.out.splitlines() if l.startswith("zapret2"))


def ufw_rules() -> list[str]:
    res = run(["ufw", "status"], sudo=True, timeout=30)
    return [l for l in res.out.splitlines() if "ALLOW" in l or "DENY" in l]


def dns_port_rules() -> list[str]:
    """Rule nào chạm cổng 53 hoặc 853.

    BẪY ĐÃ DÍNH: `ufw status` in cổng theo dạng `53/udp`, `853/tcp` — KHÔNG
    phải `/53`. Lọc bằng `"/53" in dòng` ⇒ **0 dòng khớp**, và test báo "chỉ có
    0 rule DNS" trong khi máy có 16. Dùng biểu thức đúng định dạng thật.
    """
    import re
    pat = re.compile(r"\b(?:53|853)/(?:udp|tcp)\b")
    return [l for l in ufw_rules() if pat.search(l)]


def nft_z2d_tables() -> list[str]:
    res = run(["nft", "list", "tables"], sudo=True, timeout=30)
    return sorted(l for l in res.out.splitlines() if "zapret" in l)


def scratch_tables() -> list[str]:
    """Bảng `inet` tên lạ — dấu hiệu phép thử trước quên dọn.

    Chính tôi đã từng để lại `inet z2d_qa_test` và `inet z2d_qa_v6` rồi phải
    xoá tay. Khung test phải tự bắt được việc đó thay vì trông bằng mắt.
    """
    res = run(["nft", "list", "tables"], sudo=True, timeout=30)
    known = {"table ip filter", "table ip6 filter"}
    return sorted(l for l in res.out.splitlines()
                  if l.startswith("table ") and l not in known
                  and not any(k in l for k in ("zapret2", "inet filter", "ip filter",
                                               "ip6 filter", "nftables")))


def ufw_scratch_files() -> list[str]:
    """Tệp dư do `ufw` tự sinh: `<tên>.<YYYYmmdd_HHMMSS>` trong /etc/ufw.

    Không phải lỗi của install.sh (grep không có `ufw/after` trong mã), và
    đã đo là **không tăng thêm** sau một lần cài. Ghi ra để không ai quy nhầm
    là rò rỉ đang chạy.
    """
    res = run(["sh", "-c", "ls -1 /etc/ufw/ 2>/dev/null"], sudo=True, timeout=30)
    return sorted(l for l in res.out.splitlines() if re.search(r"\.\d{8}_\d{6}$", l))


def marker() -> Path:
    """Mốc thời gian để `find -newer` lập danh sách tệp vừa thay đổi."""
    p = Path("/tmp/z2d-qa/.state-marker")
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(str(time.time()))
    return p


def etc_newer_than(mark: Path) -> list[str]:
    res = run(["sh", "-c", f"find /etc -xdev -newer {mark} -type f 2>/dev/null | sort"],
              sudo=True, timeout=120)
    return sorted(res.out.split())


def classify(path: str) -> str:
    """Xếp một đường dẫn vào BẢN THÂN / INTENTIONAL / LEFTOVER / NGOÀI PHẠM VI."""
    if any(path.startswith(o) for o in Z2D_OWNED):
        return "BẢN THÂN"
    if path in Z2D_MODIFIES:
        return "INTENTIONAL"   # sửa tệp của gói, có trong backup để khôi phục
    return "CẦN XEM"
