# NETWORK-DESIGN — hệ thống mạng 3 tầng

Mọi khẳng định trong tài liệu này đều từ phép thử chạy trên máy thật.
Không có gì ở đây là suy đoán. Ngày đo: **2026-09-28**, máy ở **AS18403 (FPT)**,
đo qua `enp8s0`.

---

## 1. Mô hình: ai quyết định chặn

```
        gói tin đi ra Internet
                 │
    ┌────────────▼─────────────┐
    │  TẦNG 1 · zapret2        │  sửa gói để DPI không đọc được tên miền
    │  nfqws2 · queue 300      │  ✗ KHÔNG quyết định chặn — không chặn gì cả
    └────────────┬─────────────┘
                 │
    ┌────────────▼─────────────┐
    │  TẦNG 2 · NextDNS (DoT)  │  ◀── TẦNG DUY NHẤT QUYẰT ĐỊNH CHẶN
    │  tên miền bị chặn ở đây  │      nằm trên đám mây, không phải trong máy
    └────────────┬─────────────┘
                 │
    ┌────────────▼─────────────┐
    │  TẦNG 2b · ufw tường DNS│  chỉ cho hỏi NextDNS, chặn DNS nơi khác
    └────────────┬─────────────┘      ✗ không quyết định chặn
                 │
    ┌────────────▼─────────────┐
    │  TẦNG 3 · ufw INPUT deny│  chặn theo cổng, trừ KDE Connect
    └──────────────────────────┘      ✗ không quyết định chặn
```

**Hệ quả quan trọng nhất:** tầng 1 và tầng 2b, tầng 3 đều *không* quyết định
chặn. Chỉ tầng 2 mới quyết định. Nói cách khác, hệ thống này **lọc theo tên
miền**, và tầng 1 chỉ là lưới an toàn cho những gì tầng 2 chưa chặn tới.

---

## 2. Sơ đồ tệp

```
TẦNG 1 ────────────────────────────────────────────────────────────────────
  /opt/zapret2/config                              quyết định desync
  /opt/zapret2/ipset/zapret-hosts-user.txt         RỖNG = bypass mọi 80/443
  /opt/zapret2/ipset/zapret-hosts-user-exclude.txt  9 dải IP miễn trừ
  ⚙ bảng nft `inet zapret2` + queue 300             trạng thái runtime, KHÔNG phải tệp
                                                    mất khi tắt zapret2

TẦNG 2 ────────────────────────────────────────────────────────────────────
  /etc/systemd/resolved.conf                       4 DNS + 4 FallbackDNS, DoT
  /etc/resolv.conf → symlink                       → stub của resolved
  /etc/NetworkManager/system-connections/*.nmconnection
                                                   ignore-auto-dns = true
  ☁ profile NextDNS trên đám mây                    17 blocklist · 83 deny · 117 allow

TẦNG 2b + 3 ───────────────────────────────────────────────────────────────
  /etc/ufw/user.rules      10 rule IPv4  ┐
  /etc/ufw/user6.rules     10 rule IPv6  ┘ 20 rule: 8 ALLOW + 8 DENY + 4 KDE
  /etc/default/ufw                      CHÍNH SÁCH policy + IPT_SYSCTL
  /etc/ufw/ufw.conf                     ENABLED · LOGLEVEL

HARDENING ──────────────────────────────────────────────────────────────────
  /etc/ufw/z2d-sysctl.conf                18 khoá — nguồn DUY NHẤT
  /etc/sysctl.d/60-z2d-hardening.conf ──► symlink tới tệp trên
  /etc/systemd/system/ufw.service.d/z2d-reapply-sysctl.conf   lớp 2
  /etc/pacman.d/hooks/z2d-pacman-ufw.hook                    lớp 3
  /usr/local/bin/z2d-sysctl-apply                             helper
```

---

## 3. Tầng 1 — zapret2 đang làm gì thật

**Cấu hình hiệu lực** (chép từ `/opt/zapret2/config`):

