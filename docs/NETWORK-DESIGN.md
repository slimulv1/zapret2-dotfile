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
    │  TẦNG 2 · NextDNS (DoT)  │  <<  TẦNG DUY NHẤT QUYẾT ĐỊNH CHẶN
    │  tên miền bị chặn ở đây  │      nằm trên đám mây, không phải trong máy
    └────────────┬─────────────┘
                 │
    ┌────────────▼─────────────┐
    │  TẦNG 2b · ufw tường DNS │  chỉ cho hỏi NextDNS, chặn DNS nơi khác
    └────────────┬─────────────┘      ✗ không quyết định chặn
                 │
    ┌────────────▼─────────────┐
    │  TẦNG 3 · ufw INPUT deny │  chặn theo cổng, trừ KDE Connect
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

### 8.2 ĐÃ kiểm trên máy trắng — và 8 lỗi chỉ lộ ra ở đó

Trước đây mục này ghi "chưa có bằng chứng". Nay **đã chạy thật**: xoá sạch
zapret2, NextDNS, ufw, sysctl, cấu hình NM, rồi cài từ đầu theo README.

Kết quả: **cài thành công**, nhưng phải sửa **8 lỗi thật** trước đó mới được.
Tất cả đều là loại "logic đúng, nhưng đặt sai chỗ" — chạy trơn trên máy đã
có sẵn, chết ngay trên máy trắng:

| # | lỗi | triệu chứng trên máy trắng |
|---|---|---|
| 1 | `ldconfig -p \| grep -q` + `pipefail` | `die` vì "thiếu thư viện" dù cả 5 đều có |
| 2 | backup giả định `/opt/zapret2/config` tồn tại | hỏng một lần là **không cài lại được** |
| 3 | không tạo `config` từ `config.default` | bước 4 chết "không có config" |
| 4 | copy unit nằm trong nhánh clone | `Unit zapret2.service not found` |
| 5 | kiểm rule trước khi bật ufw | "tường DNS không đủ 16 rule" dù đủ |
| 6 | `systemctl enable --now ufw` ≠ `ufw enable` | cờ `ENABLED=no` ⇒ `ufw status` rỗng |
| 7 | `ufw delete ALLOW OUT from …` sai cú pháp | uninstall **xoá được 0/16 rule** |
| 8 | uninstall bỏ sót unit ở `/usr/lib` và bảng `nft` | gỡ xong còn dấu vết tầng 1 |

Nguyên nhân chung đáng ghi nhất: **mọi phép thử trước đó chạy trên máy đã có
đủ mọi thứ**, nên nhánh "chưa có" của installer không bao giờ được chạy. Sửa
cách kiểm chứng, không chỉ sửa code: `test/t1-config.sh` chỉ đọc trạng thái
đã cài, nó không phát hiện được installer có chạy đúng trên máy trắng hay không.

### 8.2b Đối chiếu sơ đồ ↔ máy sống, và 5 chỗ sai

So từng phần tử của sơ đồ README với trạng thái thật:

| sơ đồ | đo được | kết luận |
|---|---|---|
| [1] hỏi ở cổng 853 | `ss` thấy `systemd-resolve → 45.90.28.0:853` | khớp |
| [1] chặn / cho qua | 2 domain chặn, 3 domain qua | khớp |
| [2] desync | queue bật cả `AF_INET` + `AF_INET6`, nhận gói thật | cơ chế đúng |
| [2] "đoạn đầu 1 byte" | **không đo được** (thiếu tcpdump) | thiếu bằng chứng |
| [3] chặn INPUT | kernel: `hook input … policy drop` cả 2 họ | khớp |
| [4] tường DNS v4+v6 | 3 server v4 + 2 server v6 đều `timed out` | khớp |

Cái đáng nói nhất: **trước khi soi, 15 phép kiểm của installer chỉ có 3 phép
là hành động thật**; 12 phép còn lại đọc tệp. Sơ đồ thì lại khẳng định về
**hành vi**. Ba chỗ đã sửa để khớp:

- `DoT` trước đây chỉ `grep 'DNSOverTLS=yes'` — hỏi "ta ghi gì vào tệp", không
  phải "máy có thật sự hỏi ở 853 không". Nay `ss` soi kết nối thật.
- `policy incoming` trước đây hỏi `ufw status` — ufw tự báo. Nay đọc
  `nft list ruleset`, kernel tự nói. Đo được cả `v4/v6`.
- `--dry` không kiểm 9 tệp config: xoá `config/z2d-exclude.txt` rồi chạy
  `--dry` vẫn in `XEM XONG`. `--dry` mất đúng tác dụng bắt lỗi trước khi cài.

Và 3 lỗi tra ra khi rà từng dòng:

