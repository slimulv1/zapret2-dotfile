# Proxy, VPN và giao thức — công cụ vượt chặn phía máy chủ

Tài liệu từ các namespace công cụ của <https://wiki.zapret.moe/> — 97 trang:
`xray` (12), `protocols` (8), `Clash` (10), `sing-box` (6), `Hysteria` (12),
`mtproxy` (9), `tproxy` (5), `amnezia-2-0` + `amnezia-3-0` (6), `VLESS` (2),
`subscriptions` (2), `premium` (5).

> **Cách đọc tài liệu này.** Wiki làm việc tốt ở mức **tóm tắt chính thức của tác
> giả** — mỗi trang đều có khối *"О чём заметka"* mô tả đúng nội dung trang đó.
> Tài liệu này dựng trên các tóm tắt đó. Với `xray` và `protocols`, wiki còn có
> phân tích **từng byte theo mã nguồn** (`Xray-core v26.7.28`, 08/2026) — những
> phần đó không được gói ở đây, tham khảo trực tiếp khi cần chi tiết.

---

## 1. Ba tầng: giao thức, vận tải, giấu mờ

Wiki phân biệt ba tầng rõ ràng, và phần lớn nhầm lẫn đến từ chỗ này:

| Tầng | Trả lời câu hỏi | Ví dụ |
|:--|:--|:--|
| **Giao thức** (protocol) | *Trao đổi dữ liệu **gì** qua nhau?* | VLESS, Shadowsocks, Trojan, VMess, TUIC, AnyTLS |
| **Vận tải** (transport) | *Đưa gói đó đi **bằng đường nào**?* | TCP, WebSocket, gRPC, XHTTP, HTTP/2, QUIC |
| **Giấu mờ** (masking) | *Làm cho nó **trông giống cái gì**?* | TLS thật, REALITY, ShadowTLS |

**XHTTP, ví dụ, là vận tải — nó trực giao với giao thức VLESS và lớp REALITY.**
Có thể ghép bất kỳ tổ hợp nào.

---

## 2. `xray` — Project X / Xray-core (12 trang)

> Phần lớn máy chủ vượt chặn ngày nay chạy **VLESS**.

### Bản đồ 5 lớp của một link `vless://`

> Trang `vless-stack-map` giải quyết đúng thứ gây sai nhiều nhất: năm tham số
> (`type`, `security`, `flow`, `encryption` và bản thân giao thức) điều khiển
> **năm lớp khác nhau**. Đây là nguồn của phần lớn lỗi cấu hình: *"bật Vision rồi mà
> không chạy"*, *"đã có mã hoá thì cần REALITY làm gì"*, *"sao splice không bật"*.

### Project X là gì

Nhánh **fork của V2Ray**, tác giả **RPRX**. Mang các công nghệ
**XTLS-Vision**, **REALITY**, **XHTTP**. Về cơ bản thay thế `v2fly/v2ray-core`.

`v2fly-vs-xray` so sánh hai lõi: chung tổ tiên từ năm 2020, phân kỳ về giao thức
(XTLS/REALITY/XHTTP **độc quyền** của Xray; QUIC và Hysteria2 thuộc về
v2fly/v2ray-core), config, phụ thuộc và mô hình quản lý.

`authors-v2ray-xray` xử lý câu hỏi thường gặp *"V2Ray/Xray phải do một cô gái
tạo ra không?"* — bút danh **Victoria Raymond** (V2Ray) và **RPRX** (Xray-core) là
hai người khác nhau; tác giả V2Ray biến mất năm 2019.

### VLESS

Giao thức vận tải proxy của Xray-core, trên đó phần lớn máy chủ vượt chặn được
dựng. Trang `vless` phân tích **mức byte**: định dạng header, trường `flow` và
XTLS-Vision, `fallbacks`, XUDP, và mã hoá hậu kỳ tích hợp trong Xray-core.

### REALITY

Thay thế TLS trong Xray-core, cho phép máy chủ proxy **ngụy trang thành một website
bên thứ ba thật** mà **không cần domain hay chứng thư riêng**.