```
MODE_FILTER=hostlist        + danh sách user RỖNG  ⇒ không còn mệnh đề lọc
NFQWS2_PORTS_TCP=80,443     ⇒ phạm vi: TCP 80 và 443, KHÔNG phải mọi cổng
NFQWS2_PORTS_UDP=           (rỗng) ⇒ bỏ qua UDP
--payload=tls_client_hello --lua-desync=multisplit:pos=1
```

### Đo được: tầng 1 CẮT thật, không phải chỉ nhận gói

`multisplit:pos=1` cắt ClientHello làm hai đoạn, đoạn đầu mang **1 byte**.
Đo bằng cách nhìn gói tin thật trên `enp8s0` (raw socket `AF_PACKET`, không cần
tcpdump), tách theo từng kết nối, đo chiều dài đoạn TCP đầu tiên:

| | đoạn đầu của 5 kết nối tới :443 |
|---|---|
| tầng 1 **BẬT** | `[1, 1, 1, 1, 1]` byte |
| tầng 1 **TẮT** | `[1570, 1570, 1570, 1571, 1573]` byte |

A/B lặp 3/3 vòng, kết quả y hệt nhau.

### Nhưng tầng 1 KHÔNG giúp ích trên đường này

Vì sao không chứng minh được "nó cứu truy cập":

1. `viet69.be` và `erothots.co` bị NextDNS chặn (`ai-threat-detection`,
   `threat-intelligence-feeds`). Ép IP thẳng, giữ nguyên SNI: **HTTP 200**,
   TLS bắt tay bình thường, và **giống hệt khi tắt tầng 1**.
   ⇒ **không có chặn SNI/DPI**. Lưu lượng dừng ở tầng DNS vì không phân giải
   được tên, nên không tạo ra socket nào để desync.

2. 20 domain hay bị chặn ở Việt Nam đã khảo sát: **0** bị chặn ở tầng SNI.

**Kết luận thẳng:** chặn ở Việt Nam hiện nay chủ yếu là **chặn tầng DNS**,
và tầng DNS chính là tầng 2. Tầng 1 là lưới an toàn, không phải thứ đang cứu
truy cập. Không thể chứng minh ngược lại trên một đường không có gì bị chặn.

### Chặn ở tầng 2 có đẩy lưu lượng khỏi tầng 1 không

Có, và đo được: domain bị tầng 2 chặn trả `127.0.0.1`, mà `127.0.0.0/8` nằm
trong 9 dải loại trừ ⇒ lưu lượng đó **không bao giờ** vào queue desync.
Đo trên cùng một cột đếm: domain xuyên **+163 gói**, domain bị chặn **+0 gói**.

---

## 4. Tầng 2 — NextDNS

| mục | giá trị |
|---|---|
| DNS | 4 địa chỉ (2 IPv4 + 2 IPv6), mỗi cái kèm `#<ID>.dns.nextdns.io` |
| DoT | bật — bắt buộc, vì DNS cổng 53 thì nhà mạng tiêm được |
| LLMNR / mDNS | tắt |
| blocklist | 17 danh sách |
| denylist | 83 mục |
| allowlist | 117 mục |
| parental | 25 dịch vụ + 7 chuyên mục |

**`ignore-auto-dns` là bắt buộc.** Không tắt thì router vẫn quảng bá DNS của
nó qua DHCP, và mỗi truy vấn mất một vòng SYN bị chặn rồi mới fallback về
NextDNS. Riêng profile `lo` (loopback giả) không cần — không có router.

---

## 5. Tầng 2b — tường chặn DNS

16 rule: **8 ALLOW** (4 địa chỉ × 2 cổng, cả 2 họ) + **8 DENY** (4 cổng × 2 họ).

**THỨ TỰ QUAN TRỌNG:** ALLOW phải đứng trước DENY. ufw đánh giá tuần tự; đảo
lại là chặn luôn cả NextDNS ⇒ mất DNS.

Đo được tường này có tác dụng thật: `1.1.1.1:53`, `1.1.1.1:853`, `8.8.8.8:53`,
IPv6 `:53/853` — **tất cả đều bị chặn**; còn NextDNS `:853` thì mở.

