# Zapret theo nền tảng, game và bộ cấu hình dùng sẵn

Bổ sung cho [`WIKI-ZAPRET1-THAM-CHIEU.md`](WIKI-ZAPRET1-THAM-CHIEU.md) — phần đó
là cờ, danh sách và chẩn đoán. Tài liệu này là **triển khai theo nền tảng** và các
bài hướng dẫn theo tình huống.

---

## 1. Router — OpenWRT và Keenetic

### OpenWRT

| Dự án | Ghi chú |
|:--|:--|
| **`zapret-openwrt`** (remittor) | Gói OpenWrt có wiki cài đặt riêng |
| **`zapret4rocket`** (IndeecFOX) | Cài một lệnh: |

```bash
curl -O https://raw.githubusercontent.com/IndeecFOX/z4r/4/z4r && sh z4r
```

Chỉ cần nhấn Enter. Script hỗ trợ **tự chọn nhanh** chiến lược từ các bộ đã
kiểm chứng: YouTube không giới hạn, voice Telegram, WhatsApp, Discord,
`ntc.party`, `meduza.io`.

### Keenetic

Cộng đồng dự án: `nfqws-keenetic` (Anonym-tsk), `Zapret-on-Keenetic` (Nikitian),
`zapret4rocket` (IndeecFOX), `zapret` (AlexFBG), cùng bài Habr `834826`.

---

## 2. Android — vì sao cần root

> ⚠️ Zapret trên điện thoại **bắt buộc cần root**, vì nó làm việc trực tiếp với
> `iptables`. Và cần có **Magisk** đã cài.

### Zapret2 (khuyến nghị)

Module Magisk/KernelSU chạy vượt DPI **một cách hệ thống**, làm việc thẳng với bộ
lọc Linux (`iptables` / **NFQUEUE**).

| Điểm | Nội dung |
|:--|:--|
| **Không phải VPN** | Traffic đi **thẳng**, không đường hầm, không máy chủ ngoài → nhanh hơn VPN, không cần đăng ký — nhưng cũng **không ẩn danh** |
| **Phạm vi** | Mọi ứng dụng trên thiết bị, **một lần** |
| **Yêu cầu** | Android **7.0+**, root (Magisk hoặc KernelSU), kernel hỗ trợ **NFQUEUE** |
| **Xung đột** | Với ứng dụng tự bắt gói: **AdGuard, NetGuard, AFWall+** → phải tắt |
| **Bonus** | Điện thoại bật Zapret2 có thể **phát Wi-Fi hotspot** → thiết bị nối vào được Internet đã vượt |

**Vì sao cần root:** quản lý netfilter/iptables và gắn handler vào traffic
**chỉ tiến trình có quyền root** làm được. Ứng dụng thường trong sandbox Android
không làm nổi.

