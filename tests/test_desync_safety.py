"""Kiểm an toàn của khối `NFQWS2_OPT` — chạy tĩnh, không cần root.

Lỗi nguy hiểm nhất mà bộ test này chặn:

**`fake` không kèm fooling** ⇒ hỏng mọi trang.
    `wiki.zapret.moe/Zapret2/desync/fake`: *«fake без ограничителей на tcp =
    гарантированный слом соединения»*. Đo trên máy này (`tests/bench-dpi.py`):
    ứng viên `nofool-fake` làm hỏng **5/5 trang TCP** và 2/5 trang HTTP/3, và
    đoạn đầu mang SNI `www.microsoft.com` — tên miền của *gói giả*.

Nửa còn lại là **chốt hồi quy**:

- **`fake` dùng fooling của TCP trong profile UDP** — `tcp_md5` là *tuỳ chọn
  TCP*, đặt vào UDP thì vô tác dụng: có tham số nên check "đã có fooling" xanh,
  nhưng gói giả vẫn tới đích.
- **Thiếu `--new` giữa các profile** — nfqws2 gộp chúng thành **một**. Đo bằng
  chính log của nó: 3 profile có `--new` cho `we have 4 user defined desync
  profile(s)`, thiếu `--new` chỉ còn `we have 1`.

Tất cả đều **thất lặng**: nfqws2 vẫn khởi động, vẫn `active`, vẫn đỡ tên miền.
Không có gì báo lỗi. Nên phải kiểm tĩnh.

MỨC ĐỘ CHẮC CHẮN — ĐỌC TRƯỚC KHI TIN
    `fake` không fooling là lỗi **đã tái hiện trên chính máy này**. Ba lỗi còn
    lại thì **chưa từng xảy ra trong repo này** — chúng là chốt hồi quy, thêm vì
    sửa cấu hình desync rất dễ làm hỏng ngầm. Nói rõ thế để không ai tưởng đã
    từng phải vá.

    Trong lúc làm, tôi từng tưởng file trong repo thiếu `--new` rồi báo nhầm là
    lỗi có thật. Đếm lại: `HEAD` có đủ 2/2 dòng. Tôi đọc nhầm một dòng bị cắt
    ngắn khi in ra. Bài học cho chính bài này: phải **đếm** (`grep -c`), không
    được **nhìn**.

CHẠY TĨNH CỐ TÌNH
    Không cần `nfqws2` chạy, không cần root, không chạm máy. Đọc thẳng tệp
    trong repo. Nhờ vậy lỗi bị chặn **trước khi** ai cài lên máy — chứ không
    phải sau khi đã hỏng.

TỰ THỬ LẤY LỖI
    Cuối tệp có hai bài test tiêm cấu hình xấu vào và đòi các check phải đỏ.
    Check mà không dính lỗi nào thì chỉ là trang trí.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

pytestmark = pytest.mark.invariants

OPT_FILE = Path(__file__).resolve().parent.parent / "config" / "z2d-zapret2-opt"

#: Tham số fooling theo đúng bảng ở `wiki.zapret.moe/Zapret2/desync`.
#:
#: Chia hai nhóm vì chúng **không thay thế được cho nhau**:
#:
#: * L3/IP — dùng được cho cả TCP lẫn UDP.
#: * L4/TCP — `tcp_md5` là *tuỳ chọn TCP*. Đặt vào gói UDP thì không có tác
#:   dụng gì, nên tưởng là đã có fooling trong khi thực ra gói giả sẽ tới đích.
FOOL_IP = {
    "ip_ttl", "ip6_ttl", "ip_autottl", "ip6_autottl",
    "ip6_hopbyhop", "ip6_hopbyhop2", "ip6_destopt", "ip6_destopt2",
    "ip6_routing", "ip6_ah", "badsum", "ipfrag", "fool",
}
FOOL_TCP = {
    "tcp_md5", "tcp_seq", "tcp_ack", "tcp_ts", "tcp_flags_set",
    "tcp_flags_unset", "tcp_ts_up", "tcp_nop_del",
}
FOOL_ALL = FOOL_IP | FOOL_TCP

#: Hàm desync nào **chỉ** dùng được với TCP. Cắt datagram UDP làm nhiều
#: datagram là sai bản chất giao thức — mỗi datagram tự chứa trọn.
SPLIT_FUNCS = {"multisplit", "multidisorder", "fakedsplit", "fakeddisorder"}


# --------------------------------------------------------------------------- #
# Bóc tách
# --------------------------------------------------------------------------- #
def profiles(path: Path = OPT_FILE) -> list[str]:
    """Các dòng profile trong tệp, bỏ dòng trắng và dòng chú thích."""
    assert path.is_file(), f"không có {path}"
    return [ln.strip() for ln in path.read_text(encoding="utf-8").splitlines()
            if ln.strip() and not ln.strip().startswith("#")]


def desync_calls(line: str) -> list[tuple[str, list[str]]]:
    """Rút (tên hàm, tham số) từ mọi `--lua-desync=` trong một profile."""
    return [(lambda parts: (parts[0], parts[1:]))(raw.split(":"))
            for raw in re.findall(r"--lua-desync=([^\s]+)", line)]


def param_names(params: list[str]) -> set[str]:
    """Tên tham số, **kể cả cờ không có giá trị**.

    Bẫy đã dính lần đầu: `tcp_md5` viết trong tài liệu là `tcp_md5[=hex]` —
    phần hex là tuỳ chọn, nên `tcp_md5` bình thường **không có** dấu `=`.
    Lọc bằng `"=" in p` thì rơi mất đúng cái cờ quan trọng nhất, và check báo
    động giả trên chính cấu hình tốt.
    """
    return {p.split("=", 1)[0] for p in params}


def is_udp(line: str) -> bool:
    return "--filter-udp" in line


# --------------------------------------------------------------------------- #
# Lỗi 1 — `fake` không có fooling
# --------------------------------------------------------------------------- #
def check_fake_has_fooling(path: Path) -> list[str]:
    offenders = []
    for line in profiles(path):
        for func, params in desync_calls(line):
            if func != "fake":
                continue
            if not (param_names(params) & FOOL_ALL):
                offenders.append(
                    f"fake không có fooling (tham số: {params}) — sẽ hỏng mọi trang")
    return offenders


def check_udp_fooling_is_ip_only(path: Path) -> list[str]:
    offenders = []
    for line in profiles(path):
        if not is_udp(line):
            continue
        for func, params in desync_calls(line):
            if func != "fake":
                continue
            names = param_names(params)
            if names & FOOL_TCP:
                offenders.append(
                    f"profile UDP dùng fooling của TCP {sorted(names & FOOL_TCP)} — "
                    f"vô tác dụng với UDP")
            elif not (names & FOOL_IP):
                offenders.append("profile UDP có fake mà không có fooling tầng IP")
    return offenders


def check_udp_does_not_split(path: Path) -> list[str]:
    return [f"profile UDP dùng hàm tách {f}"
            for line in profiles(path) if is_udp(line)
            for f, _ in desync_calls(line) if f in SPLIT_FUNCS]


# --------------------------------------------------------------------------- #
# Lỗi 2 — thiếu `--new` làm gộp profile
# --------------------------------------------------------------------------- #
def check_profiles_end_with_new(path: Path) -> list[str]:
    return [ln for ln in profiles(path) if not ln.endswith("--new")]


def check_no_double_new(path: Path) -> list[str]:
    return [ln for ln in profiles(path) if ln.count("--new") > 1]


# --------------------------------------------------------------------------- #
# Cấu hình thật trong repo phải sạch
# --------------------------------------------------------------------------- #
ALL_CHECKS = [
    check_fake_has_fooling,
    check_udp_fooling_is_ip_only,
    check_udp_does_not_split,
    check_profiles_end_with_new,
    check_no_double_new,
]


@pytest.mark.parametrize("check", ALL_CHECKS, ids=lambda c: c.__name__[6:])
def test_repo_config_passes(check):
    bad = check(OPT_FILE)
    assert not bad, "\n".join(bad)


def test_tcp443_has_more_than_a_bare_split():
    """Profile 443 không được trần.

    Tài liệu nói thẳng: *«разрез сам по себе не обманет»* — hệ thống biết ghép
    lại luồng TCP thì cắt đoạn không lừa được, nên `multisplit` phải đi kèm
    gói giả. Cấu hình cũ của repo đúng là `multisplit:pos=1` trần.
    """
    lines = [ln for ln in profiles() if "--filter-tcp=443" in ln]
    assert lines, "không có profile TCP/443"
    for line in lines:
        funcs = {f for f, _ in desync_calls(line)}
        assert "fake" in funcs, (
            f"profile 443 chỉ có {sorted(funcs)}, không có gói giả — "
            f"cắt đoạn trần không lừa được DPI biết ghép luồng")


def test_udp443_profile_present():
    """`config.default` mở `NFQWS2_PORTS_UDP=443`; không có profile UDP thì cổng
    đó được mở ra rồi để không, và HTTP/3 đi thẳng qua."""
    assert any(is_udp(ln) and "--filter-udp=443" in ln for ln in profiles()), \
        "config.default mở NFQWS2_PORTS_UDP=443 nhưng repo không dựng profile udp/443"


# --------------------------------------------------------------------------- #
# Check phải bắt được lỗi thật
# --------------------------------------------------------------------------- #
#: Mỗi mục là một cấu hình xấu đã **đo thật**: `nofool-fake` hỏng 5/5 trang,
#: còn `--new` thì lấy số liệu từ log nfqws2 (4 profile vs 1).
BAD = {
    "fake-khong-fooling":
        "  --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello "
        "--lua-desync=fake:blob=fake_default_tls --new",
    "fooling-TCP-trong-UDP":
        "  --filter-udp=443 --filter-l7=quic --payload=quic_initial "
        "--lua-desync=fake:blob=fake_default_quic:tcp_md5 --new",
    "thieu---new":
        "  --filter-tcp=80 --filter-l7=http --payload=http_req "
        "--lua-desync=multisplit:pos=method+2",
    "cat-datagram-UDP":
        "  --filter-udp=443 --filter-l7=quic --payload=quic_initial "
        "--lua-desync=multisplit:pos=1 --new",
    "hai---new-tren-mot-dong":
        "  --filter-tcp=443 --filter-l7=tls --payload=tls_client_hello "
        "--lua-desync=multisplit:pos=1 --new --new",
}

#: Cấu hình xấu nào phải bị check nào bắt. Ghi rõ để khi một mục "lọt" thì
#: biết ngay là check hỏng hay là ca kiểm thử viết thiếu.
EXPECT_CATCH = {
    "fake-khong-fooling": {check_fake_has_fooling},
    "fooling-TCP-trong-UDP": {check_udp_fooling_is_ip_only},
    "thieu---new": {check_profiles_end_with_new},
    "cat-datagram-UDP": {check_udp_does_not_split},
    "hai---new-tren-mot-dong": {check_no_double_new},
}


def _write(tmp: Path, text: str) -> Path:
    p = tmp / "z2d-zapret2-opt"
    p.write_text(text + "\n", encoding="utf-8")
    return p


@pytest.mark.parametrize("name,bad", list(BAD.items()), ids=list(BAD))
def test_each_bad_config_is_caught(name, bad, tmp_path):
    """**Check phải chứng minh bắt được lỗi.**

    Một check không dính lỗi nào thì chỉ là trang trí. Bài test này tiêm từng
    cấu hình xấu vào một tệp tạm rồi chạy lại đúng bộ check ở trên, đòi phải
    bắt đúng lỗi đã biết.

    Cố tình **không** gọi `pytest` con: chậm, và lỗi con có thể bị nuốt. Gọi
    thẳng hàm kiểm — nếu sau này ai đổi logic, bài test này đỏ, và đó là chuyện
    được muốn.
    """
    p = _write(tmp_path, bad)
    caught = {c.__name__ for c in ALL_CHECKS if c(p)}
    expected = {c.__name__ for c in EXPECT_CATCH[name]}
    assert expected <= caught, (
        f"{name}: mong {sorted(expected)} bắt được, thực tế chỉ {sorted(caught)}")


@pytest.mark.parametrize("name", list(BAD), ids=list(BAD))
def test_real_config_is_never_mistaken_for_a_bad_one(name, tmp_path):
    """Chiều ngược: cấu hình thật phải qua sạch.

    Chống lại loại lỗi tệ nhất của bộ check — báo động giả. Lần đầu viết bài này
    nó **đã bắt** luôn cấu hình tốt, vì `fooling_of` lọc bằng `"=" in p` mà
    `tcp_md5` không có dấu bằng. Cần giữ bài này để lỗi đó không quay lại.
    """
    p = _write(tmp_path, OPT_FILE.read_text(encoding="utf-8").rstrip("\n"))
    for c in ALL_CHECKS:
        assert not c(p), f"{c.__name__} báo động giả trên cấu hình thật"