---

## 6. Tầng 3 — chặn INPUT

`DEFAULT_INPUT_POLICY="DROP"` trong `/etc/default/ufw`, chỉ mở 4 rule
`1714:1764` (tcp+udp) cho `192.168.0.0/16` và `fe80::/10` — đủ cho KDE Connect
trong LAN.

Rule được tạo **trước**, policy đặt **sau**. Đảo thứ tự sẽ tự cắt kết nối của
chính người đang dùng máy.

---

## 7. Hardening — 18 khoá sysctl, một nguồn, hai đường nạp

`/etc/ufw/z2d-sysctl.conf` là nguồn duy nhất. Nó được nạp theo **hai** đường:

1. **Boot** — `/etc/sysctl.d/60-z2d-hardening.conf` là **symlink** tới tệp đó.
   Nếu chỉ để trong `/etc/ufw/` thì ufw không chạy là mất hardening.
2. **ufw** — `IPT_SYSCTL=/etc/ufw/z2d-sysctl.conf` trong `/etc/default/ufw`.

Ba lớp phòng thủ chống việc ufw ghi đè 2 khoá (`default.rp_filter`, `all.log_martians`):

| lớp | cơ chế | phủ trường hợp |
|---|---|---|
| 1 | `IPT_SYSCTL` trong `/etc/default/ufw` | `ufw reload` từ CLI (không đi qua systemd) |
| 2 | drop-in `ufw.service.d/` | mỗi lần ufw.service khởi động |
| 3 | hook pacman | nâng cấp gói ufw ghi đè `/etc/default/ufw` |

Đo 4 phép thử, cả 4 đạt: phá giá trị rồi `sysctl --system` → phục hồi;
`ufw --force reload` → không ghi đè; `systemctl restart ufw` → phục hồi;
2 khoá hay bị ghi đè nhất giữ đúng.

---

## 8. Những chỗ đã biết là chưa ổn

### 8.1 IPv6: tầng 1 có xử lý nhưng chưa thấy dấu desync

- Gói IPv6 **có** tới tầng 1: `curl -6` làm bộ đếm queue 300 tăng **+131 gói**,
  và bảng `inet zapret2` **có** rule ipv6 cho `dport { 80, 443 }`.
- Nhưng **21 luồng IPv6, không luồng nào có đoạn đầu ≤ 8 byte**
  (quan sát được: 1340–1380 byte khi bật, 1527–1534 khi tắt).

Nguyên nhân **chưa xác định**. Hệ quả: khẳng định "bypass mọi kết nối 80/443"
mới chỉ được kiểm chứng cho **IPv4**. Nếu nhà mạng lọc SNI trên đường IPv6,
cấu hình hiện tại có thể không chống được.

### 8.2 `ufw --force reload` từ CLI không đi qua systemd

Lớp 2 (drop-in) không bắn. Lớp 1 (`IPT_SYSCTL`) có phủ. Sau lệnh đó nên chạy
tay `sudo sysctl --system`.

### 8.3 Nội dung 17 blocklist không kiểm được

NextDNS không công bố nội dung danh sách. `profile-privacy.json` chỉ cho biết
tên và số mục. Muốn biết vì sao một trang bị chặn thì phải hỏi NextDNS tại
thời điểm đó.

---

## 9. Bẫy đo đã dính — ghi lại để không lặp

Đây là phần đáng giá nhất của tài liệu. Mỗi mục là một lỗi đã xảy ra thật và
đã tốn công tìm.

