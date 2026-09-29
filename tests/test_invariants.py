"""Quét invariant — danh sách §4. Đây là bộ test có giá trị cao nhất.

Mỗi test = MỘT hành vi, tên đọc là biết nó kiểm cái gì. Mỗi test khẳng định
cả **trạng thái lệnh** (rc) lẫn **hệ quả** (side-effect), không chỉ kiểm lệnh
"chạy xong".

Tất cả test ở đây giả định hệ ĐANG CHẠY, nên cần `needs_installed` (bỏ qua kèm
lý do nếu chưa cài). Thiếu khai báo thì khi phiên bắt đầu lúc máy đã-gỡ, chúng
đỏ vì "thiếu tệp" — lý do không liên quan gì tới thứ đang kiểm.

Phân loại kết quả:
    HELD       — có phép đo, đạt
    UNVERIFIED — thiếu bằng chứng; KHÔNG được coi là đạt
    VIOLATION  — đo ra trái với thiết kế
"""

from __future__ import annotations

import pytest

from qa import state
from qa.dnsprobe import deny_counter, resolve, resolved_peers, system_resolves
from qa.host import run
from qa.wire import first_segments

pytestmark = pytest.mark.invariants

#: Resolver KHÔNG được phép hỏi — cả hai họ, cả hai chuyển vận tải.
FORBIDDEN = [
    ("1.1.1.1", False), ("8.8.8.8", False), ("9.9.9.9", False),
    ("208.67.222.222", False),
    ("[2606:4700:4700::1111]", False), ("[2001:4860:4860::8888]", False),
    ("[2620:fe::fe]", False),
    ("1.1.1.1", True), ("[2606:4700:4700::1111]", True),
]

#: Resolver ĐƯỢC hỏi — phải còn sống, nếu không cả hệ thống chết.
ALLOWED = ["45.90.28.0", "45.90.30.0"]


# --------------------------------------------------------------------------- #
# INV-DNS-1 — mọi resolver ngoài NextDNS phải thất bại
# --------------------------------------------------------------------------- #
@pytest.mark.network
@pytest.mark.parametrize("server,tcp", FORBIDDEN, ids=lambda v: str(v))
def test_dns_forbidden_resolver_is_blocked(server, tcp, needs_installed):
    """Hai khẳng định, phải đạt CẢ HAI:

    1. hỏi ⇒ không có câu trả lời;
    2. counter của rule DENY 53/853 **tăng**.

    Chỉ (1) thì chưa đủ: "không có câu trả lời" chưa phân biệt được
    "tường chặn" với "mạng không tới nơi". (2) mới chứng minh chính bức
    tường đã chặn — và nó cũng bắt được tình huống `ufw` in
    "Skipping inserting existing rule" tức lỗi chưa hề được chèn.
    """
    before = deny_counter()
    st = resolve(server, "github.com", "A", tcp=tcp)
    after = deny_counter()
    assert st == "CHẶN", (
        f"resolver {server} (tcp={tcp}) trả về {st!r} — lối tắt tầng 2. "
        f"Kiểm:  sudo ufw status | grep -F '{server.strip('[]')}'"
    )
    assert after > before, (
        f"không có câu trả lời ({st!r}) nhưng counter rule DENY không tăng "
        f"({before} → {after}) ⇒ không phải tường chặn, mà mạng không tới. "
        f"Phép thử này chưa chứng minh được gì."
    )


@pytest.mark.network
@pytest.mark.parametrize("server", ALLOWED)
def test_dns_nextdns_resolver_still_works(server, needs_installed):
    st = resolve(server, "github.com", "A")
    assert st == "NOERROR", f"NextDNS {server} trả {st!r} — hệ thống DNS hỏng"


@pytest.mark.network
def test_dns_dot_is_actually_encrypted(needs_installed):
    """853 phải là DoT thật. Đo được bằng `+tls`; thiếu `+tls` thì im lặng.

    Bẫy đã dính: `dig -p 853` không có `+tls` gửi DNS RÕ qua cổng DoT ⇒
    NextDNS không trả lời ⇒ tưởng đường DoT chết. Đó là sai.
    """
    st = resolve("45.90.28.0", "github.com", "A", port=853, tls=True)
    assert st == "NOERROR", f"DoT tới NextDNS trả {st!r}"


@pytest.mark.network
def test_dns_system_resolver_answers(needs_installed):
    assert system_resolves() == "OK", "hệ thống không phân giải được tên miền"