Trang `reality` phân tích **theo mã nguồn** (`XTLS/REALITY`, fork `crypto/tls`):

- chuyện gì xảy ra ở mức bắt tay
- cơ chế xác thực mật mã
- **vì sao active probing không phân biệt được** máy chủ REALITY với website thật
- dấu hiệu trong `SessionId`
- X25519

### XTLS / Vision

`xtls-vision` trả lời câu hỏi hay gặp: *"XTLS, Vision, REALITY là một hay khác
nhau?"* — **khác nhau, ở các tầng khác nhau**, và thường cùng hoạt động.

Cốt lõi: **padding** đối với **TLS-in-TLS**, và `splice`. Lịch sử bốn thế hệ, và
**ranh giới của việc giấu mờ**.

### XHTTP (SplitHTTP)

Vận tải Xray bọc traffic proxy vào **HTTP request thường** để đi **qua CDN** như
Cloudflare. Ba chế độ:

| Chế độ | Đặc điểm |
|:--|:--|
| `packet-up` | — |
| `stream-up` | — |
| `stream-one` | — |

Kèm XMUX và tham số config. Phân tích theo mã nguồn
`transport/internet/splithttp/` — tên nội bộ gói **vẫn là `splithttp`**, tên
công khai là XHTTP.

### VLESS Encryption (`mlkem768x25519plus`)

> Tháng 9/2025, lớp mã hoá **bên trong chính giao thức VLESS**, gỡ bỏ phụ thuộc
> lịch sử vào TLS bên ngoài.

- Lệnh: `xray vlessenc`
- Mật mã: **hậu kỷ** (`mlkem768x25519plus`)
- Dùng khi đi qua **CDN**
- ⚠️ **Câu hỏi thực hành quan trọng: nó có vượt được chặn ở Nga và Trung Quốc
  không? — Câu trả lời ngắn: không trực tiếp.**

### Định tuyến và client

`routing` phân tích module routing của Xray-core — cơ chế **quyết định cho từng
kết nối** sẽ đi qua outbound nào: thẳng, qua proxy, hay chặn. Đây là thứ **thực
tế cho phép mở site Nga đi ngoài đường hầm** còn site bị chặn thì qua máy chủ.

- `domainStrategy`, `geosite`, `geoip`
- Cân bằng phân tải (balancer)

`clients-and-routing` là hướng dẫn thực hành cho người chưa có kinh nghiệm:
client **HAPP** trên điện thoại, nhập khoá, quy tắc của `routing.help`, định tuyến
tách (`.ru` đi thẳng).

### DPI và VLESS+REALITY

`VLESS/dpi-tls-june-2026` là phần **quan trọng nhất** của cả nhóm: nó phân tích
**cách DPI hiện đại phát hiện** chuỗi VLESS+REALITY, dựa trên **sơ đồ hạn chế
tháng 6/2026**.

> Wiki tự ghi: *"Vật liệu mang tính nghiên cứu và giáo dục. Nhiệm vụ là hiểu theo
> những dấu hiệu nào DPI hiện đại phân biệt công cụ vượt với traffic thường, và
> vì sao không còn một công tắc "phép màu" nào giải quyết được nữa."*

---

## 3. `protocols` — bản đồ giao thức (8 trang)

