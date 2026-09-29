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
NFQWS2_PORTS_UDP=443        ⇒ thêm QUIC (HTTP/3)
```

### Đo được: tầng 1 CẮT thật, không phải chỉ nhận gói

Cấu hình hiện tại (xem `docs/RESEARCH-DPI.md` vì sao chọn):

```
--payload=tls_client_hello
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid,padencap
  --lua-desync=multisplit:pos=1,midsld
```

Cấu hình này **bơm một gói giả 684 byte** trước dữ liệu thật, rồi **cắt** phần
thật. Đo bằng cách nhìn gói tin thật trên `enp8s0` (raw socket `AF_PACKET`, không
cần tcpdump), tách theo từng kết nối:

| | IPv4 | IPv6 |
|---|---|---|
| tầng 1 **BẬT** — đoạn đầu | 684 byte (gói giả) | 684 byte (gói giả) |
| tầng 1 **BẬT** — số đoạn | 10 | 11 |
| tầng 1 **BẬT** — tổng | 2591 byte | 2604 byte |
| tầng 1 **TẮT** — đoạn đầu | 1424 byte | 1388 byte |
| tầng 1 **TẮT** — tổng | 1907 byte | 1920 byte |

**Số cần đọc là phép trừ, không phải con số "đẹp"**:

```
IPv4:  1907 + 684 = 2591   ✓
IPv6:  1920 + 684 = 2604   ✓
```

Luồng thật **giữ nguyên từng byte**; gói giả là cộng thêm đúng 684 byte, không
thay một byte nào của dữ liệu thật. Đây là bằng chứng mạnh hơn hẳn so với kiểu
kiểm cũ (xem §8.1b — kiểm cũ chỉ đúng với `multisplit` trần, vì chiến lược đó
chỉ **đảo thứ tự** chứ không **bơm thêm**).

Và đoạn đầu **không chứa tên miền thật**: tách SNI ra được `None` ở cả IPv4 lẫn
IPv6, cả khi tầng 1 bật. Đó mới là mục đích của desync — một DPI chỉ soi đoạn
đầu thì không thấy tên miền.

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
| [2] "đoạn đầu không lộ tên miền" | **đã đo**: tách SNI đoạn đầu = `None` khi zapret2 chạy; luồng thật giữ nguyên (`1907+684=2591`, `1920+684=2604`) | khớp |
| [2] IPv6 cùng phép đo | `curl -6` cho đoạn đầu 684 byte, tổng 2604 = 1920 + 684 | khớp |
| [1] DNS qua IPv6 | chặn riêng 2 IP v4 ⇒ `resolvectl` vẫn phân giải; `ss` thấy `systemd-resolve → [2a07:a8c0::]:853` | khớp |
| [3] chặn INPUT | kernel: `hook input … policy drop` cả 2 họ; **quét từ "máy ngoài"**: chỉ 1716 `open` khi nguồn trong `192.168.0.0/16`, mọi cổng `filtered` khi nguồn ngoài | khớp |
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

### 8.2c Rà `uninstall()` lần ba: 3 chỗ để lại dấu vết

`uninstall()` đã sửa 2 vòng trước (unit rác ở `/usr/lib`, bảng `nft`). Rà kỹ
thêm thì còn 3 chỗ, đều là "gỡ xong nhưng máy chưa về đúng trạng thái cũ":

1. **`/etc/resolv.conf` không được sao lưu.** Bước 5 `rm -f` rồi tạo symlink trỏ
   stub, nhưng danh sách sao lưu không có mục này. Nếu tệp gốc là TỆP THẬT
   (máy dùng resolvconf, hoặc admin tự viết) thì mất luôn, không phục hồi được.
   Nay thêm vào danh sách.
2. **`cp` khi khôi phục đi theo symlink.** `/etc/resolv.conf` sau khi cài là
   symlink; `cp -a backup /etc/resolv.conf` sẽ ghi ĐÈ mất
   `/run/systemd/resolve/stub-resolv.conf` mà symlink vẫn trỏ vào đó. Nay `rm`
   trước rồi mới `cp`. Đo được: stub còn nguyên 920 byte, mtime không đổi.
3. **Policy INPUT không được khôi phục.** Bản đầu chỉ `ufw default deny incoming`
   mà không lưu giá trị cũ ⇒ gỡ xong vẫn còn `deny` dù hệ thống đã bị gỡ hết.
   `ufw status verbose` trong backup chỉ để người đọc, code không dùng lại. Nay
   ghi `ufw-policy-in.txt` lúc sao lưu và đặt lại lúc gỡ. Vòng kiểm chứng:
   `allow → cài → deny → gỡ → allow`.
4. **`rm -f` bị lặp hai lần** trên cùng một tệp drop-in — sót từ lần sửa trước.

### 8.3 `ufw --force reload` từ CLI không đi qua systemd

Lớp 2 (drop-in) không bắn. Lớp 1 (`IPT_SYSCTL`) có phủ. Sau lệnh đó nên chạy
tay `sudo sysctl --system`.

### 8.4 Nội dung 17 blocklist không kiểm được

NextDNS không công bố nội dung danh sách. `profile-privacy.json` chỉ cho biết
tên và số mục. Muốn biết vì sao một trang bị chặn thì phải hỏi NextDNS tại
thời điểm đó.

---

### 8.1b Đo desync trên dây — không cần `tcpdump`, và những bẫy của nó

Trước đây mục này ghi *"không đo được, thiếu tcpdump"*. Sai: `tcpdump` chỉ là
một cách, và cách đó còn **không đáng tin** khi offload còn bật. Đo bằng raw
socket `AF_PACKET` tự phân tích header, không cài gói nào.

```python
# tests/qa/wire.py — lược
s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
s.bind(('enp8s0', 0))          # chỉ bắt trên đúng NIC đang định tuyến
# bóc Ethernet → (VLAN) → IPv4/IPv6 → TCP; gom đoạn đầu tiên mang dữ liệu
# của mỗi nhóm 4-tuple, sau SYN
```

**Bẫy 1 — offload làm ra số sai.** `tcp-segmentation-offload: on` ⇒ kernel đưa
cả khối lớn xuống NIC, NIC mới chia trên dây. `AF_PACKET` trên host nằm *trước*
bước chia, nên host thấy **một skb lớn** dù trên dây có nhiều đoạn nhỏ. Đo mà
quên tắt TSO/GSO thì ra số hoàn toàn sai. Phải:

```bash
ethtool -K enp8s0 tso off gso off gro off   # trước khi đo
ethtool -K enp8s0 tso on  gso on  gro on    # bắt buộc bật lại sau khi đo
```

**Bẫy 2 — phải có nhánh đối chứng.** Một con số "1 byte" mà không có nhánh
"tắt zapret2" thì không chứng minh gì: nếu máy vốn đã chia nhỏ thì cũng ra 1.
Đo cả hai, rồi so **tổng số byte** — nhưng cách so phụ thuộc chiến lược:

| chiến lược | tổng byte có bằng không | vì sao |
|---|---|---|
| `multisplit` (chỉ cắt) | **phải bằng** | chỉ **đảo thứ tự** byte, không sinh thêm |
| `fake` (bơm gói giả) | **phải hơn đúng số byte gói giả** | sinh thêm dữ liệu mới |

Đo được trên cấu hình hiện tại (`fake` + `multisplit`):

| | zapret2 chạy | zapret2 dừng | phép trừ |
|---|---|---|---|
| đoạn đầu | **684 byte** (gói giả) | **1424 / 1388 byte** (`head=16030106…`) | — |
| số đoạn | 10 / 11 | 8 / 8 | — |
| tổng byte | 2591 / 2604 | 1907 / 1920 | **+684 cả hai** |

`1907 + 684 = 2591` và `1920 + 684 = 2604` ⇒ luồng thật giữ nguyên từng byte, gói
giả chỉ là phần cộng thêm. Đây là cách đúng để chứng minh "desync, không phải mất
gói" **với** chiến lược có bơm gói giả. (Với `multisplit` trần thì tổng phải bằng
đúng — đừng dùng tiêu chí "bằng" cho mọi chiến lược.)

**Bẫy 2b — đo chiều dài đoạn đầu thì đo nhầm gói giả.** Câu hỏi *"desync có ẩn tên
miền không?"* không phải *"đoạn đầu dài bao nhiêu"*. Khi có `fake`, đoạn đầu là
**gói giả**, nên đo chiều dài cho kết luận sai. Bản đầu của bộ đo rơi vào đúng
bẫy này: thấy `684` thay vì `1` rồi tưởng cấu hình mới hỏng. Cách đúng là **tách
SNI** trong đoạn đầu (`tests/lab/dpi.py:parse_sni`) và đòi nó khác tên miền thật.

**Bẫy 3 — `dig` là công cụ sai cho địa chỉ NextDNS v6.** `dig @[2a07:a8c0::]`
báo `couldn't get address for '[2a07:a8c0::]': failure` — đây là `getaddrinfo`
của `dig` không phân tích được literal dạng `::`, **không phải** mạng hỏng.
Vài cách kiểm lại:

```bash
dig @2a07:a8c0:0:0:0:0:0:0 …          # viết đủ 8 nhóm — vẫn timeout
dig +tls -p 853 @45.90.28.0 …         # DoT phải có +tls, không có thì im lặng
# bằng chứng đúng: chặn RIÊNG 2 IP v4 (bảng nft tạm) → resolvectl vẫn ra kết quả
ss -tnp | grep 2a07:a8c0              # systemd-resolve → [2a07:a8c0::]:853  ESTAB
```

Ba domain **chưa từng được cache** đều phân giải được lúc v4 bị chặn ⇒ loại trừ
giả thuyết "resolved đọc cache". `ss` mới là bằng chứng quyết định.

**Còn chưa đo được:** dừng zapret2 thì `github`/`wikipedia`/`example` vẫn trả
200 ⇒ **môi trường này không có DPI chặn các site đó**, nên phần *"tắt zapret2
thì domain bị chặn phải fail"* của INV-DESYNC-1 **không kiểm được ở đây**.
Muốn kiểm phần đó cần lab có DPI giả lập (nft payload match SNI/Host).

**Phát hiện phụ (2026-09-29) — IPv6 tới NextDNS trên 53/udp không dùng được**

Bức tường cho phép `2a07:a8c0:: 53/udp`, nhưng truy vấn tới đúng địa chỉ đó vẫn
timeout. Đo kỹ để không đoán:

```
ip6 daddr 2a07:a8c0:: udp dport 53  counter packets 3 → 4   ← tăng
ip6 daddr 2a07:a8c0:: tcp dport 853 counter packets 2 → 3   ← tăng
dig +time=4 @2a07:a8c0:: github.com A            → timed out
dig +time=5 +tls -p 853 @2a07:a8c0:: … github   → status: NOERROR
```

Counter tăng nghĩa là **rule ufw khớp và gói đã ra khỏi máy**; không có câu trả lời
là bên kia im lặng. Cùng địa chỉ đó trên **853/DoT thì tốt**. Vì hệ thống bật
`DNSOverTLS=yes` nên nó đi 853 ⇒ **không ảnh hưởng gì**, chỉ là rule
`… 53/udp ALLOW` trên IPv6 hiện **chưa bao giờ có tác dụng** trên đường này.
Giữ rule vẫn đúng (nó đúng khi đường đó dùng được), chỉ là không được dùng.

### 8.1c Phát hiện 2026-09-29 — tắt `ip_forward` làm mất một khoá hardening

Khi dựng lab DPI (netns + veth), sau khi gỡ lab, `t1-config.sh` báo:

```
LỆCH  khoá sysctl đúng   thực tế=[17] mong đợi=[18]
```

Truy ra nguyên nhân, và nó **không** nằm ở lab:

```
net.ipv4.ip_forward=1 → net.ipv4.conf.all.accept_redirects = 0
net.ipv4.ip_forward=0 → net.ipv4.conf.all.accept_redirects = 1
```

Lặp lại **3/3 lần** cho cùng kết quả. Khi IPv4 forwarding bị tắt, kernel đặt
lại nhóm tham số định tuyến về mặc định, và mặc định của `accept_redirects` là
`1`. Tệp `/etc/sysctl.d/60-z2d-hardening.conf` dòng 43 vẫn ghi `= 0` — tức
**cấu hình và thực tế đã lệch nhau**.

