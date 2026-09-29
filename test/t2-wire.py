#!/usr/bin/env python3
"""Đo kích thước đoạn TCP đầu tiên mang ClientHello, ngay trên DÂY.

Vì sao không dùng tcpdump: tcpdump cũng chỉ thấy skb TRƯỚC TSO, nên cũng đo
sai. Cách này tự phân tích header, không cần cài gói nào.

Cách dùng
---------
    # 1. BẮT BUỘC tắt offload, nếu không số đo sai hoàn toàn
    sudo ethtool -K enp8s0 tso off gso off gro off

    # 2. Đo — nhánh A: zapret2 ĐANG CHẠY
    sudo python3 test/t2-wire.py enp8s0 14 443 /tmp/A.json &
    sleep 2
    for u in https://github.com https://www.wikipedia.org; do
      curl -s -o /dev/null -m 8 --no-keepalive "$u"; sleep 1
    done
    wait

    # 3. Nhánh B: DỪNG zapret2 rồi đo lại y hệt
    sudo systemctl stop zapret2
    sudo python3 test/t2-wire.py enp8s0 14 443 /tmp/B.json

    # 4. BẬT LẠI OFFLOAD — quên bước này là giảm hiệu năng toàn hệ thống
    sudo ethtool -K enp8s0 tso on gso on gro on
    sudo systemctl start zapret2

Cách đọc kết quả
----------------
    zapret2 chạy : đoạn đầu   1 byte  (head=16, tức 0x16 = byte đầu ClientHello)
    zapret2 dừng  : đoạn đầu ~1400 byte (head=16030106…, nguyên ClientHello)

Phải so TỔNG số byte của hai nhánh: phải BẰNG NHAU. Tổng bằng nhau mà cách
chia khác ⇒ đúng nghĩa desync, không phải mất hay thêm gói.

Kết quả đo thật trên máy này (2026-09-29, kernel 7.2.7-lqx1-1-arisa):
    A (chạy)  : 1 / 1 / 1 byte    · tổng 1907 / 1920 / 1925
    B (dừng)  : 1424 / 1388 / 1348 · tổng 1907 / 1920 / 1925   (y hệt)
    IPv6      : 1 / 1 / 1 byte, ghi rõ họ IP trong từng nhóm (`[v6]`)

Giới hạn đã biết
----------------
Dừng zapret2 thì github/wikipedia/example vẫn trả 200 ⇒ môi trường này KHÔNG
có DPI chặn các site đó. Nên phần "tắt zapret2 thì domain bị chặn phải fail"
của INV-DESYNC-1 không kiểm được ở đây; cần lab có DPI giả lập.
"""
import socket, struct, sys, time, json, subprocess
"""Đo kích thước đoạn TCP đầu tiên mang ClientHello, ngay trên DÂY.

Vì sao không dùng tcpdump: tcpdump cũng chỉ thấy skb trước TSO. Cách này tự
phân tích header nên không cần cài gói, và in ra từng đoạn để đối chiếu.

Cảnh báo đo sai (đã dính): nếu TSO/GSO còn bật, host thấy MỘT skb lớn dù
trên dây có nhiều đoạn nhỏ. Vì vậy phải tắt TSO/GSO trước khi kết luận.
"""
import socket, struct, sys, time, json

IFACE = sys.argv[1] if len(sys.argv) > 1 else 'enp8s0'
DUR   = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0
SPORT = int(sys.argv[3]) if len(sys.argv) > 3 else 443     # cổng đích
OUT   = sys.argv[4] if len(sys.argv) > 4 else '/tmp/z2d-qa/seg.json'

ETH_P_ALL = 0x0003
TCP, ETHERTYPE_IP, ETHERTYPE_IPV6, ETHERTYPE_VLAN = 6, 0x0800, 0x86DD, 0x8100