**Kho ứng dụng:** [F-Droid repo của Zapret Apps](https://git.zapret.moe/fdroid/repo)
— có tự cập nhật và kiểm chữ ký.

### Zapret 1

| Cách | Nguồn |
|:--|:--|
| Module Magisk `zapret_module.zip` | `ImMALWARE/zapret-magisk` |
| `zapret-pocket` | `sevcator/zapret-magisk` |
| **`zaprett`** (app) | `CherretGit/zaprett-app`, wiki `mailru.pro/guide/install/app-module` |
| **ByeByeDPI** | Không cần root — chạy qua local VPN service, có giới hạn riêng |

---

## 3. `wssize` — vì sao là phương án cuối

> **Nguồn:** trả lời của tác giả zapret (nick `bolvan`) trên ntc.party, 08/2026.

**Khuyến nghị của tác giả: tốt hơn bỏ `wssize` và tìm cách vượt khác.**

### Cơ chế

`--wssize=<kích thước>[:<scale>]` thay trường **TCP window size** trong gói đi ra.
Máy chủ thấy "cửa sổ" **rất nhỏ** → buộc phải gửi câu trả lời **từng miếng nhỏ**,
chờ xác nhận sau mỗi miếng.

Nói ngắn gọn: `wssize` **nói dối máy chủ** rằng "tôi chỉ nhận được từng chút một",
khiến máy chủ chia nhỏ câu trả lời — mà khi câu trả lời bị chia nhỏ, chữ ký trong
đó không nằm trọn trong một gói.

### Ba giới hạn

| Giới hạn | Hệ quả |
|:--|:--|
| Thay đổi ở chặng **thiết lập kết nối** | Zapret **chưa biết** hostname hay giao thức |
| **Không dùng được** với `--hostlist` | — |
| **Không dùng được** với bộ lọc `l7` | Chỉ lọc được ở mức l3/l4: `ipset` và cổng |
| Ngoại lệ duy nhất | `--ipcache-hostname` |

Ngoài ra: **làm chậm mọi kết nối** trên các cổng bị lọc.

### Vì sao blockcheck đặt nó cuối log

| Chế độ | Hành vi |
|:--|:--|
| **standard** | Chỉ thử `wssize` cho **TLS 1.2**, và **chỉ khi** toàn bộ phần thử không `wssize` mà không tìm được chiến lược nào chạy được |
| **force** | Chạy lại **toàn bộ** danh sách kèm `wssize` |

Cả hai trường hợp, chúng đều ở **cuối `blockcheck.log`** — và người dùng thường
**copy bừa** mà không biết các giới hạn trên.

> **Nếu log có chiến lược chạy được không kèm `wssize`, hãy lấy cái đó.**

Trong Zapret 2: `--wssize` → `--lua-desync=wssize`, `--wsize` → `--lua-desync=wsize`.

---

## 4. Steam

> Phân tích dựa trên **bản ghi traffic** Windows ngày **27/09/2026**, dài 47 giây:
> client Steam kết nối, mở cửa hàng, mở trang game có trailer, mở mục cộng đồng.

### Bốn điều quan trọng

1. **Steam vào mạng qua server riêng của Valve** `*.steamserver.net` — và **không chỉ
   cổng 443**, mà còn TCP **27020, 27021, 27024**.
   → Profile chỉ khai cổng `80,443` sẽ **không thấy** các kết nối này.

2. **Cửa hàng, cộng đồng, ảnh, video** đến từ mạng giao hàng của bên thứ ba:
   - **Akamai**: `steampowered.com`, `steamcommunity.com`, `steamusercontent.com`
   - **Fastly**: `*.fastly.steamstatic.com`

   Qua chúng đi **gần như toàn bộ** traffic Steam trong bản ghi.

3. **Dùng hostlist, không dùng danh sách IP** — địa chỉ CDN thay đổi, và một phần
   nội dung trong bản ghi đến qua **IPv6**.

4. **Traffic của game** (UDP 27000–27250 và P2P) **profile này không phủ** — cần
   profile riêng theo cách gom IP.

### Profile tối thiểu

```bash
--name=Steam
--filter-tcp=80,443-65535
--hostlist=lists/steam.txt
--payload=tls_client_hello
--lua-desync=<chiến lược của bạn>
```

`lists/steam.txt`:

```
steampowered.com
steamcommunity.com
steamstatic.com
steamusercontent.com
steamcontent.com
steamserver.net
```

> Vì sao ghi **domain cha** thay vì từng CDN: trong hostlist, subdomain được bao gồm
> tự động.

### Hai kiểu chữ ký TLS

Cùng một ứng dụng nhưng **hai chữ viết TLS khác nhau** — nên có thể cần **hai
profile**.

---

## 5. Game khác

| Trang | Nội dung |
|:--|:--|
| `Battlefield 6` | Lỗi multiplayer `1:85008S`; sẵn file `battlefield.bat` và bản `zapret-bf` với **ALT7/ALT8** |
| `League of Legends` | Lỗi *"unknown player"* ở EUW/EUNE/PBE khi bị chặn |
| `Ubisoft` | Không chạy được Ubisoft Connect; nơi tìm giải pháp trong issue của `Flowseal/zapret-discord-youtube` |
| `Zapret2/find-game-strategy` | Cách tổng quát (mục 6) |

---

## 6. Tổng quát: chiến lược cho game

1. **Gom IP bằng TCPView.**
2. **Tạo profile game**, đưa IP đã gom vào `ipset`.
3. **Giờ** mới đổi chiến lược — lúc này việc thử mới trung thực.
4. **UDP**: traffic thời gian thực cần **profile UDP riêng** với `payload=all`.

> ⚠️ **TCPView không hiện địa chỉ đích của UDP.** Đây là lý do
> [log analyzer](ZAPRET2-WIKI-TONG-HOP.md) sinh ra: để thay cả Wireshark lẫn
> TCPView. Tạm thời mở rộng bộ lọc `wf` toàn cổng, ghi log khi game đang chạy —
> bảng connections sẽ cho ra toàn bộ địa chỉ của game.

**Lưu ý:** trang wiki có trích một preset tên `ALL TCP & UDP
hostfakesplit_multi_syndata` (BuiltinVersion 2.24) với phần đầu chuẩn bị bị lược
bỏ (`--lua-init`, cache, `--blob`).

---

## 7. Bộ cấu hình `.bat` dùng sẵn

Các trang này chủ yếu là **kho script** cho `winws.exe` — không phải hướng dẫn.

| Trang | Nội dung |
|:--|:--|
| `Zapret GUI` | Tổng hợp các `.bat`: preset của **bolvan**, **Flowseal 1.6.1/1.8.0**, **Discord Voice**, bản cho **Beeline** và **Rostelecom** |
| `Launcher zapret 2.9.1` | Preset cho launcher 2.9.1: `fake`, `multisplit`, `multidisorder` kèm hostlist cho cổng 80 và 443 |
| `YTDisBystro_v3.5` | Script `.bat` đầy đủ: **12 chiến lược desync TLS**, vượt QUIC và Discord, dừng dịch vụ **GoodbyeDPI** và zapret |
| `DiscordFix_5.1.7` | Cho **Beeline**, **Rostelecom**, **Infoline**: tham số `winws.exe`, biến thể `syndata`, `split2`, `disorder2` |
| `ToDo/Dronator 4.2` | Cấu hình cho zapret-discord-youtube 1.8.0–1.8.4: Discord, YouTube, WireGuard, cổng game |
| `ToDo/Phasmophobia` | Tham số cho UDP `5056` và `27002` |
| `ToDo/preset_discord_media_stun` | Thảo luận bol-van #1733, ví dụ `--filter-l7=discord,stun` |

### Đọc preset `.bat` để hiểu cú pháp

`Launcher zapret 2.9.1` cho ví dụ cấu trúc thật:

```bat
winws.exe
--wf-tcp=80,443
--filter-tcp=80
  --hostlist="...\auxiliary\cdn.txt"
  --hostlist="...\auxiliary\blacklist.txt"
  --hostlist="...\auxiliary\myblacklist.txt"
  --hostlist-exclude="...\auxiliary\whitelist.txt"
  --dpi-desync=fake,multisplit
```

Ba điều thấy ngay:

- **`--wf-tcp=80,443`** — bộ lọc bắt gói
- **Nhiều `--hostlist` cùng lúc** — được phép, cộng lại
- **`--hostlist` và `--hostlist-exclude` dùng chung profile** — chính là cơ chế loại
  trừ mục 6 của [`WIKI-ZAPRET1-THAM-CHIEU.md`](WIKI-ZAPRET1-THAM-CHIEU.md)

---

## 8. Changelog và cộng đồng

### Changelog

`changelog-21.0.0-dev-june-2026` — ZapretGUI từ **21.0.0.6 → 21.0.0.181**
(04–06/2026): proxy Telegram, profile, trình sửa danh sách, tăng tốc, và sửa lỗi
"mất Internet".

### Kênh và tài nguyên

| Trang | Nội dung |
|:--|:--|
| `ZapretTeam`, `Test`, `LordSlon` | Kênh Telegram chính thức, nhóm chat, bot hỗ trợ |
| `Zapret ссылки` | Link tới thảo luận `Flowseal/zapret-discord-youtube`, `ipset-ovh`, sự kiện Telegram |
| `Zapret Todo` | Danh sách việc dự án |
| `Zapret ссылки` → `ipset-ovh.txt` | Danh sách subnet OVH sẵn |

### Sự kiện: GitHub đình chỉ Flowseal (10/07/2026)

GitHub **đình chỉ** tài khoản Flowseal và repo `zapret-discord-youtube`.

Wiki có hai bài phân tích: `flowseal-zapret-discord-youtube-block-july-2026` và
`flowseal-zapret-video-script-july-2026`. Kết luận quan trọng:

- Đây là **đình chỉ**, **không phải** "Zapret hỏng"
- Có tin đồn nguyên nhân là file `.bat` giả chứa **trojan SalatStealer**
- **Zapret không phải virus**

Chi tiết các ca nhiễm khác: [`WIKI-VAN-DE-AN-TOAN.md`](WIKI-VAN-DE-AN-TOAN.md) mục 1.

---

## 9. Tải về

`download` — **năm cách** tải Zapret GUI cho Windows 10+:

1. Kênh Telegram
2. Bot
3. Bản phát hành trên **Forgejo**
4. **Dựng từ mã nguồn**

Thêm bản cho **Android** và **Linux**.

> Nhớ nguyên tắc ở [`WIKI-VAN-DE-AN-TOAN.md`](WIKI-VAN-DE-AN-TOAN.md): chỉ lấy từ
> nguồn xác minh, đối chiếu hash.