Ý nghĩa: bất kỳ sự kiện nào tắt/bật IPv4 forwarding — đổi mạng, container,
`systemd-networkd`, một script nào đó — đều có thể **âm thầm làm yếu tầng 3 đi
một khoá**. Hiện chỉ có drop-in `ufw.service.d/z2d-reapply-sysctl.conf` nạp lại
sysctl khi `ufw` khởi động; một sự kiện chỉ đụng `ip_forward` thì không kích
hoạt drop-in đó.

Cách vô hiệm hóa tạm thời (đã áp dụng trong `tests/lab/setup.sh`): sau khi trả
`ip_forward` về giá trị cũ, nạp lại tệp hardening.

```
sysctl -p /etc/sysctl.d/60-z2d-hardening.conf
```

Còn việc chữa lâu dài (chưa làm, cần chốt hướng) thuộc về câu hỏi: có nên thêm
một `systemd.path` theo dõi `/proc/sys/net/ipv4/ip_forward` không.

### 8.1d Đo tầng 3 từ "máy ngoài" — `INV-IN-1` (2026-09-29)

Không có máy thứ hai trong nhà, nên dựng một máy ngoài bằng network namespace
nối qua veth. Gói của nó đi đúng chuỗi `prerouting → INPUT` của máy thật —
khác với việc đọc cấu hình, đây là phép đo thật.

Máy quét tự viết (`tests/lab/scan.py`), không dùng `nmap`: cài phần mềm mới
vào đúng máy đang kiểm rồi không dám xoá là chuyện lệ chuẩn. Quét kiểu
`connect()` vẫn là phép thử thật — SYN đi qua đúng chuỗi, và nếu tường chặn
thì kết nối treo.

**Đối chiếu bắt buộc trước khi kết luận:** phải xác nhận `kdeconnectd` thật sự
đang lắng nghe. Không có bước này thì "1716 filtered" cũng đúng với máy đã tắt
dịch vụ — tức phép thử không phân biệt được tường với dịch vụ chết.

```
$ ss -tlnp | grep :1716
LISTEN 0  50  *:1716  *:*  users:(("kdeconnectd",pid=2218,fd=19))
```

Kết quả, cùng một lần quét, chỉ khác NGUỒN:

| cổng | nguồn `192.168.99.2` (trong LAN) | nguồn `203.0.113.5` (ngoài subnet) |
|---|---|---|
| **1716** | **open** | **filtered** |
| 1714 1715 1763 1764 | closed (tường cho qua, không có dịch vụ) | filtered |
| 22 53 80 443 3306 5432 8080 | filtered | filtered |

Ba trạng thái là ba kết luận khác nhau, không được gộp:
`open` = vào được · `closed` = tường cho qua nhưng không có dịch vụ ·
`filtered` = tường DROP.

**Hai bẫy đo đã dính khi làm lab này**

1. **Nguồn gói không phải điều ta nghĩ.** Đã gán `192.168.99.2` cho netns nhưng
   gói tới `192.168.1.24` đi theo route mặc định, nên kernel chọn nguồn
   `10.98.0.2` — không thuộc `192.168.0.0/16`, rule KDE Connect không khớp.
   Đo được: counter `ufw-user-input` = 0 dù quét đúng cổng 1716. Phải ép bằng
   `ip route replace 192.168.1.24/32 dev vin0 src 192.168.99.2`.
2. **`getsockopt(SO_ERROR)` không lấy được lỗi.** Nó **xoá** lỗi sau khi đọc và
   trả 0, nên 13/13 cổng đều bị gán `closed` trong khi tường đang DROP. Phải
   đọc errno trực tiếp từ `connect_ex` và phân biệt `ECONNREFUSED` (có RST) với
   `ETIMEDOUT`/`EHOSTUNREACH` (không có phản hồi).

**Còn chưa chứng minh:** đây vẫn là một netns, không phải một máy vật lý khác.
Chuỗi kernel, chuỗi nft và chính sách ufw là như nhau, nhưng không thay được việc
quét từ một máy thật trong cùng tầng mạng vật lý (ví dụ qua Wi-Fi, qua switch
thật, hay kiểm rằng ARP/broadcast/PACKET_MATCH bị hạn chế ở tầng link).

### 8.1e Canh khoá hardening — `z2d-sysctl-guard` (2026-09-29)