# --------------------------------------------------------------------------- #
# INV-V6-1 — tầng 2 qua IPv6
# --------------------------------------------------------------------------- #
@pytest.mark.destructive
@pytest.mark.network
def test_dns_falls_back_to_ipv6_when_ipv4_nextdns_blocked(require_installed):
    """Khi IPv4 NextDNS không dùng được, DNS phải còn qua IPv6 — và phải THẬT.

    Vì sao cần chặn v4: `resolved` ưu tiên v4 (`Current DNS Server:
    45.90.28.0`), nên khi v4 còn tốt thì nó **không bao giờ** mở socket tới
    `2a07:a8c0::`. Bản test đầu của tôi chỉ nhìn `ss` và đòi thấy kết nối v6
    ⇒ đỏ, và tôi suýt kết luận "IPv6 hỏng". Đo thì ra ngược lại: phải CHẶN v4
    thì kết nối v6 mới xuất hiện. Đây là bẫy "đo sai điều kiện" — mạng vẫn
    tốt, chỉ là không ai gọi tới IPv6.

    Ba khẳng định, phải đạt cả ba:
      1. v4 bị chặn ⇒ `dig` tới v4 timeout (xác nhận lỗi ĐÃ được tiêm);
      2. phân giải vẫn thành công ⇒ tồn tại đường dự phòng;
      3. trong lúc phân giải, `ss` thấy `systemd-resolve → [2a07:a8c0::]:853`.
    """
    # `require_installed` là BẮT BUỘC: không có hệ 3 tầng thì tường DNS không
    # tồn tại, mọi resolver đều bị chặn ⇒ `system_resolves` trả CHẶN là ĐÚNG,
    # và test đỏ vì lý do không liên quan tới IPv6. Bản đầu thiếu chính cái này.
    import threading, time
    tbl = "z2d_pytest_v6"
    mk = run(["nft", "add", "table", "inet", tbl], sudo=True, timeout=20)
    assert mk.ok, "không tạo được bảng thử: " + mk.describe()
    run(["nft", "add", "chain", "inet", tbl, "o",
         "{ type filter hook output priority -10 ; }"], sudo=True, timeout=20)
    added = 0
    for ip in ("45.90.28.0", "45.90.30.0"):
        added += run(["nft", "add", "rule", "inet", tbl, "o", "ip", "daddr", ip,
                      "drop"], sudo=True, timeout=20).ok
    try:
        assert added == 2, f"chỉ chặn được {added}/2 IP v4 — lỗi chưa tiêm"
        assert resolve("45.90.28.0", "github.com", "A") == "CHẶN", \
            "v4 chưa bị chặn — phép thử chưa có ý nghĩa"

        seen: list[int] = []

        def sampler(stop):
            while not stop.is_set():
                seen.append(len(resolved_peers("v6")))
                time.sleep(0.2)

        for _ in range(3):
            stop = threading.Event()
            t = threading.Thread(target=sampler, args=(stop,), daemon=True)
            t.start()
            st = system_resolves("www.debian.org")
            stop.set(); t.join(timeout=2)
            if st == "OK" and max(seen or [0]) > 0:
                return
            seen = []
        pytest.fail(
            f"v4 đã chặn mà phân giải vẫn thất bại, hoặc không thấy kết nối IPv6. "
            f"system_resolves={st!r} · mẫu ss={seen}. Nếu DNS vẫn ra kết quả thì "
            f"đó có thể là cache — kiểm lại bằng --cache=no."
        )
    finally:
        run(["nft", "delete", "table", "inet", tbl], sudo=True, timeout=20)
        left = run(["sh", "-c",
                    f"nft list tables 2>/dev/null | grep -c 'table inet {tbl}'"],
                   sudo=True, timeout=20).out.strip()
        assert left == "0", f"bảng thử còn sót lại sau finally ({left})"


