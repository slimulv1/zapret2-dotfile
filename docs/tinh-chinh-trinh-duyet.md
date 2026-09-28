# Ghim DoH cho trình duyệt

Tường chặn DNS (tầng 2b) chặn cổng **53** và **853**. Nhưng DoH chạy trên cổng
**443** — cùng cổng với web. Không có quy tắc nào chặn được DoH mà không chặn
cả web.

Nên nếu để trình duyệt tự bật DoH và tự chọn provider, nó sẽ hỏi một dịch vụ
khác NextDNS — **tầng 2 bị đi vòng**.

Mặc định:

| trình duyệt | mặc định | vấn đề |
|---|---|---|
| Firefox | `trr.mode = 5` | có fallback nhưng **không ghim provider** |
| Chromium | dùng DNS hệ thống | bị tường chặn, hoạt động bình thường |

Thay `785fad` bằng ID profile NextDNS của bạn.

## Firefox

Ghi vào **`user.js`**, không phải `prefs.js` — Firefox đọc `user.js` mỗi lần
khởi động nên không bị `prefs.js` ghi đè.

```bash
ND_ID=785fad
DOH="https://dns.nextdns.io/$ND_ID/dns-query"

for f in "$HOME"/.config/mozilla/firefox/*/user.js; do
  [ -f "$f" ] || continue
  sed -i '/network\.trr\.\(mode\|uri\|excluded\)/d' "$f"
  cat >> "$f" <<EOF

user_pref("network.trr.mode", 2);
user_pref("network.trr.uri", "$DOH");
user_pref("network.trr.excluded", "");
EOF
  echo "  cap nhat $f"
done
```

**Vì sao `mode 2` chứ không phải `3`.** `3` là bắt buộc DoH — DoH lỗi là mất
phân giải tên, tức mất DNS. `2` dùng DoH này nhưng lỗi thì lùi về DNS hệ thống,
tức vẫn về NextDNS qua DoT (cổng 853, nằm trong tường). `5` là mặc định của
Firefox: có fallback nhưng không ghim provider — chính là lỗ hổng.

**Endpoint phải có ID profile trong đường dẫn.** Thiếu thì NextDNS không biết
bạn dùng profile nào.

### ⚠ Ghi vào cả hai lớp profile

Trên CachyOS `~/.config` chạy qua **back-ovfs**, nên mỗi profile có nhiều thư mục:

```
68igij8q.default-release-back-ovfs    → trong $HOME     BỀN
68igij8q.default-release-backup       → trong $HOME     BỀN
68igij8q.default-release              → symlink tới /run/user/1000/psd/…  VOLATILE
```

Chỉ ghi một lớp thì mất cấu hình sau reboot. Vòng lặp ở trên ghi vào **mọi**
thư mục khớp nên đã bao gồm cả hai lớp bền; ghi thêm vào thư mục symlink là vô
hại nhưng không có tác dụng, vì `/run` là tmpfs.

## Chromium

`Preferences` là JSON một dòng ~50 kB. **Đừng dùng `sed`** — phải sửa bằng JSON
để không làm mất các khoá cấu hình khác.

```bash
ND_ID=785fad
P="$HOME/.config/chromium/Default/Preferences"
[ -f "$P" ] || { echo "khong tim thay $P — chromium chua chay lan nao"; exit 1; }
cp -a "$P" "$P.bak"

ND_ID="$ND_ID" python3 - "$P" <<'PY'
import json, os, shutil, sys, collections
p = sys.argv[1]
with open(p, encoding='utf-8') as f:
    d = json.load(f, object_pairs_hook=collections.OrderedDict)
h = d.setdefault('dns_over_https', collections.OrderedDict())
h['mode'] = 'secure'
h['templates'] = collections.OrderedDict([(
    'https://dns.nextdns.io/%s/dns-query' % os.environ['ND_ID'],
    collections.OrderedDict([('name', 'NextDNS')]))])
tmp = p + '.new'                       # ghi tệp tạm rồi mới thay
with open(tmp, 'w', encoding='utf-8') as f:
    json.dump(d, f, separators=(',', ':'), ensure_ascii=False)
shutil.copymode(p, tmp); shutil.copystat(p, tmp)
shutil.move(tmp, p)
print('  da ep DoH cho chromium')
PY
```

## Kiểm chứng

```bash
# Firefox: prefs.js phải ghi nhận setting vừa áp dụng
grep -E 'network.trr.(mode|uri)' "$HOME"/.config/mozilla/firefox/*/prefs.js

# Chromium
python3 -c "import json;d=json.load(open('$HOME/.config/chromium/Default/Preferences'));print(d['dns_over_https'])"

# Cổng 443 tới IP NextDNS = trình duyệt đang đi DoH của NextDNS.
# Cùng IP với DoT 853 nhưng khác cổng nên phân biệt được:
ss -tn | grep '45.90.28.0:443'
```

Nếu dòng cuối có kết nối tới `45.90.28.0:443` thì trình duyệt đang đi đúng
đường.

## Không nằm trong phạm vi script

Cài đặt **không** đụng tới trình duyệt, và `backup-3tang.sh` cũng không lưu phần
này. Clone repo về máy mới thì phải làm lại, nếu không lỗ hổng ở trên mở lại.