1. **`--nd-key --dry` biến xem trước thành cài thật.** `--nd-key` nuốt cờ
   `--dry` làm giá trị của nó, `DRY` vẫn 0, script cài thật và in `HOÀN TẤT`.
   Đo được: `zapret2` restart lúc 11:39:37. Nay `need_val` chặn giá trị bắt
   đầu bằng `-`.
2. **ID NextDNS viết HOA bị từ chối.** Regex `^[0-9a-f]{6}$` chặn `785FAD`, dù
   API trả 200 cho cả ba kiểu hoa thường và bắt tay TLS với
   `<id>.dns.nextdns.io` cho cả ba đều trả 238 byte. Nay nhận cả hai và hạ
   về chữ thường.
3. **Con số mong đợi của phép kiểm tự thêm là bịa.** Lần đầu viết
   `chk "policy INPUT" … "1/1"` mà không đo trước; chạy thật ra `2/2` vì tôi
   đếm không tách được họ. Nay đếm theo bảng (`table ip` / `table ip6`).

**Bài học đắt nhất của lượt này:** hai phép kiểm mới tôi viết **đều sai ngay
lần đầu** — mẫu `grep 'systemd-resolve.*:853'` sai thứ tự (`ss` in địa chỉ
trước tên tiến trình) nên không bao giờ khớp; và nhãn 33 ký tự vượt giới hạn
32 mà chính chốt bảo vệ trong `chk` bắt được. Cả hai chỉ lộ ra khi chạy thật.
Một phép kiểm mới chỉ đáng tin sau khi **tiêm lỗi thật** và thấy nó bắt.

**Lần thứ hai (sau khi đã sửa 8 lỗi): cài thành công ngay lần đầu, không lộ
thêm lỗi nào.** Vì máy lần trước đã có `/opt/zapret2` do lần chết giữa chừng,
nên nhánh `clone` chưa từng chạy trọn với bản đã sửa. Lần này chạy đủ 4 nhánh
một lần: clone + `make systemd` → thư viện đủ 5 → 3 unit → tạo `config`.

Hai chỗ sai lệch so với upstream phát hiện được khi soi sâu (không phải lỗi
chặn cài, nhưng là chỗ nói dối):

- **Timer không được bật.** `install_easy.sh:559` enable
  `zapret2-list-update.timer`; ta chỉ enable `zapret2.service`. Đo được
  `GETLIST=` rỗng nên `get_config.sh` không có gì tải — chạy tay thì chỉ in
  "reloading nftables set backend (forced-update)", thoát 0, `config` không đổi
  (đã diff). Nên bật cũng vô hại, cũng vô dụng. Comment cũ của ta viết "Đây cũng
  là 3 unit mà install_easy.sh cài" đọc ra như thể bám sát cả hành vi. Đã sửa
  comment nói thẳng là không bật và vì sao.
- **Thư mục `ufw.service.d/` rỗng còn lại sau `--uninstall`.** Systemd bỏ qua
  nên vô hại, nhưng là tàn dư do ta tạo — cùng loại với unit rác ở `/usr/lib`
  đã sửa. Nay xoá, **nhưng chỉ khi thư mục rỗng**: nếu người dùng có drop-in
  riêng thì khối khôi phục đã đặt lại chúng, xoá thư mục là xoá việc của họ.
  Thử cả hai ca: rỗng → xoá; có file của người dùng → giữ nguyên nội dung.

`need_pkgs` (tự `pacman -S` khi thiếu gói) là phần **chưa** được chạy thật —
nhưng đây **không phải** khiếm khuyết của installer. Lý do: `gcc`, `make`,
`git`, `nftables`, `ufw`, `luajit` là **gói nền** của máy, và máy bình thường
đã có chúng. Tôi từng định gỡ để "làm trắng" rồi mới hiểu là sai: gỡ nền tảng
để chứng minh một hàm tự cài là cách kiểm sai, và nó còn làm hỏng `paru`,
`mpv`, `gamescope`, `dnsmasq`, `dkms` — những gói phụ thuộc vào chúng.

"Máy trắng" ở đây nghĩa là **không còn hệ thống 3 tầng** (zapret2, NextDNS,
tường ufw, sysctl, cấu hình NM), không phải **không có gói build**. Xem bảng
trên: 8 lỗi tìm ra đều thuộc loại thứ hai, và tìm ra hết từ cấu hình.

### 8.3 `ufw --force reload` từ CLI không đi qua systemd

Lớp 2 (drop-in) không bắn. Lớp 1 (`IPT_SYSCTL`) có phủ. Sau lệnh đó nên chạy
tay `sudo sysctl --system`.