def parse(pkt):
    if len(pkt) < 14: return None
    et = struct.unpack('!H', pkt[12:14])[0]; off = 14
    while et in (ETHERTYPE_VLAN, 0x88A8):                 # bóc VLAN nếu có
        if len(pkt) < off + 4: return None
        et = struct.unpack('!H', pkt[off+2:off+4])[0]; off += 4
    src = dst = None
    if et == ETHERTYPE_IP and len(pkt) >= off + 20:
        ihl = (pkt[off] & 0x0F) * 4
        if pkt[off+9] != TCP: return None
        tot = struct.unpack('!H', pkt[off+2:off+4])[0]
        proto_off = off + ihl
        src = socket.inet_ntop(socket.AF_INET, pkt[off+12:off+16])
        dst = socket.inet_ntop(socket.AF_INET, pkt[off+16:off+20])
        frag = struct.unpack('!H', pkt[off+6:off+8])[0]
        if frag & 0x1FFF: return None                      # bỏ mảnh sau
    elif et == ETHERTYPE_IPV6 and len(pkt) >= off + 40:
        if pkt[off+6] != TCP: return None
        src = socket.inet_ntop(socket.AF_INET6, pkt[off+8:off+24])
        dst = socket.inet_ntop(socket.AF_INET6, pkt[off+24:off+40])
        proto_off = off + 40
    else:
        return None
    if len(pkt) < proto_off + 20: return None
    sp, dp = struct.unpack('!HH', pkt[proto_off:proto_off+4])
    doff = (pkt[proto_off+12] >> 4) * 4
    flags = pkt[proto_off+13]
    seq  = struct.unpack('!I', pkt[proto_off+4:proto_off+8])[0]
    payload = pkt[proto_off+doff:]
    return dict(src=src, dst=dst, fam=('v6' if ':' in src else 'v4'), sp=sp, dp=dp, seq=seq, flags=flags,
                pay=len(payload), syn=bool(flags & 0x02), fin=bool(flags & 0x01),
                data=payload[:8])

s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
s.settimeout(0.5); s.bind((IFACE, 0))
flows, result = {}, []
t0 = time.time()
local = None
try:
    import subprocess
    local = subprocess.run(['ip','-4','route','get','1.1.1.1'],
                           capture_output=True, text=True).stdout
    local = local.split('src')[1].split()[0].strip() if 'src' in local else None
except Exception: pass

while time.time() - t0 < DUR:
    try: pkt = s.recv(65535)
    except socket.timeout: continue
    except OSError: break
    r = parse(pkt)
    if not r: continue
    if r['dp'] != SPORT and r['sp'] != SPORT: continue
    if r['syn'] and not (r['flags'] & 0x10):
        key = (r['src'], r['sp'], r['dst'], r['dp'])       # bắt đầu kết nối mới
        flows[key] = {'first_pay': None, 'segs': [], 't0': time.time(), 'fam': r['fam'], 'src': r['src'], 'dst': r['dst']}
        continue
    key = (r['src'], r['sp'], r['dst'], r['dp'])
    if key not in flows: continue
    f = flows[key]
    if r['pay'] == 0: continue
    f['fam'] = r['fam']; f['src'] = r['src']; f['dst'] = r['dst']
    f['segs'].append({'pay': r['pay'], 't_ms': round((time.time()-t0)*1000, 1),
                      'head': r['data'].hex()})
    if f['first_pay'] is None:
        f['first_pay'] = r['pay']
s.close()
json.dump({'iface': IFACE, 'local': local, 'flows': list(flows.values())},
          open(OUT, 'w'), indent=1)
n = sum(1 for f in flows.values() if f['first_pay'])
print(f"  nhom tin hieu (co du lieu): {len(flows)} · nhom co doan du lieu dau: {n}")
for f in flows.values():
    if f['first_pay'] is None: continue
    tot = sum(x['pay'] for x in f['segs'])
    famv = f.get('fam', '?')
    print(f"  [{famv}] doan dau = {f['first_pay']} byte · tong {tot} byte · so doan = {len(f['segs'])}")
    for x in f['segs'][:5]:
        print(f"      +{x['t_ms']:>8.1f}ms  {x['pay']:>5} byte  head={x['head']}")