| Giao thức | Ý tưởng cốt lõi | Vấn đề nó giải / trạng thái |
|:--|:--|:--|
| **Shadowsocks** | Tổ tiên của proxy vượt kiểm duyệt hiện đại. Bản **SIP022 (2022)** thay thế cipher cũ không an toàn | Cipher cũ không an toàn; hôm nay chỉ dùng ở dạng hiện hành |
| **VMess** | Giao thức chính của V2Ray; chuẩn của thập niên 2010 | Hầu như **bị VLESS thay thế**. Trường `alterId` bí ẩn; đã tìm ra nhiều lỗ hổng — năm 2026 có nên dùng không |
| **Trojan** | Tối giản trên **TLS thật**, quanh **một ý**: với ai **không biết mật khẩu**, máy chủ phải cư xử như website bình thường | Cơ chế **fallback**; Trojan-Go bổ sung gì; điểm yếu của sơ đồ |
| **ShadowTLS** | Bọc proxy tuỳ ý (thường Shadowsocks) sau **bắt tay TLS thật** với site bên ngoài. Biến thể **Restls** | V1–V3 khác nhau; **năm 2025 v3 bị coi là có thể phát hiện** — hệ quả thực tế |
| **NaiveProxy** | Dựng trên **network stack của Chromium**: thay vì bịa thêm một kiểu giấu mờ, nó **lặp lại hành vi** của trình duyệt thật | Sơ đồ frontend-server; **padding gói đầu tiên**; **không phải lõi nào cũng hỗ trợ** |
| **AnyTLS** | Tương đối mới (2025), thiết kế quanh **một vấn đề cụ thể**: chữ viết đặc trưng sinh ra khi **giấu một kết nối đã mã hoá bên trong một kết nối đã mã hoá** (TLS-in-TLS) | Chống lại bằng **padding** và **pool phiên**; khác Vision ở đâu; ranh giới |
| **TUIC** | Proxy trên QUIC, thiết kế quanh **thiết lập nhanh (0-RTT)** và làm việc **trung thực với UDP** | So với Hysteria 2; khác biệt v4/v5; các chế độ UDP relay; trạng thái dự án |

---

## 4. `Clash` và `mihomo` (10 trang)

### Chuyện gì đã xảy ra

Dự án Clash gốc **biến mất tháng 11/2023**. Chỗ của nó do nhánh fork
**mihomo** (tên cũ **Clash.Meta**) của nhóm MetaCubeX chiếm — **đây là lõi sống
duy nhất của cả hệ sinh thái**. Trên nó chạy Clash Verge Rev, FlClash, Mihomo
Party, ClashMetaForAndroid và các gói cho router.

### Trang theo thứ tự đọc

| Trang | Nội dung |
|:--|:--|
| `01-clash-core` | Lõi Clash là **chương trình console định tuyến traffic**; khác GUI client thế nào; cấu trúc config; Clash API; Clash Premium (đóng) khác bản mở thế nào; chuyện xảy ra 11/2023 |
| `03-first-run` | Hướng dẫn từng bước cho người mở client lần đầu mà **không muốn đụng YAML**. Hệ thống proxy khác chế độ **TUN** ra sao; cách kiểm tra đã thật sự chạy chưa |
| `04-rules` | Khối `rules`: đọc quy tắc thế nào; ép site/app/thiết bị đi đúng đường; lấy danh sách sẵn ở đâu; **làm sao biết quy tắc nào đã khớp** |
| `05-troubleshooting` | Từ "mất Internet hẳn" tới "mọi thứ chạy trừ một game" — và **phương pháp** tìm ra |
| `06-features-protocols` | Khả năng thật của mihomo: giao thức hỗ trợ (client lẫn server), giấu mờ thế nào, TUN, hệ thống DNS, sniffer, bộ rule |
| `07-clients` | Bản đồ vỏ GUI: dự án nào còn sống (07/2026), cái nào biến mất 11/2023; vì sao phân biệt "cập nhật app" với "cập nhật lõi" lại quan trọng |
| `08-vs-sing-box` | So `mihomo` với `sing-box` và `Xray-core`, và với giải pháp chuyên dụng như Hysteria |
| `09-glossary` | **node, group, provider, TUN, fake-ip, sniffer, multiplex** — thuật ngữ trong client, YAML và hướng dẫn của bán hàng |

### So sánh ba lõi phổ quát

`08-vs-sing-box` so sánh theo các trục **thực sự ảnh hưởng tới lựa chọn**: định
dạng config · vai trò trong mạng · định tuyến · hệ sinh thái client · phía máy
chủ.

---

## 5. `sing-box` (6 trang)

Trang gốc là `sing-box` — nền tảng proxy phổ quát — và nhánh fork
**sing-box-extended** của `shtorm-7`.