§8.1c nêu lỗ hổng: bật rồi tắt IPv4 forwarding làm kernel đặt lại
`net.ipv4.conf.all.accept_redirects` về `1`. Cơ chế canh:

| tệp | vai trò |
|---|---|
| `config/z2d-sysctl-guard` | script, **chỉ ghi khoá đang lệch** |
| `config/z2d-sysctl-guard.path` | `PathChanged` trên `/proc/sys/net/ipv4/ip_forward` và `/proc/sys/net/ipv4/conf/all/accept_redirects` |
| `config/z2d-sysctl-guard.service` | `Type=oneshot`, gọi script |

**Vì sao phải "chỉ ghi khi lệch":** nếu dùng `sysctl -p`, mỗi lần ghi đều phát
sự kiện trên procfs ⇒ path unit bắn lại ⇒ service chạy lại ⇒ **vòng lặp không
dừng**. Đây là điều đã cân nhắc TRƯỚC khi viết, không phải phát hiện sau.

Đã kiểm `systemd.path` bắt được tệp trong `/proc` không: **có** — thử bằng
`PathChanged=/proc/sys/net/ipv4/ip_forward` rồi đổi giá trị, service bắn.

Chứng minh trên máy thật:

```
đặt accept_redirects = 1        → ngay lập: 1   → sau 3s: 0  ✔
ip_forward 0→1→0                → ngay lập: 1   → sau 4s: 0  ✔ tự lành
chờ 20 giây, journal đứng yên  → 4 dòng trước, 4 dòng sau  ✔ KHÔNG lặp
```

Script ghi vào `syslog` (nhãn `z2d-sysctl-guard`) mỗi khi sửa, kèm nghi phạm:
*"có thể do ai đó bật rồi tắt IPv4 forwarding"* — để việc siết bị nới lỏng không
còn diễn ra trong im lặng.

**Giới hạn đã biết:** cơ chế này bảo vệ `accept_redirects` và mọi khoá khác trong
tệp hardening. Nó **không** ngăn được thay đổi xấu ở tầng khác — ví dụ ai đó
sửa trực tiếp `/etc/sysctl.d/60-z2d-hardening.conf`. Tầng bảo vệ còn lại là
`ufw.service.d/z2d-reapply-sysctl.conf` (nạp lại mỗi lần `ufw` chạy) và
`tests/lab/setup.sh` (nạp lại sau khi đụng `ip_forward`).