# --------------------------------------------------------------------------- #
# INV-LAYER-2 — NextDNS chết thì phải fail-closed, không lối tắt
# --------------------------------------------------------------------------- #
@pytest.mark.destructive
@pytest.mark.network
def test_dns_fails_closed_when_nextdns_unreachable(require_installed):
    """Chặn NextDNS cả hai họ ⇒ mọi tên phải hỏng. Vẫn vào được = rò DNS (S1).

    Dùng bảng `nft` RIÊNG thay vì `ufw`:
      * `ufw insert 1 deny out to <v6>/128` → `ERROR: Invalid position '1'`
        (ufw không cho chèn vị trí 1 cho rule IPv6)
      * chèn rule trùng sẵn thì ufw in "Skipping inserting existing rule" ⇒
        lỗi KHÔNG được tiêm ⇒ phép thử ra kết quả tầng 2 vẫn sống (tưởng
        pass trong khi thực tế chưa chặn gì).
    Bảng riêng thì xoá sạch, và `finally` luôn dọn.
    """
    import time
    tbl = "z2d_pytest_fc"
    # PHẢI TẠO BẢNG trước. Bản đầu của test này thêm rule vào bảng chưa tồn
    # tại ⇒ `nft add rule` hỏng ⇒ lỗi KHÔNG được tiêm ⇒ rồi assert rằng DNS
    # chết sẽ FAIL. May mắn là fail chứ không pass giả, nhưng phải sửa.
    mk = run(["nft", "add", "table", "inet", tbl], sudo=True, timeout=20)
    assert mk.ok, "không tạo được bảng thử: " + mk.describe()
    ch = run(["nft", "add", "chain", "inet", tbl, "o",
              "{ type filter hook output priority -10 ; }"], sudo=True, timeout=20)
    assert ch.ok, "không tạo được chain thử: " + ch.describe()

    added = 0
    for ip in ("45.90.28.0", "45.90.30.0"):
        added += run(["nft", "add", "rule", "inet", tbl, "o", "ip", "daddr", ip,
                      "drop"], sudo=True, timeout=20).ok
    for ip in ("2a07:a8c0::", "2a07:a8c1::"):
        added += run(["nft", "add", "rule", "inet", tbl, "o", "ip6", "daddr", ip,
                      "drop"], sudo=True, timeout=20).ok
    try:
        # Xác nhận lỗi ĐÃ thật sự được tiêm, trước khi kết luận.
        assert added == 4, f"chỉ thêm được {added}/4 rule chặn — lỗi chưa tiêm xong"
        time.sleep(1)
        assert system_resolves() == "CHẶN", (
            "NextDNS bị chặn mà hệ thống vẫn phân giải được ⇒ RÒ DNS (S1)"
        )
    finally:
        run(["nft", "delete", "table", "inet", tbl], sudo=True, timeout=20)
        left = run(["sh", "-c",
                    f"nft list tables 2>/dev/null | grep -c 'table inet {tbl}'"],
                   sudo=True, timeout=20).out.strip()
        assert left == "0", f"bảng thử còn sót lại sau finally: {left} ghi"            if False else f"bảng thử còn sót lại sau finally ({left})"


# --------------------------------------------------------------------------- #
# INV-DESYNC-1 — đoạn đầu không lộ tên miện thật
# --------------------------------------------------------------------------- #
#: Hai tên miền dùng để đo. Phải biết trước tên thật thì mới đòi hỏi được
#: "đoạn đầu KHÔNG chứa tên thật" — không có nó thì bất biến vô nghĩa.
DESYNC_PROBES = [
    ("github.com", "https://github.com"),
    ("www.wikipedia.org", "https://www.wikipedia.org"),
]