| Trang | Nội dung |
|:--|:--|
| `sing-box-extended` | Fork bổ sung **hàng chục** giao thức và tính năng còn thiếu: từ Cloudflare WARP, MTProxy tới bộ giới hạn traffic và **bảng quản trị web** |
| `architecture` | Kiến trúc mã nguồn: lõi, registry pattern, cách hiện thực giao thức, limiter, DNS, hệ thống quản lý **"manager + node + panel"** |
| `protocols-origin` | sing-box nhúng giao thức của bên khác bằng file tĩnh, hay tự viết? So trực tiếp với Xray-core |
| `wire-protocol-explained` | **Từ đầu, không đơn giản hoá**: wire format là gì; vì sao hai chương trình do hai người khác nhau viết, **không hề thấy mã nhau**, vẫn hiểu nhau; văn hoá internet-standard tạo ra điều đó; và **vì sao viết lại thay vì sao chép mã người khác** |
| `hardcoded-defaults` | Tra cứu giá trị **hardcode** trong mã nguồn: cổng mặc định, timeout, khoảng thời gian, **địa chỉ ma thuật**, số hiệu giao thức |

---

## 6. `Hysteria 2` (12 trang)

**Hysteria 2** — proxy trên **QUIC (UDP)**, chế tối cho mạng **mất gói** và vượt
kiểm duyệt nhờ giấu dưới dạng **HTTP/3 thông thường**.

| Trang | Nội dung |
|:--|:--|
| `install-server` | Cài phần máy chủ trên Linux-VPS: script bash chính thức + systemd, cài nhị phân tay, Docker |
| `config-server` | Viết `config.yaml` máy chủ: lấy chứng thư TLS (ACME hoặc của riêng), mật khẩu xác thực, **masquerade** giả dạng website, và chạy |
| `config-client` | Cấu hình client: địa chỉ máy chủ, mật khẩu, SOCKS5/HTTP cục bộ, và **chế độ TUN** (VPN trọn vẹn) |
| `obfs-port-hopping` | **Hai thao tác độc lập** khi ISP gây rắc rối: **obfs** (mã hoá gói đến mức **không còn trông như QUIC/HTTP-3**) và **port hopping** (đổi cổng liên tục để né chặn/trottle một cổng UDP cụ thể) |
| `port-hopping-manual` | Làm port hopping **tay** bằng rule firewall (iptables/nftables **DNAT**) khi dải trong `listen` không phù hợp |
| `realms-nat` | Dựng máy chủ **không cần IP công cộng, không cần mở port** — từ nhà, sau **CGNAT**, từ modem di động — bằng **Realms** (P2P qua **UDP hole punching**) |
| `tproxy` | **TPROXY** trên client Linux: bọc **toàn bộ** TCP/UDP của thiết bị hoặc mạng nội bộ qua Hysteria mà **không phải cấu hình proxy trong từng ứng dụng**. Chỉ Linux |
| `acl-outbounds` | Rule **ACL** phía máy chủ: chặn địa chỉ, chia traffic theo outbound, chặn kết nối |
| `bandwidth-brutal` | Vì sao có trường `bandwidth`, thuật toán kiểm soát tắc nghẽn **Brutal** hoạt động ra sao, và **đặt tốc độ thế nào** để không làm tệ hơn |
| `traffic-stats-api` | Bật **HTTP-API thống kê**: traffic theo người dùng, ai đang online, **kick** client. Hữu ích khi chia sẻ máy chủ |
| `troubleshooting` | Giải mã lỗi thường gặp ở client và máy chủ |

---

## 7. `mtproxy` — Telegram (9 trang)

### Vấn đề kiến trúc then chốt

Trang `ja4-sni-client-side` nêu **sự thật kiến trúc** quyết định toàn bộ cuộc đấu với
phát hiện MTProto mới:

> **Chữ viết TLS (JA4) và tên miền (SNI) do *client* Telegram đặt, KHÔNG phải máy
> chủ proxy.** Vì vậy các cách vượt "thuần" (đổi JA4, xoay vòng SNI) chỉ hoạt
> động **ở phía client, trước nhà kiểm duyệt**.

Hệ quả: **máy chủ proxy không sửa được** thứ mà DPI nhìn thấy. Đó là lý do
`mtproxy.zig`, `mtproto.zig` bị giới hạn, và tại sao các fork client mới xuất hiện.

