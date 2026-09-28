#!/usr/bin/env python3
"""Kiểm sơ đồ khối trong README: các dòng phải thẳng hàng.

QUY TẮC (đúng như mong đợi khi nhìn sơ đồ):
  Mọi dòng trong một khối ``` có ký tự vẽ khung phải SAI ĐỘ RÔNG HIỂN THỊ,
  và các ký tự khung trái phải nằm ở CÙNG CỘT.

Khối không có ký tự vẽ khung (bash, json…) thì bỏ qua.

  python3 test/check-diagram.py            # kiểm README.md
  python3 test/check-diagram.py file.md    # kiểm file khác
"""
import sys
import unicodedata

# Ky tu ve khung canh dung
BOX = set('│┌┐└┘├┤┬┴┼─╭╮╰╯━┃')
LEFT = '┌├╭'
RIGHT = '┐┤╮'


def cw(ch):
    """Do rong hien thi cua MOT ky tu. Dau tieng Viet la ky tu tong hop: 0 cot."""
    if unicodedata.combining(ch):
        return 0
    if unicodedata.east_asian_width(ch) in ('W', 'F'):
        return 2
    return 1


def W(s):
    return sum(cw(c) for c in s)


def C(s, j):
    return sum(cw(c) for c in s[:j])


def blocks(text):
    """[(so dong, cac dong)] cho tung khoi lan giua ``` ... ```."""
    out, cur, n, inside = [], [], 1, False
    for line in text.split('\n'):
        if line.startswith('```'):
            if inside:
                out.append((n, cur))
            cur, inside = [], not inside
            n += 1
            continue
        if inside:
            cur.append(line)
        n += 1
    return out


def check(name, box):
    if not any(any(c in BOX for c in l) for l in box):
        return None                     # khoi thuong (bash, json) — bo qua
    print(f'=== {name} · {len(box)} dong ===')
    bad = 0
    widths = {}
    for l in box:
        widths.setdefault(W(l), []).append(l)
    if len(widths) > 1:
        print(f'  ✘ SO DO CO {len(widths)} DO RONG khac nhau: {sorted(widths)}')
        for w, ls in sorted(widths.items()):
            if len(ls) <= 3:
                for l in ls:
                    print(f'      rong {w}: {l!r}')
        bad += len(widths) - 1
    lc, rc = set(), set()
    for l in box:
        for j, c in enumerate(l):
            if c in LEFT:
                lc.add(C(l, j))
            elif c in RIGHT:
                rc.add(C(l, j))
    # '│' don le (duong noi giua cac khung) nam o giua khung, bo qua kiem canh
    if len(lc) > 1:
        print(f'  ✘ canh trái lệch: {sorted(lc)}')
        bad += 1
    if len(rc) > 1:
        print(f'  ✘ canh phải lệch: {sorted(rc)}')
        bad += 1
    if bad == 0:
        print(f'  ✔ thẳng hàng — mọi dòng rộng {W(box[0])}, '
              f'khung trái cột {min(lc) if lc else "-"}, phải cột {max(rc) if rc else "-"}')
    return bad


def main(*paths):
    files = paths or ('README.md',)
    total = 0
    for path in files:
        text = open(path, encoding='utf-8').read()
        for n, box in blocks(text):
            r = check(f'{path}: khối dòng {n}', box)
            if r is None:
                continue
            total += r
            print()
    print('KẾT QUẢ:', 'sơ đồ thẳng hàng' if total == 0 else f'{total} chỗ cần sửa')
    return 0 if total == 0 else 1


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:]))