### 8.4 Nội dung 17 blocklist không kiểm được

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
| `printf '%-32s'` của bash | luôn đệm theo **BYTE**, kể cả khi `LC_CTYPE` là UTF-8. Nhãn tiếng Việt có dấu ⇒ 1 ký tự 2 byte ⇒ cột hụt tới 3 ký tự, ngay ở bản gốc | `local LC_ALL=C.UTF-8` trong hàm, để `${#1}` đếm KÝ TỰ rồi tự tính khoảng trắng |
| `${#x}` dưới `sudo` | `sudo` xoá biến `LC_*` ⇒ `${#x}` đếm **byte** trong khi lúc đo tay bằng tay tính **ký tự** ⇒ chốt "≤ 32 ký tự" báo sai 31 thành 33 | đo cả hai cách trước khi tin; chỗ nào cần thì `export LC_ALL` cục bộ |
| `pkill -f 'qemu-system…'` | `-f` khớp **cả dòng lệnh shell đang chạy** vì dòng đó chứa đúng chuỗi cần tìm ⇒ tự giết chính mình, mất output | tách PID ra tệp, `kill "$PID"` |
| `pkill -f` + `sudo` trong cùng lệnh | `sudo` chờ mật khẩu, PAM khoá tài khoản sau 3 lần sai | dùng `SUDO_ASKPASS`; xoá helper **sau** khi xong, đừng xoá giữa chừng |
| đếm dòng có mã màu ANSI | `grep -cE '^ +(OK\|LỆCH)'` ra 0 vì dòng bắt đầu bằng mã màu, không phải khoảng trắng | `sed 's/\x1b\[[0-9;]*m//g'` rồi mới đếm |
| `producer \| grep -q` + `set -o pipefail` | `grep -q` thoát sớm ⇒ producer nhận **SIGPIPE (141)** ⇒ pipefail trả 141 ⇒ coi thứ **đang có** là **thiếu**. Đo: `ldconfig -p \| grep -q` hỏng **20/20 lần** vì output 3760 dòng (~300 KB) vượt đệm pipe 64 KB; `nm -D` 212 dòng thì **0/100 lần** vì nằm vừa đệm | bỏ `grep -q`: lấy output một lần rồi so khớp bằng `case` của bash. Cùng mẫu lệnh, khác hành vi — đừng suy từ chỗ chạy được |
| `systemctl enable --now ufw` | **KHÔNG** bật cờ `ENABLED=yes` trong `/etc/ufw/ufw.conf`, nên `ufw status` vẫn in `Status: inactive` và **không in bảng rule**, dù `is-active` là `active` | dùng `ufw --force enable` (`--force` vì `ufw enable` sẽ hỏi xác nhận rồi chờ, script không tương tác thì treo) |
| kiểm trạng thái trước khi bật dịch vụ | đọc `ufw status` khi ufw chưa bật ⇒ bảng rỗng ⇒ mọi kiểm tra rule FAIL dù rule đã ghi đúng vào `user.rules` | tạo hết rule **rồi mới** bật tường, kiểm sau cùng |
| `ufw delete ALLOW OUT from <ip> to any port …` | sai cú pháp ⇒ `ERROR: Invalid syntax`, ufw **không xoá gì** mà vẫn trả 0. uninstall âm thầm để lại toàn bộ 20 rule | cú pháp phải **khớp đúng** lệnh đã thêm: `delete allow out to <ip> port …` và `delete allow in from <src> to any port …` |
| `ufw` phân biệt HOA/thường | `ufw delete ALLOW OUT …` → Invalid syntax; `ufw delete allow out …` → Rule deleted | hạ chữ ngay trong hàm: `act=${1,,}; dir=${2,,}` — nơi gọi viết kiểu nào cũng chạy |
| logic đặt trong nhánh không phải lúc nào cũng vào | copy unit và kiểm thư viện nằm trong nhánh `else` (nhánh clone) ⇒ máy đã có `/opt/zapret2` thì **không bao giờ** chạy | đặt việc cần luôn xảy ra **ngoài** if/elif/else; chỉ phần *clone* mới nằm trong nhánh |
| gọi `cp` cho tệp có thể chưa tồn tại | backup chết vì `/opt/zapret2/config` chưa sinh (chỉ `config.default` mới có) ⇒ hỏng một lần là không cài lại được, phải xoá tay | chỉ sao lưu thứ **đang có**, in ra thứ bỏ qua |
| gỡ không đụng tới thứ build sinh ra | `make systemd` để lại 3 unit ở `/usr/lib/systemd/system/`; `pacman -Qo` trả rỗng (không gói nào sở hữu) | gỡ ở **cả** `/etc` và `/usr/lib`, rồi đếm còn sót và cảnh báo |
| `systemctl list-unit-files` mẫu regex hẹp | mẫu `^zapret2(-list-update)?\.` **không khớp** `zapret2-bc2.service` nên cảnh báo im lặng đúng lúc còn sót | `^zapret2.*\.`; và luôn thử bằng unit thật, đừng chỉ tin regex |
| bảng `nft` tự tồn tại sau khi dừng dịch vụ | `nft list tables` vẫn còn `table inet zapret2` + set 522288 phần tử sau `--uninstall` | `nft delete table inet zapret2` trong `uninstall()` |
| khối đặt ngoài chốt `--dry` | khối xoá bảng nft tôi viết nằm **sau** `fi` của `if [ "$D" = 1 ]` ⇒ `--uninstall --dry` sẽ xoá thật | `--dry` phải được kiểm bằng cách so trạng thái trước/sau, không tin lời in |
| bộ đo của tôi tự báo sai ba lần | (a) `awk '/^300 /'` không khớp vì dòng procfs **có thụt lề đầu dòng** ⇒ tầng 1 bị báo là không nhận gói; (b) `diff <(sudo cat A) <(sudo cat B)` cho kết quả bịa vì `sudo` trong process substitution; (c) `awk '/^done$/'` không khớp `  done` ⇒ trích ra **file rỗng** rồi kết luận "fix hỏng 60/60" | đo lại bằng `$1==300`; so sánh bằng file trên đĩa; kiểm tra file trích có dòng trước khi tin. **Nguyên tắc: phép đo hỏng thì báo "không đo được", không báo số** |
| bỏ qua nội dung của systemd | `install.sh` copy 3 unit giống upstream nhưng chỉ enable 1, comment lại viết như bám sát cả hành vi | đọc `install_easy.sh` đối chiếu từng dòng `enable`; nếu cố ý khác thì nói thẳng và nêu lý do |
| mẫu `grep` sai thứ tự trong một dòng | `ss` in `… 45.90.28.0:853 users:(("systemd-resolve",…))` — địa chỉ **trước** tên tiến trình, nên `grep 'systemd-resolve.*:853'` không bao giờ khớp và cảnh báo báo đạt giả | tách hai lần `grep` trên cùng dòng: `\| grep systemd-resolve \| grep -q ':853'` |
| đặt số mong đợi mà không đo trước | `chk "policy INPUT" … "1/1"` viết từ trí nhớ; chạy thật ra `2/2` vì đếm không tách được họ IPv4/IPv6 | đếm theo bảng (`table ip` / `table ip6`) trước khi viết kỳ vọng |
| `--dry` không kiểm tệp cấu hình | xoá `config/z2d-exclude.txt`, `--dry` vẫn in `XEM XONG` exit 0 — công cụ xem trước không bắt được lỗi nó sinh ra để bắt | kiểm đủ 9 tệp ở bước 1; `--dry` phải **chặt** chứ không chỉ báo |
| tham số nuốt cờ khác | `--nd-key --dry` ⇒ `--nd-key` ăn cờ `--dry`, `DRY=0`, script **cài thật** | `need_val` chặn giá trị bắt đầu bằng `-` |
| đo bằng regex khi cần chuỗi có nhiều thứ tự | `grep 'A.*B'` trên dòng thực tế là `B … A` | tách thành nhiều `grep`, hoặc `awk` với điều kiện rời |
| gỡ gói nền để "làm trắng máy" || gỡ gói nền để "làm trắng máy" | `gcc`, `make`, `git`, `nftables`, `ufw`, `luajit` là **gói nền**; gỡ chúng làm hỏng `paru`, `mpv`, `gamescope`, `dnsmasq`, `dkms` (pacman từ chối cả lệnh). Tệ hơn: nó **không kiểm được** gì | "trắng" = không còn hệ thống 3 tầng, **không** phải không có gói build. Muốn thử `need_pkgs` thì dùng container, đừng gỡ gói nền trên máy thật |
| phép thử rỗng | `dig @<IPv6 Cloudflare>` timeout **dù đã mở tường** ⇒ luôn báo "đã chặn", báo đạt giả | đổi sang TCP 853 qua IPv6, đo được là phân biệt được |

**Nguyên tắc rút ra:** một phép đo chỉ đáng tin khi nó phân biệt được *"đúng"* với
*"sai cấu trúc"*. Muốn biết phép đo có ích không, phải **tiêm một lỗi thật** xem
nó có bắt không. Chạy một lần thấy "đạt" là bằng không.

---

## 10. Trạng thái đã kiểm chứng

Đo ngày 2026-09-28, sau khi chạy `install.sh`:

```
install.sh              đủ bước · 15/15 mục kiểm cuối · exit 0
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
