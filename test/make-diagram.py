#!/usr/bin/env python3
"""Sinh sơ đồ 3 tầng cho README.

Không gõ tay. Do rong tiếng Việt không đều — ký tự có dấu là ký tự tổ hợp,
dấu chiếm 0 cột hiển thị — nên gõ tay chắc chắn lệch. Script này tính độ rộng
hiển thị rồi đệm chữ, nên kết quả luôn thẳng hàng.

Mô hình: MỘT khung ngoài đại diện cho máy. Bên trong chia 3 cột:
    số | tên tầng | mô tả
Mọi dòng cùng độ rộng, khung trái và phải ở cùng cột.

  python3 test/make-diagram.py      # in ra kiểm, không ghi file
"""
import sys
import unicodedata


def cw(ch):
    """Độ rộng hiển thị của một ký tự."""
    if unicodedata.combining(ch):          # dấu tiếng Việt: 0 cột
        return 0
    return 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1


def W(s):
    return sum(cw(c) for c in s)


def put(s, n):
    """Đệm hoặc CẮT để độ rộng hiển thị đúng bằng n."""
    d = n - W(s)
    if d >= 0:
        return s + ' ' * d
    out = ''
    for ch in s:
        if W(out) + cw(ch) > n:
            break
        out += ch
    return out + ' ' * (n - W(out))


INNER = 84
TITLE = ' MÁY CỦA BẠN '
C_NUM = 5      # 2 thụt lề + số + 2 khoang trắng
C_NAME = 25
GAP = 2      # khoang cach giua ten tang va mo ta

out = []
pad = INNER - W(TITLE)
out.append('┌' + '─' * (pad // 2) + TITLE + '─' * (pad - pad // 2) + '┐')


def blank():
    out.append('│' + ' ' * INNER + '│')


def section(text):
    if out:
        blank()                       # tach phan cho de doc
    out.append('│' + put('  ' + text.upper(), INNER) + '│')
    blank()


CD = INNER - C_NUM - C_NAME - GAP      # do rong cot mo ta


def layer(num, name, desc):
    out.append('│' + put('  ' + num, C_NUM) + put(name, C_NAME)
               + ' ' * GAP + put(desc[0], CD) + '│')
    for d in desc[1:]:
        out.append('│' + ' ' * (C_NUM + C_NAME) + ' ' * GAP + put(d, CD) + '│')


def note(text):
    blank()
    out.append('│' + put('  ' + text, INNER) + '│')


section('Khi bạn mở một trang web')
layer('1', 'TẦNG 2 · NextDNS · DoT', [
    'Hỏi tên miền ở cổng 853. Trả IP thật,',
    'hoặc chặn tuỳ danh sách trên đám mây.',
    '',
    '◀ CHỖ DUY NHẤT QUYẾT ĐỊNH CHẶN',
    'Nằm trên đám mây, không nằm trong máy.',
])
layer('2', 'TẦNG 1 · zapret2 · desync', [
    'Mở kết nối tới IP đó. Cắt gói đầu của',
    'kết nối HTTPS thành hai đoạn, đoạn đầu',
    'chỉ mang 1 byte. Bộ lọc của nhà mạng cần',
    'nguyên gói để đọc tên miền nên không',
    'khớp mẫu nào và cho qua.',
    '',
    'Không chặn gì cả — chỉ chống bị chặn.',
])
note('Bị chặn ở bước 1 ⇒ không có kết nối nào để mà sửa ở bước 2.')

section('Khi có ai gọi tới máy bạn')
layer('3', 'TẦNG 3 · ufw · chặn INPUT', [
    'Chặn mọi thứ đi vào máy, trừ KDE Connect',
    'trong mạng LAN.',
])

section('Luôn luôn bật, mọi lúc mở máy')
layer('4', 'TẦNG 2b · ufw · tường DNS', [
    'Chỉ cho hỏi NextDNS ở cổng 53 và 853,',
    'chặn mọi nơi hỏi DNS khác — cả IPv4 lẫn IPv6.',
])

out.append('└' + '─' * INNER + '┘')

diagram = '\n'.join(out)
print(diagram)
print()

widths = {W(l) for l in out}
print('── tự kiểm ──')
print(f'  số dòng        : {len(out)}')
print(f'  các độ rộng    : {sorted(widths)}')
if len(widths) != 1:
    print('  ✘ LỆCH')
    for w in sorted(widths):
        print(f'      rộng {w}:')
        for l in out:
            if W(l) == w:
                print(f'        {l!r}')
    sys.exit(1)
col = lambda l, ch: sum(cw(c) for c in l[:l.index(ch) + 1]) - 1
lc = {col(l, '┌') for l in out if '┌' in l} | {col(l, '│') for l in out if '│' in l}
# canh PHAI phai la '|' CUOI CUNG, khong phai '|' dau tien — '|' dau tien la
# khung trai o cot 0. Ban dau lay nham nen bao "phai [0, 85]".
rc = {col(l, '┐') for l in out if '┐' in l}
rc |= {sum(cw(c) for c in l) - 1 for l in out if l.startswith('│')}
w = widths.pop()
if len(lc) > 1 or len(rc) > 1:
    print(f'  ✘ khung lệch: trái {sorted(lc)}, phải {sorted(rc)}')
    sys.exit(1)
print(f'  ✔ thẳng hàng   : mọi dòng rộng {w}, khung trái cột {min(lc)}, phải cột {max(rc)}')
