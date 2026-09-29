"""Cho `testinfra` biết CachyOS là Arch, để `host.package` dùng được `pacman`.

Vì sao cần: `testinfra.modules.package` chọn backend theo
`system_info.distribution in ("arch", "manjarolinux")`. Máy này là CachyOS,
`/etc/os-release` có `ID=cachyos`, `ID_LIKE=arch`. testinfra đọc `ID` nên ra
`cachyos` → không khớp → `NotImplementedError` (đã bắt được, không đoán).

Đo được trước khi có shim:
    test_pkg[local]  →  NotImplementedError
Sau khi có shim:
    test_pkg[local]  →  qua, dùng `pacman -Q <tên>` (đúng lệnh của ArchPackage)
"""

from __future__ import annotations

from testinfra.modules.package import ArchPackage, Package

_PATCHED_FLAG = "_z2d_pacman_shim"


def install() -> None:
    """Đăng ký ArchPackage cho các bản phân phối `ID_LIKE=arch`."""
    if getattr(Package.get_module_class, _PATCHED_FLAG, False):
        return
    original = Package.get_module_class.__func__

    def get_module_class(cls, host):
        dist = (host.system_info.distribution or "").lower()
        if dist in ("cachyos", "arch", "manjarolinux", "endeavouros", "garuda", "artix"):
            return ArchPackage
        return original(cls, host)

    setattr(get_module_class, _PATCHED_FLAG, True)
    Package.get_module_class = classmethod(get_module_class)