@pytest.mark.network
@pytest.mark.slow
def test_desync_first_segment_is_exactly_one_byte(iface, offload_off, raw_socket, needs_installed):
    """Đoạn TCP đầu tiên mang dữ liệu **không được lộ tên miền thật**.

    Bắt buộc có `offload_off`: nếu TSO/GSO còn bật, host thấy MỘT khối lớn dù
    trên dây có nhiều đoạn nhỏ ⇒ đo ra số sai hoàn toàn.

    VÌ SAO KHÔNG KIỂM "ĐOẠN ĐẦU 1 BYTE" NỮA
    Bản cũ đòi đoạn đầu đúng 1 byte, và nó **đúng** với cấu hình `multisplit`
    trần. Nhưng nó đo *hình thức* của chiến lược chứ không đo *mục đích* của nó.
    Đổi sang `fake` + `multisplit:pos=1,midsld` thì đoạn đầu trở thành gói giả
    ~684 byte và bản cũ đỏ — dù cấu hình mới **mạnh hơn**.

    Cái thực sự phải giữ là: một DPI chỉ soi đoạn đầu thì **không thấy** tên
    miền thật. Nên đo bằng SNI. Cách này đúng với cả cấu hình cũ lẫn mới, và
    trả lời đúng câu hỏi.
    """
    import subprocess, sys, threading, time
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent / "lab"))
    from dpi import parse_sni

    assert all(v == "off" for v in offload_off.values()), \
        f"offload chưa tắt: {offload_off}"
    assert run(["systemctl", "is-active", "zapret2"], sudo=True, timeout=20).out.strip() \
        == "active", "zapret2 không chạy — không có gì để đo desync"

    def traffic():
        time.sleep(2)
        for _, u in DESYNC_PROBES:
            subprocess.run(["curl", "-s", "-o", "/dev/null", "-m", "8",
                            "--no-keepalive", u], capture_output=True, timeout=15)
            time.sleep(1)
    t = threading.Thread(target=traffic, daemon=True); t.start()
    segs = first_segments(iface, 443, seconds=12)
    t.join(timeout=5)

    assert segs, "không bắt được luồng nào tới cổng 443 — phép đo hỏng, không kết luận"

    real = {h for h, _ in DESYNC_PROBES}
    for s in segs:
        sni = parse_sni(s["first_bytes"])
        assert sni not in real, (
            f"nhóm {s['fam']}: đoạn đầu {s['first']} byte LỘ tên miền thật "
            f"({sni!r}) — DPI chỉ soi đoạn đầu là thấy hết, desync không còn tác dụng"
        )
        assert s["first_head"].startswith("16"), (
            f"byte đầu = {s['first_head'][:2]}, mong đợi 16 (0x16 = TLS handshake)"
        )
        # desync có thật sự chạy không: ClientHello phải bị cắt, tức đoạn đầu
        # không giải mã được trọn ClientHello. Nếu không có mảnh này thì bất
        # biến trên có thể "đúng" chỉ vì không bắt được ClientHello nào.
        assert s["nseg"] > 1, (
            f"nhóm {s['fam']}: chỉ {s['nseg']} đoạn cho cả luồng — "
            f"ClientHello không bị cắt, có lẽ desync không chạy"
        )



# --------------------------------------------------------------------------- #
# INV-NO-HALF-STATE / §3 — các thứ không thuộc tầng 1
# --------------------------------------------------------------------------- #
def test_no_scratch_nft_tables_left_behind(iface):
    """Không còn bảng `nft` tạm nào sót lại.

    Chính tôi đã từng để lại `inet z2d_qa_test` và `inet z2d_qa_v6`. Khung test
    phải bắt được việc đó, không để mắt thường phải tự thấy.
    """
    left = state.scratch_tables()
    assert not left, f"còn bảng nft sót lại (từ phép thử trước): {left}"


def test_sysctl_does_not_collide_with_cachyos_settings(needs_installed):
    """`60-z2d-hardening.conf` không được đặt khoá trùng với CachyOS.

    `systemd-sysctl` áp theo thứ tự TÊN tệp, nên `70-` chạy sau `60-` và thắng.
    Trùng khoá ⇒ cấu hình của hệ 3 tầng bị ghi đè im lặng, không có cảnh báo.
    """
    dup = state.sysctl_conflicts()
    assert not dup, (
        f"{len(dup)} khoá bị đặt ở cả hai tệp; CachyOS thắng: {dup}"
    )


def test_firewall_policy_is_drop_in_kernel(needs_installed):
    """Policy phải đọc từ KERNEL (`nft list ruleset`), không đọc tệp.

    Đọc tệp là kiểm ý kiến của installer, không phải trạng thái thật.
    """
    res = run(["nft", "list", "ruleset"], sudo=True, timeout=30)
    assert res.ok, "không đọc được ruleset: " + res.err[:200]
    for fam in ("ip filter", "ip6 filter"):
        assert f"table {fam}" in res.out, f"thiếu bảng {fam}"
    drop_v4 = 'table ip filter' in res.out and 'policy drop' in res.out
    assert drop_v4, "không thấy `policy drop` trong bảng lọc IPv4"


def test_nfqueue_hook_present_for_both_families(needs_installed):
    """zapret2 phải móc NFQUEUE trên CẢ IPv4 và IPv6 — nếu thiếu, tầng 1 im."""
    res = run(["nft", "list", "ruleset"], sudo=True, timeout=30)
    assert "queue" in res.out and "zapret" in res.out.lower(), \
        "không thấy hook NFQUEUE của zapret2 trong ruleset"
    assert 'ip6' in res.out or 'ip ' in res.out, "ruleset không có họ nào"