### Các trang

| Trang | Nội dung |
|:--|:--|
| `mtproxy` | Tổng quan: MTProxy (proxy chạy giao thức MTProto của Telegram), giấu FakeTLS, phát hiện từ phía ТСПУ, cách sống sót — cả máy chủ lẫn client. Cộng thêm vận tải thay thế **WSS** |
| `mtproto-zig` | **Giải thích đơn giản**: MTProxy là gì, FakeTLS là gì, DPI/ТСПУ bắt nó bằng dấu hiệu nào, và `mtproto.zig` chống lại thế nào. Có cấu hình sẵn và checklist |
| `mtproto-zig-setup` | Runbook thực hành, **hiểu từng lớp phòng vệ** — tính đến: vân tay client đã **cũ** (`telegramdesktop#30733`), phát hiện `expected_64_got_0`, thao tác **TCPMSS** |
| `faketls-relay-diagnosis` | Khoá `tg://proxy?...` chạy trong Telegram chính thức nhưng **không** chạy ở client khác (bản tự build, fork, app thử nghiệm). Cách xác định trong vài phút, **không cần build lại**, xác định thủ phạm là relay hay client |
| `tdlib-obf-client-side-stealth` | `tdlib-obf` — fork **TDLib** (thư viện chính thức viết client Telegram) giấu MTProto dưới dạng **HTTPS trình duyệt thường** |
| `tsrman-tg-android-faketls` | `tsrman/tg` — fork app Telegram chính thức cho Android (mã nguồn DrKLO), đổi **JA4** của kết nối FakeTLS **ngay trong client** và thêm **jitter** giữa các kết nối. Đây là bản GUI hiện thực luận điểm ở `ja4-sni-client-side` |
| `telegram-wss-transport` | Vận tải xuất hiện 2026: luồng MTProto thường **đặt vào WebSocket trên TLS** rồi gửi tới endpoint web Telegram kiểu `kws2.web.telegram.org/apiws` — **cùng endpoint** mà Telegram Web trên trình duyệt dùng |
| `telegram-wss-limits` | Danh sách dài điều kiện: **không phải datacenter nào cũng chạy**; **sticker và reaction có thể không tải**; **cuộc gọi không được proxy**; đường dự phòng miễn phí chạm trần Cloudflare |

---

## 8. `tproxy` — WEB-proxy của Telegram (5 trang)

**Tháng 8/2026** Telegram có **loại proxy thứ tư**: **WEB-proxy (tproxy)**.

> Khác biệt cốt lõi: **ứng dụng ngừng tự ra mạng** và nhờ **trình duyệt tích hợp sẵn
> trong nó** thực hiện, truy cập tới **một website hoàn toàn bình thường**.

| Trang | Nội dung |
|:--|:--|
| `tproxy` | Là gì, vì sao cần — giải thích đơn giản |
| `tproxy-protocol` | Phân tích kỹ thuật giao thức **WEB proxy protocol v1** |
| `tproxy-server-setup` | Triển khai phần máy chủ `tproxy-server` |
| `tproxy-in-bot` | Cài trong bot |
| `tproxy-blocking` | Câu hỏi riêng: **có chặn được loại proxy này không**, và bằng cách nào |

---

## 9. `AmneziaWG` (6 trang)

**AmneziaWG (AWG)** — WireGuard đã **obfuscate**, của nhóm Amnezia.

| Thế hệ | Nội dung |
|:--|:--|
| **2.0** | `amnezia-2-0/reference` — tra cứu thế hệ 2.0 |
| **3.0** | Phát hành **24/07/2026**. Khác biệt chính: **mã hoá header gói tin** |
| **3.1** | Dòng 3.1 trong thế hệ 3, phát hành **12/08/2026** |