## 9. Bẫy đo đã dính — ghi lại để không lặp
| `pacman -Qkk \| grep -c 'modified:'` | Qkk **không** dùng chữ `modified:`, nó ghi `\"... (SHA256 checksum mismatch)\"` ⇒ grep trả **0 giả**, tưởng không tệp nào bị sửa | đếm `grep -c SHA256`, và luôn đối chiếu trực tiếp tệp khi kết luận |
| `[ -e \"/var/backups/…\" ]` bằng user thường | thư mục `root` 700 ⇒ `[ -e ]` trả **false dù tệp có thật** ⇒ kết luận \"không có trong backup\" | đo bằng `sudo -A test -e` |
| `dig @[2a07:a8c0::]` | `couldn't get address for '[2a07:a8c0::]': failure` — đây là `getaddrinfo` của dig **không** phân tích được literal dạng `::`, **không phải** mạng hỏng | bằng chứng thật: chặn riêng v4 + `ss` thấy `systemd-resolve → [2a07:a8c0::]:853` |
| `dig -p 853` không kèm `+tls` | gửi DNS **rõ** qua cổng DoT ⇒ NextDNS im lặng ⇒ tưởng đường v6 chết | `dig +tls -p 853 @…` |
| đo đoạn khi TSO/GSO còn bật | host thấy **một skb lớn** dù trên dây có nhiều đoạn nhỏ ⇒ số đo sai hoàn toàn | `ethtool -K enp8s0 tso off gso off gro off` trước khi đo, và **bật lại** sau khi đo |
| đo đoạn đầu mà không có nhánh đối chứng | con số đúng một cách ngẫu nhiên cũng có thể ra 1 byte; không chứng minh được gì | đo cả hai nhánh (bật/dừng) và so **tổng byte** — phải **bằng** nếu chiến lược chỉ cắt, phải **hơn đúng số byte gói giả** nếu chiến lược bơm gói giả |
| kết luận "desync có ẩn tên miền" từ chiều dài đoạn đầu | khi có `fake`, đoạn đầu là **gói giả**; đo `684` rồi tưởng hỏng, trong khi `684` mới là bằng chứng đúng | tách **SNI** trong đoạn đầu và đòi nó khác tên miền thật |
| `grep -cE '…-offload: on'` để xác nhận offload | không khớp `generic-receive-offload` ⇒ báo \"2/3\" trong khi cả 3 đều `on` | liệt kê từng mục bằng `^(tên):` |
| đếm gói bằng `grep -c 'ip6 daddr …'` | đếm **số dòng khớp**, không phải **counter gói** ⇒ ra 0 và tưởng rule không khớp | đọc `counter packets N` của đúng rule, so trước/sau |
| regex `\\bb drop\\b` (thừa khoảng trắng) | không khớp `711 drop` ⇒ báo \"0 gói bị chặn\" trong khi thật ra có 12 | viết regex từ **dòng thật** trong `nft list ruleset`, không gõ tay |
| kết luận \"IPv6 tới NextDNS hỏng\" từ `dig … 53/udp` | gói **đã đi ra** (counter 3→4) nhưng **không ai trả lời**. DoT 853 cùng địa chỉ đó thì `NOERROR` | phân biệt *rule không khớp* với *gói đi được mà bên kia im*; xem counter, đừng chỉ nhìn kết quả `dig` |
| xoá rule ufw lấy số từ `grep -n` | `grep -n` cho **SỐ DÒNG** của output, không phải **SỐ RULE** ⇒ xoá nhầm 6 rule thật (30 → 14) | lấy từ `[ N ]`: `grep -oE '^\[[ 0-9]+\]' \\| grep -oE '[0-9]+'` |
| `not {'a': '0'}` để kiểm dọn dẹp | dict có phần tử thì luôn truthy ⇒ teardown **luôn đỏ** dù đã dọn sạch | so **từng giá trị**: `{k: v for k, v in d.items() if v != '0'}` |
| dựng lab bằng netns mà không nạp lại sysctl | `ip_forward=0` reset `accept_redirects` về 1 ⇒ tầng 3 yếu đi 1 khoá, `t1-config` báo LỆCH 1 | xem §8.1c; luôn `sysctl -p` tệp hardening sau khi trả `ip_forward` |
| đo bằng `eval "$2"` mà quên `sudo` | lệnh thất bại **im lặng** ⇒ cả 8 trigger trông như đã giữ nguyên, tức kết luận sai hoàn toàn | bọc `sudo -A bash -c "$2"` và kiểm rc |
| quét cổng rồi tin `getsockopt(SO_ERROR)` | SO_ERROR **xoá** lỗi sau khi đọc và trả 0 ⇒ 13/13 cổng thành `closed` trong khi tường đang DROP | đọc errno từ `connect_ex`; phân biệt `ECONNREFUSED` (có RST) với `ETIMEDOUT`/`EHOSTUNREACH` (không phản hồi) |
| gán IP cho netns rồi mặc định là gói sẽ dùng IP đó | đi qua route mặc định nên kernel chọn nguồn khác ⇒ rule lọc theo nguồn không khớp, counter = 0 | ép bằng `ip route replace <đích>/32 dev <dev> src <ip>` |

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
| `cp` khôi phục mà quên `rm` trước | `/etc/resolv.conf` sau khi cài là symlink trỏ stub; `cp -a backup /etc/resolv.conf` đi theo symlink và **ghi đè mất stub** — tệp bị hỏng lúc nào không biết | `rm -f` đích trước, rồi mới `cp -a` |
| gỡ xong mà không trả lại policy | chỉ set `ufw default deny incoming` mà không lưu giá trị cũ ⇒ sau uninstall vẫn `deny`, dù hệ thống đã bị gỏ hết; người dùng quy nhầm cho ufw | ghi policy vào backup lúc cài, đặt lại lúc gỡ; thiếu thì báo, không đoán |
| sửa tệp mà quên sao lưu nó | `/etc/resolv.conf` bị `rm -f` + tạo symlink mà không nằm trong danh sách sao lưu ⇒ mất luôn nếu bản gốc là tệp thật | thay đổi gì thì phải có đường quay lại |
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