| bẫy | biểu hiện | sửa |
|---|---|---|
| `grep -c ... \|\| echo 0` | khi không khớp, grep in `0` **rồi trả về 1**, nên `\|\|` in thêm `0` nữa → giá trị `"0\n0"`, dòng kiểm báo LỆCH dù máy đúng | `\|\| true` |
| lookbehind biến thiên | `grep -oP '(?<=X\s*=\s*)'` → PCRE từ chối: *length of lookbehind assertion is not limited* | dùng `^X=\K` |
| `$?` sau `\|` | lấy trạng thái của lệnh cuối trong pipe, không phải của script | đo vào tệp, không pipe ra grep/sed |
| `grep -c 'LỆCH'` | khớp cả dòng tổng kết `0LỆCH` → mọi phép đo đều ≥1 | yêu cầu `^[[:space:]]+LỆCH[[:space:]]` |
| `ufw --force delete` trong vòng lặp | ufw **đọc stdin**, nuốt mất input của chính vòng lặp → dừng sớm (20 rule, 9 sót) mà script vẫn báo xong | `</dev/null` + vòng lặp đến hết + xác nhận còn 0 |
| `exit 1` trong pipeline | `while` chạy ở subshell → lỗi bị nuốt, dòng "OK" vẫn in | gom vào mảng bằng `mapfile`, kiểm ngoài pipeline |
| đếm dòng thay vì kiểm rule | 4 rule giả cùng chú `DNSWALL` là đủ để "đạt" khi rule thật đã mất | kiểm từng rule theo ngữ nghĩa |
| `ufw_has` chỉ khớp IPv4 | cột 2 của dòng IPv6 là `(v6)` ⇒ nhận đủ 16 rule OUT mà bỏ 4 rule IN | xử lý cả 3 bố cục + phân biệt "không có token hướng" với "có token khác hướng" |
| comment lưu dạng hex | `comment=7a3264206e657874646e73203533` ⇒ grep `z2d` trong `user.rules` **luôn ra 0** | đọc qua `ufw status`, không đọc thẳng tệp |
| `KEY = VALUE` cho zapret2 | config là **script shell** ⇒ `MODE_FILTER: command not found`, zapret2 không lên | `KEY=VALUE` + `bash -n` trước khi restart |
| `sed` trên khối nhiều dòng | `NFQWS2_OPT` nhiều dòng, sed chỉ thay dòng đầu ⇒ các dòng sau trôi thành lệnh lạ | một lượt `awk` xoá cả khối rồi chèn |
| `cp ... 2>/dev/null` trong backup | nuốt lỗi im lặng ⇒ bản sao lưu thiếu `opt/zapret2/config`, mất đúng thứ cần để quay lại | không che lỗi + xác nhận tệp bắt buộc tồn tại |
| phép thử rỗng | `dig @<IPv6 Cloudflare>` timeout **dù đã mở tường** ⇒ luôn báo "đã chặn", báo đạt giả | đổi sang TCP 853 qua IPv6, đo được là phân biệt được |

**Nguyên tắc rút ra:** một phép đo chỉ đáng tin khi nó phân biệt được *"đúng"* với
*"sai cấu trúc"*. Muốn biết phép đo có ích không, phải **tiêm một lỗi thật** xem
nó có bắt không. Chạy một lần thấy "đạt" là bằng không.

---

## 10. Trạng thái đã kiểm chứng

Đo ngày 2026-09-28, sau khi chạy `install.sh`:

```
install.sh              9/9 bước · 14/14 mục kiểm cuối · exit 0
install.sh --dry        vân tay trước/sau GIỐNG NHAU · 0 lần in "HOÀN TẤT"
install.sh lần 2        0 rule sửa thêm ⇒ idempotent
t1-config.sh            37/37 đạt · exit 0
bash -n · shellcheck    0 lỗi · 0 cảnh báo
18 khoá sysctl          18/18 đúng, qua cả 2 đường nạp
tường DNS               16/16 rule, kiểm từng rule cả 2 họ
```

Bằng chứng tiêm lỗi thật: xoá 4 rule DENY IPv6 → `t1` báo LỆCH đúng dòng đó;
đổi `MODE_FILTER` thành `none` → bắt được; làm đầy danh sách user → bắt được;
trỏ `IPT_SYSCTL` về tệp của ufw → bắt được; xoá drop-in → bắt được; đặt
`rp_filter` về 1 → bắt được; đổi policy sang `allow` → bắt được; tắt DoT →
bắt được. **8/8**.
