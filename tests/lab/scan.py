#!/usr/bin/env python3
"""Quét cổng bằng kết nối TCP thật, chạy trong network namespace.

Vì sao tự viết thay vì dùng `nmap`: máy này không cài nmap, và đặt nạn phần mềm
mới vào hệ thống đang kiểm để rồi không dám xoá là chuyện lệ chuẩn. Quét kiểu
`connect()` vẫn là phép thử thật: SYN đi qua đúng chuỗi prerouting → INPUT như
mọi gói đến từ mạng, và nếu tường chặn thì kết nối sẽ treo (filtered).

Phân biệt hai trạng thái, không gộp:
    open      — kết nối TCP thành công
    closed    — bị RST: có dịch vụ nhưng không phải bị tường chặn
    filtered  — treo tới hết giờ: bị tường chặn (hoặc không ai lắng nghe
                sau một DROP im lặng)
Vì `accept_redirects`… không, vì DROP thì không RST, nên `filtered` ở đây là
dấu hiệu của tường. Đối chiếu với `ss -tlnp` trên máy đích để biết dịch vụ
CÓ hay KHÔNG — nếu không đối chiếu thì "closed" và "không có dịch vụ" trùng nhau.
"""
from __future__ import annotations

import argparse
import errno
import socket
import sys
from concurrent.futures import ThreadPoolExecutor


#: Mã lỗi báo "KHÔNG có gói trả lời" — dấu của tường chặn (DROP).
#: ECONNREFUSED là RST ⇒ có dịch vụ, chỉ là không phải tường.
NO_REPLY = {errno.ETIMEDOUT, errno.EHOSTUNREACH, errno.ENETUNREACH,
            errno.EHOSTDOWN, errno.ENETDOWN, errno.EAGAIN}


def probe(host: str, port: int, timeout: float) -> str:
    """open / closed / filtered.

    BẪY ĐÃ DÍNH: bản đầu dùng `getsockopt(SO_ERROR)` để lấy lỗi — nhưng
    SO_ERROR **xoá** lỗi sau khi đọc và trả về 0, nên mọi ca đều bị gán
    "closed". Đo được: 13/13 cổng trả `closed` trong khi thực tế tường đang
    DROP (đối chiếu: counter `ufw-user-input` = 0, tức không rule nào khớp, và
    `ufw-skip-to-policy-input` drop). Phải đọc errno trả về trực tiếp từ
    `connect_ex`.
    """
    s = socket.socket()
    s.settimeout(timeout)
    try:
        rc = s.connect_ex((host, port))
        if rc == 0:
            return "open"
        return "filtered" if rc in NO_REPLY else "closed"
    except socket.timeout:
        return "filtered"
    except OSError as e:
        return "filtered" if e.errno in NO_REPLY else "closed"
    finally:
        s.close()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--ports", default="22,53,80,443,3306,5432,8080,5353,1714,1715,1716,1763,1764")
    ap.add_argument("--timeout", type=float, default=2.0)
    a = ap.parse_args()
    ports = [int(x) for x in a.ports.split(",") if x.strip()]
    with ThreadPoolExecutor(max_workers=32) as ex:
        res = list(ex.map(lambda p: (p, probe(a.host, p, a.timeout)), ports))
    order = {p: i for i, p in enumerate(ports)}
    res.sort(key=lambda x: order[x[0]])
    for p, st in res:
        print(f"{p}\t{st}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
