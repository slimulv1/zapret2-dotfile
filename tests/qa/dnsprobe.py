"""Dò resolver — phục vụ INV-DNS-1 và INV-LAYER-2.

Phân biệt 4 trạng thái, không gộp làm một:
    OK          — có câu trả lời DNS
    NXDOMAIN    — có câu trả lời nhưng tên bị chặn (đây là CHẶN ĐÚNG)
    CHẶN        — đã hỏi, không có câu trả lời (timeout/refused)
    KHÔNG ĐO ĐƯỢC — công cụ không đo được trường hợp này (xem bẫy bên dưới)
"""

from __future__ import annotations

import re

from .host import Result, run

#: Bẫy đã dính: `dig @[2a07:a8c0::]` in
#:   `couldn't get address for '[2a07:a8c0::]': failure`
#: — đó là `getaddrinfo` của dig không phân tích được literal dạng `::`,
#: KHÔNG phải mạng hỏng. Đừng kết luận "IPv6 chết" từ dòng đó.
LITERALS_DIG_CANNOT_PARSE = ("2a07:a8c0::", "2a07:a8c1::")

_STATUS = re.compile(r"status:\s+([A-Z]+)")
_NOSERVER = re.compile(r"no servers could be reached")
_TOOLFAIL = re.compile(r"couldn't get address|invalid option|bad address")
_TIMEOUT = re.compile(r"timed out|connection timed out")


def _classify(res: Result) -> str:
    out = res.out + res.err
    if _TOOLFAIL.search(out):
        return "KHÔNG ĐO ĐƯỢC"
    if _STATUS.search(out):
        st = _STATUS.search(out).group(1)
        return st if st in ("NOERROR", "NXDOMAIN") else st
    if _NOSERVER.search(out) or _TIMEOUT.search(out) or res.timed_out:
        return "CHẶN"
    return "KHÔNG ĐO ĐƯỢC"


def resolve(server: str, name: str = "github.com", rtype: str = "A", *,
            port: int = 53, tcp: bool = False, tls: bool = False,
            timeout: int = 20) -> str:
    """Hỏi một resolver. Trả về trạng thái, không trả về "có/không" gộp.

    Bẫy đã dính: `dig -p 853` mà không có `+tls` sẽ gửi DNS **rõ** qua cổng
    DoT; NextDNS im lặng ⇒ tưởng đường DoT chết. Phải có `+tls`.
    """
    if server in LITERALS_DIG_CANNOT_PARSE:
        return "KHÔNG ĐO ĐƯỢC"
    # BẪY ĐÃ DÍNH (lần 2): `dig @[2620:fe::fe]` in
    #   `couldn't get address for '[2620:fe::fe]': failure`
    # — dig KHÔNG chấp nhận ngoặc vuông trong `@`. Bỏ ngoặc thì phân tích đúng
    # và mới báo `communications error … timed out`. Không bỏ ngoặc thì mọi
    # resolver v6 đều thành "KHÔNG ĐO ĐƯỢC" và test hỏng với lý do sai.
    server = server.strip("[]")
    cmd = ["dig", "+time=5", "+tries=1"]
    if tcp:
        cmd.append("+tcp")
    if tls:
        cmd.append("+tls")
    if port != 53:
        cmd += ["-p", str(port)]
    cmd += [f"@{server}", name, rtype]
    return _classify(run(cmd, timeout=timeout))


def system_resolves(name: str = "github.com", timeout: int = 20) -> str:
    """Hỏi qua `resolved` — đường đi thật của máy, không ép cổng.

    Dùng `--cache=no` vì `dig` đọc cache của `resolved`: khi NextDNS bị chặn,
    `dig` vẫn trả kết quả nhờ cache và ta tưởng "DNS còn sống".
    """
    res = run(["resolvectl", "query", "--cache=no", name], timeout=timeout)
    if res.ok and re.search(r"([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}|\d+\.\d+\.\d+\.\d+", res.out):
        return "OK"
    return "CHẶN" if (res.timed_out or res.rc != 0) else "KHÔNG ĐO ĐƯỢC"


def resolved_peers(family: str = "v6") -> list[str]:
    """Peer nào `systemd-resolve` đang thật sự kết nối tới.

    Đây là bằng chứng thay cho `dig`: nó cho thấy kết nối TCP **thật** tới đúng
    địa chỉ, không suy đoán từ cấu hình.
    """
    pat = "2a07:a8c[01]" if family == "v6" else r"45\.90\.(28|30)\.0"
    res = run(["sh", "-c", f"ss -tnp 2>/dev/null | grep -E '{pat}' | grep -c ESTAB"],
              sudo=True, timeout=30)
    m = res.out.strip()
    return [m] if m.isdigit() and int(m) > 0 else []


#: Rule DENY trong nft. KHÔNG khớp theo chữ "# z2d chan DNS" — ufw KHÔNG đưa
#: comment vào ruleset (comment nằm trong /etc/ufw/user.rules). Đã đo: `grep z2d
#: nft list ruleset` ra 0 dòng. Phải khớp theo HÌNH DẠNG rule:
#:     udp dport 53 counter packets 9 bytes 711 drop
#: và loại các rule `accept` (daddr 45.90.x — đó là đường hợp lệ).
_DENY_DNS = re.compile(
    r"\b(?:udp|tcp) dport (?:53|853) counter packets (\d+)\b[^\n]*\bdrop\b")


def deny_counter() -> int:
    """Tổng số gói đã rơi vào rule DENY 53/853 của tường (cả hai họ).

    Vì sao cần: "hỏi mà không có câu trả lời" **không** chứng minh là tường
    chặn — cũng có thể chỉ là mạng không tới nơi. Đếm gói rơi vào rule DROP
    mới là bằng chứng rằng chính bức tường đã chặn.
    """
    res = run(["nft", "list", "ruleset"], sudo=True, timeout=30)
    return sum(int(m.group(1)) for m in _DENY_DNS.finditer(res.out))
