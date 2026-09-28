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
    # KHONG them dong trong o cuoi: layer() da them dong trong o dau moi tang.
    # Them ca hai noi thì ra hai dong trong lien nhau.
    out.append('│' + put('  ' + text.upper(), INNER) + '│')


# [vong 36] XEP TEN LEN DONG RIENG, MO TA THUT XUONG DUOI.
#
#   Ban dau bo 3 COT NGANG: so | ten tang | mo ta. Hai cot "ten tang" va
#   "mo ta" nam canh nhau, nen bat ky chu nao cung co the bi quy nham la cua
#   tang ben canh. Vi du ro nhat: dong
#       "  ◀ CHỗ DUY NHẤT QUYẾT ĐỊNH CHẶN"
#   la tiep noi cua TANG 2 (NextDNS) nhung nam ngay sat dong
#       "  2  TẦNG 1 · zapret2 · desync"
#   o ngay duoi, nen doc nham sang tang 1 la hoan toan hop ly.
#
#   Cach chua: moi tang chi con MOT cot — ten tren dong, mo ta thut ben duoi,
#   thut dung duoi chieu rong cua phan ten. Khong con hai cot nao nam canh
#   nhau, nen khong con gi de nham nua.
IND_BODY = '      '                  # thụt đầu dòng mô tả
CD = INNER - W(IND_BODY)              # bề rộng cột mô tả


def layer(num, name, desc):
    # DONG TRONG TRUỚC MỖI TẦNG — không có nó thì dòng cuối của tầng này
    # dính ngay dòng tiêu đề của tầng sau, đọc lại thành một khối.
    blank()
    out.append('│' + put('  ' + num + '  ' + name, INNER) + '│')
    for d in desc:
        out.append('│' + put(IND_BODY + d, INNER) + '│')


section('Khi bạn mở một trang web')
layer('①', 'TẦNG 2 · NextDNS qua DoT', [
    'Hỏi tên miền ở cổng 853. NextDNS trả về IP thật, hoặc chặn tuỳ',
    'danh sách nằm trên đám mây của bạn.',
    '',
    '◀ ĐÂY LÀ CHỖ DUY NHẤT QUYẾT ĐỊNH CHẶN.',
    'Danh sách chặn nằm trên đám mây chứ không nằm trong máy,',
    'nên phần cài đặt bên dưới không tự làm được bước này.',
])
layer('②', 'TẦNG 1 · zapret2 · desync', [
    'Mở kết nối tới IP vừa nhận được. Cắt gói đầu của kết nối',
    'HTTPS thành hai đoạn, đoạn đầu chỉ mang 1 byte. Bộ lọc của',
    'nhà mạng cần nguyên gói đó để đọc tên miền, nên không khớp',
    'mẫu nào và cho qua.',
    '',
    'Tầng này không chặn gì cả — nó chỉ chống bị chặn. Nếu tên',
    'miền bị chặn ở bước ① thì không có kết nối nào để mà sửa',
    'ở bước ②.',
])

section('Khi có ai gọi tới máy bạn')
layer('③', 'TẦNG 3 · ufw · chặn INPUT', [
    'Chặn mọi thứ đi vào máy, trừ KDE Connect trong mạng LAN.',
])

section('Luôn luôn bật, mọi lúc mở máy')
layer('④', 'TẦNG 2b · ufw · tường chặn DNS', [
    'Chỉ cho phép hỏi NextDNS ở cổng 53 và 853, chặn mọi nơi hỏi',
    'DNS khác — cả IPv4 lẫn IPv6.',
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