| Trang | Nội dung |
|:--|:--|
| `amnezia-3-0/reference` | Thật sự thêm gì ở 3.0; khác 2.0 thế nào; **ai được dùng**; các tuyên bố lan truyền trên mạng **không được xác nhận** |
| `amnezia-3-0/internals` | **Phân tích từng byte theo mã nguồn**: gói được lắp ra thế nào, bảo vệ header mã hoá **cái gì**, nonce một lần lấy ở đâu, bên nhận **nhận ra loại message mà không giải mã trọn**, và **dấu vết protocol vẫn để lại** trên mạng |
| `amnezia-3-0/client-5-0-0-5` | Relaunch app AmneziaVPN 5.0.0.5 (26/07/2026): thêm gì, **gỡ giao thức mà không thông báo**, hồi quy lộ ra trong ngày đầu, có nên cập nhật lúc này không |

---

## 10. `subscriptions` — cách bán VPN đặt ràng (2 trang)

`hwid-client-lock` phân tích hai thực hành hay thấy ở nơi bán:

1. **Gắn gói đăng ký vào định danh thiết bị (HWID)**
2. **Giới hạn danh sách client được phép**

Nội dung: cơ chế kỹ thuật, và **vì sao lõi proxy** (mihomo, sing-box, Xray-core)
**không tự hỗ trợ** các ràng buộc này.

Điểm đáng chú ý khi đối chiếu với `premium`: **Zapret VPN cố tình làm ngược lại** —
khoá được cấp dưới dạng **chuỗi `vless://…` mở**, **không gắn thiết bị**, chạy
được ở mọi client.

---

## 11. `premium` — dịch vụ trả phí (5 trang)

| Trang | Nội dung |
|:--|:--|
| `premium` | Khoá cấp bằng **chuỗi `vless://…` mở**, **không gắn thiết bị**, chạy ở Happ, v2rayN, Clash Verge Rev, sing-box, và **firmware router** |
| `zapret-vpn-bot` | Dịch vụ **Zapret VPN** của nhóm ZapretKVN qua bot `@zapretvpns_bot`: giao thức nào có sẵn, **gói đăng ký Mihomo** và config trực tiếp, bên trong file YAML phát ra, và **vì sao không gắn thiết bị lẫn client cụ thể** |
| `about` · `discord` · `zapret_premium` | Giới thiệu và hạng mục |

---

## 12. `VLESS` (2 trang)

| Trang | Nội dung |
|:--|:--|
| `VLESS` (index) | Ghi chú về cuộc đối đầu giữa giao thức VLESS và hệ thống DPI |
| `dpi-tls-june-2026` | Phân tích **cách DPI hiện đại phân biệt** VLESS+REALITY |

Cùng họ nhau: `xray/xray` là bên **giải pháp**, `VLESS/dpi-tls-june-2026` là bên
**đối phương**. Bài thứ hai nằm trong namespace `VLESS` chứ không nằm trong `xray`,
và là **một trong những trang quan trọng nhất của toàn bộ wiki**.

---

## 13. Index

| Namespace | Số trang | Chủ đề |
|:--|:--:|:--|
| `xray` | 12 | Project X / Xray-core, VLESS, REALITY, XTLS-Vision, XHTTP, VLESS Encryption, định tuyến |
| `Hysteria` | 12 | Hysteria 2 trên QUIC: cài đặt, config, obfs, port hopping, Realms, TPROXY, ACL, thống kê |
| `Clash` | 10 | Clash → mihomo, client, rules, chẩn đoán, thuật ngữ |
| `mtproxy` | 9 | MTProxy, FakeTLS, JA4 phía client, WSS |
| `protocols` | 8 | Shadowsocks, VMess, Trojan, ShadowTLS, NaiveProxy, AnyTLS, TUIC |
| `sing-box` | 6 | Kiến trúc, wire protocol, hardcoded defaults |
| `amnezia-2-0` + `amnezia-3-0` | 6 | WireGuard obfuscate, thế hệ 2.0/3.0/3.1 |
| `tproxy` | 5 | WEB-proxy Telegram (mới, 08/2026) |
| `premium` | 5 | Zapret VPN, gói `vless://` không gắn thiết bị |
| `VLESS` | 2 | DPI phát hiện VLESS+REALITY |
| `subscriptions` | 2 | HWID lock, hạn chế client |