# Virus, chứng thư Nga, root Android và bảo mật tài khoản

Tài liệu từ các namespace bảo mật của <https://wiki.zapret.moe/> — 47 trang:
`virus` (7), `nuc` (10), `root` (6), `FIDO` (9), `TOTP` (2), cộng 13 trang ở gốc.

---

## 1. `virus` — Zapret **KHÔNG phải** virus (7 trang)

Trang index `virus` nói thẳng: vì sao antivirus gào thét về Zapret và WinDivert, và
**cách phân biệt với đồ giả**.

### Mối đe dọa thật: nguyên mẫu "bộ Zapret" giả

Có một lịch sử lâu dài các file `.bat` giả đặt tên giống bộ Zapret/GoodbyeDPI phổ
biến. Năm 2026 nó **tiến hoá** sang các hình thức tinh vi hơn:

| Sự cố | Nội dung |
|:--|:--|
| `flowseal-fake-youtube-salatstealer-july-2026` | Kênh YouTube `@Dey-K` giả danh *"kênh YouTube chính thức Flowseal Github"*, phát archive `FlowsealObhod1.8.1.rar` — bản giả của bộ Zapret phổ biến. Bên trong thay vì vượt chặn là **styler SalatStealer** |
| `fixit-arcane-stealer-kaspersky-august-2026` | "Fixit" quảng cáo vượt YouTube/Discord/Telegram không cần VPN: website đẹp, lời hứa *"ổn định 100%"*, nút "Tải Fixit". **Không có chương trình** — có archive, khi chạy sẽ cài **styler Arcane** (mật khẩu, cookie, hội thoại, ví) và **máy đào crypto** |
| `hidemydiscord-loader-august-2026` | `hidemydiscord.com` phát "fix Discord miễn phí" dựa trên bộ Flowseal **thật sự chạy được**. Vấn đề: cạnh lõi vượt thật có file `StartWin.exe` **6,2 MB không có trong bản gốc** |
| `discord-cdn-fix-fake-repos-june-2026` | Kiểu mới: **không phải một archive nhiễm**, mà **mạng repo GitHub giống hệt nhau** dưới tài khoản một lần, giả danh dự án open-source hợp pháp |
| `github-removes-clean-zapret-keeps-malware-august-2026` | **11/08/2026** GitHub xoá sạch dự án sạch: tổ chức `youtubediscord` (bộ Zapret GUI, fork client Telegram ZaStoGram), tài khoản `censorliber`, repo `goshkow/Zapret-Hub`, tài khoản `neiroxgod` với `zapret-ui` — **nhưng repo chứa malware dưới cùng tên lại còn nguyên** |

### Kết luận rút ra

> **Zapret không phải virus.** Antivirus gọi nó vì nó cài **driver chặn gói mạng**
> (WinDivert / NFQUEUE) và ghi vào stack mạng — hành vi **đúng** như bất kỳ công cụ
> can thiệp mạng nào, và trùng khớp với mẫu hành vi mà AV cảnh báo.
>
> Rủi ro thật **không nằm ở Zapret** mà ở chỗ bạn tải **bản .bat không rõ nguồn gốc**.

### Cách tự bảo vệ

- Chỉ lấy từ **kênh Telegram chính thức** hoặc repo đã xác minh
- Đối chiếu **hash** với bản được công bố
- Nếu bản trả về **`.exe` lạ** không có trong bản gốc → dấu hiệu nhiễm
- Nhớ: `Flowseal` bị GitHub đình chỉ 10/07/2026 (xem
  [`WIKI-ZAPRET1-THAM-CHIEU.md`](WIKI-ZAPRET1-THAM-CHIEU.md))

---

## 2. `nuc` — chứng thư Nga và khả năng tấn công MITM (10 trang)

**НУЦ** = Национальный удостоверяющий центр Минцифры — Trung tâm Chứng thực Quốc
gia của Bộ Số. Vấn đề: **gốc (root) của НУЦ trong kho tin cậy = năng lực MITM
toàn bộ HTTPS của thiết bị.**

### Bối cảnh

| Mốc | Sự kiện |
|:--|:--|
| 2025 | Biến thể "mã hoá theo GOST" của chứng thư НУЦ được cung cấp trên Gosuslugi |
| 08/2026 | Chứng thư của **TrustAsia** (Trung Quốc) bị thu hồi khỏi domain các ngân hàng Nga lớn; Sberbank, VTB, Rosselkhozbank, T-Bank và nhiều ngân hàng khác chuyển sang chứng thư НУЦ |
| **06/2026** | Chứng thư của messenger **MAX** bị thu hồi liên tiếp — khủng hoảng niềm tin TLS |

### Các trang

| Trang | Nội dung |
|:--|:--|
| `00-overview` | Chứng thư TLS của НУЦ từ đâu ra, vì sao nhà nước thúc cài gốc, và **nguy cơ cấu trúc** của bước đó |
| `nuc-root-mitm-threat-model` | Phân tích chi tiết: **những tấn công nào trở nên khả thi** nếu gốc НУЦ vào kho tin cậy, và/hoặc nếu trung tâm đó bị hack. Đây là **mô hình đe dọa**, không phải tuyên bố |
| `safe-usage` | Sơ đồ thực hành khi cổng dịch vụ/ngân hàng chạy chứng thư НУЦ nhưng bạn **không muốn** đưa toàn bộ HTTPS thiết bị dưới gốc nhà nước. Từ đơn giản đến "paranoid", kèm **đánh giá trung thực** điểm yếu từng cách |
| `check-remove` | Kiểm tra **mọi nền tảng** (Windows, macOS, Linux, Android, iOS) và trình duyệt xem có gốc НУЦ không — và **gỡ bỏ** nếu có |
| `embedded-trust` | Gốc НУЦ **không nhất thiết** phải cài tay: trình duyệt Nga có **tin cậy tích hợp sẵn từ nhà sản xuất**. Phân tích cách nó hoạt động trong **Yandex Browser** và **Atom** |
| `banks-nuc-certs-august-2026` | Sự kiện 03/08/2026 (mục trên) |
| `gost-tls` | НУЦ có **hai loại** chứng thư: thường (trên mật mã quốc tế, chỉ không được trình duyệt thế giới tin gốc) và biến thể **mã hoá GOST** |
| `mincifry-nuc-certs-danger-june-2026` | Bài phóng bút về khủng hoảng niềm tin (những gì xảy ra, kịch bản ứng phó của chính quyền tới mức **cô lập Internet Nga**) |
| `post-cert-danger-kratko-june-2026` | Bản rút ngắn cho công chúng |
| `nuc-root-browsers` | **Chromium-Gost** và **Ruthenium** — trình duyệt có sẵn gốc НУЦ, an toàn hơn cài vào OS ở chỗ nào, tệ hơn ở chỗ nào |

### ⚠️ `nuc-root-browsers` — đánh giá rủi ro cụ thể

> Trang này được lấy **trực tiếp từ wiki** vì không có file tương ứng trong repo
> nguồn.

| Dự án | Đánh giá |
|:--|:--|
| **Chromium-Gost** (PC) | Từ bản **152.0.7977.75** (06/09/2026) chứa Russian Trusted Root CA và **tin cậy cho MỌI domain**, không riêng domain Nga. Tắt bằng cờ `--skip-bundled-ca-certificates` |
| **Ruthenium** (Android) | Giới hạn gốc НУЦ trong các vùng `.ru`, `.рф`, `.su`. Nhưng các vùng đó **chứa cả ngân hàng của bạn, `mail.ru`, `yandex.ru`** — và lỗ hổng đã biết (chứng thư trên địa chỉ IP) **không được giới hạn đó che** |

**Điểm mấu chốt về Chromium-Gost:** khẳng định *"Chromium-Gost không hề thay đổi
hệ thống"* **chỉ đúng khi không dùng mã hoá GOST**. Với site dùng **GOST-TLS** cần
**CryptoPro CSP**, mà trình cài Windows của nó **mặc định thêm 5 gốc GOST** (gồm
"Minцифры России" và "НУЦ России") vào kho tin cậy hệ thống.

**Rủi ro bản dựng:** trình duyệt **thấy mọi thứ bạn làm trong đó**. Chromium-Gost
phát triển từ 2017 có sự tham gia của chuyên gia CryptoPro; Ruthenium là dự án
**tháng 8/2026** của nhóm ẩn danh, APK cài tay.

**Luận điểm chung của wiki:** trình duyệt có gốc NУЦ tích hợp **an toàn hơn** đặt
gốc vào kho hệ thống — chỉ một trình duyệt tin cậy trung tâm nhà nước, thay vì
**mọi chương trình** trên thiết bị. Nhưng bên trong trình duyệt đó gốc vẫn hoạt
động, nên **không nên** giữ thư và đời tư cá nhân trong đó.

---

## 3. `root` — root Android (6 trang)

Root Android quan trọng với Zapret vì đó là điều kiện để chạy **module Zapret 2**.

### Hai hướng tiếp cận

| Hướng | Cơ chế | Dự án |
|:--|:--|:--|
| **systemless-root** | Trong **userspace**, "trên trên" hệ thống | **Magisk** |
| **kernel-based root** | Ở mức **kernel** | Các fork **KernelSU** |

| Trang | Nội dung |
|:--|:--|
| `root` | Tổng quan: lấy root để làm gì, và **root cho module Zapret 2** |
| `Magisk` | Cách phổ biến nhất: systemless-patch ảnh khởi động, module, **Zygisk**, **che root**. Lý thuyết |
| `Magisk-install` | Cài theo tài liệu chính thức: yêu cầu, biết phải patch ảnh nào, patch `boot`/`init_boot`/`recovery`, trường hợp riêng cho thiết bị **không có boot-ramdisk** và cho **Samsung**, gỡ bỏ và giữ root qua cập nhật |
| `ReSukiSU` | Giải pháp root **qua kernel**; khác KernelSU/SukiSU/Magisk; có KPM, SUSFS, metamodule; chạy trên thiết bị nào. Lý thuyết |
| `ReSukiSU-install` | Cài theo tài liệu chính thức (trạng thái 07/2026) |
| `LSPosed` | Framework đổi hành vi hệ thống và ứng dụng Android **"trên lúc chạy"**, chặn lời gọi hàm, **không cần flash lại, không sửa APK**. LSPosed là kẻ kế thừa hiện đại, chạy trên Android mới qua Zygisk |

---

## 4. `FIDO` — khóa bảo mật và đăng nhập không mật khẩu (9 trang)

| Trang | Nội dung |
|:--|:--|
| `00-overview` | Index: khóa bảo mật phần cứng và cách đăng nhập không truyền mật khẩu |
| `fido-history` | Hệ đăng nhập bằng **chữ ký mật mã thiết bị** ra đời thế nào, giải bài toán nào, và **vì sao các phần của nó có tên riêng** |
| `fido-protocols` | **Đường đi của một request**: site → trình duyệt → OS → thiết bị → ngược lại server. Phân tích **chống giả mạo trang**, khác biệt các thế hệ FIDO, cách lưu thông tin đăng nhập |
| `u2f` | Chuẩn khối đầu tiên: dùng khóa làm **yếu tố thứ hai** sau mật khẩu; bộ đếm chữ ký; tương thích với thế hệ sau |
| `uaf` | Chuẩn thứ hai của họ sớm: đăng nhập không mật khẩu bằng **cử chỉ cục bộ**, mã số hoặc sinh trắc trên di động. Kiến trúc, lý do lan truyền hạn chế |
| `webauthn` | **WebAuthn** — web-interface để trang tạo cặp khoá riêng và kiểm chữ ký. "Nửa web" của bộ tiêu chuẩn hiện đại |
| `ctap` | Giao thức trao đổi giữa trình duyệt/OS và bộ xác thực: lệnh đăng ký và đăng nhập, định dạng message |
| `passkeys` | **Passkey** thay mật khẩu bằng cặp khoá mật mã: site chỉ giữ **khoá công khai**, khoá riêng ở lại thiết bị. Đồng bộ, ràng buộc một thiết bị, so với mã dùng một lần, tấn công từ xa, đăng nhập bằng điện thoại |
| `hardware-security-keys` | Khóa phần cứng chống phishing thế nào; thiết bị **mã nguồn mở** khác gì bản đóng; cách chọn khóa. Kèm chế độ phụ, giới hạn bộ nhớ, cập nhật |

---

## 5. `TOTP` — mã một lần (2 trang)

`TOTP` (*Time-based One-Time Password*) — mã một lần do ứng dụng trên điện thoại sinh.

`aegis-vs-stratum` so sánh hai ứng dụng lưu bí mật để tính mã đó: định dạng hỗ trợ,
mã hoá, sao lưu, và làm việc với các dịch vụ Nga (Yandex).

---

## 6. `subscriptions` — xem ở tài liệu proxy

Xem [`WIKI-PROXY-VPN-CONG-CU.md`](WIKI-PROXY-VPN-CONG-CU.md) mục 10.

---

## 7. Các trang ở gốc wiki (13 trang)

### ⚠️ `VLESS-SOCKS5-vulnerability` và `VLESS-localhost-protection-guide`

> **Lỗ hổng bảo mật đáng biết — liên quan tới máy của bạn.**

Tất cả client **VLESS / xray / sing-box** phổ biến đều tạo **SOCKS5 proxy trên
localhost KHÔNG có xác thực**.

**Hậu quả:** bất kỳ ứng dụng gián điệp nào trên thiết bị có thể **kết nối thẳng
vào proxy đó**, **bỏ qua** cả `VpnService` lẫn phân tách theo ứng dụng (split
tunneling), gửi request qua proxy và **biết IP thoát của máy chủ VPN**.

Trang thứ hai là **hướng dẫn bảo vệ**.

### `tunnel-detection-fix-split-ip`

Cách phát hiện đường hầm và cách sửa bằng kỹ thuật split IP.

### `adblock-breaks-sites`

Tiện ích chặn quảng cáo **cũ hoặc bị bỏ hoang** (thường là **AdBlock**, không
phải **uBlock Origin**) có thể làm **hỏng tải trang**, video YouTube, ChatGPT, VK —
và thậm chí **đổi công cụ tìm kiếm Google thành Yandex**. **Antivirus không tìm ra
gì**, và người dùng đổ tội virus hoặc cách vượt.

### `cloudflare-quick-tunnel`

```bash
cloudflared tunnel --url http://localhost:3000
```

→ địa chỉ công khai ngẫu nhiên kiểu
`https://ba-tieng-anh-ctu.trycloudflare.com`, trỏ thẳng vào dịch vụ đang chạy
trên máy bạn. **Không cần** IP công cộng, **không cần** mở port, **không cần**
domain riêng.

### `Privacy Google`

Ghi chú về quyền riêng tư khi dùng Google.

### `Localhost-tracking-Meta-Yandex-SOCKS5`

Theo dõi localhost qua SOCKS5, Meta, Yandex.

### `SMS`

Ghi chú ngắn về SMS.

### `ipset-discord`

Ghi chú ngắn về ipset cho Discord.

### `sandbox`

Ghi chú rất ngắn (645 byte) — trang chỗ trống.

### `yabloko-boycotts-protest-2026`

Bài phóng bút gộp ba sự kiện hè 2026 thường bị bàn riêng lẻ: **rút "Яблоко" khỏi
bầu cử**, **boycott messenger MAX**, và phản đối phim "Последний богатырь.
Колобок". Chúng là **một câu chuyện** — sự bất đồng đi có hình thức mà không điều
khoản nào trừng phạt được.

### `banks-malware-scan-2027`

Ngày **26/06/2026** ký **Luật Liên bang Nhật Bản #210-ФЗ** (báo chí gọi là
*"antifraud-2"*), từ **01/03/2027** buộc **ngân hàng từ chối chuyển tiền** nếu có
thông tin về việc **phần mềm độc hại (ВПО) tác động tới thiết bị khách hàng**.

Trang này: nguyên văn các điều khoản, ứng dụng ngân hàng bị ảnh hưởng thế nào.

---

## 8. Ba việc nên làm sau khi đọc

1. **Kiểm tra gốc НУЦ** trên mọi thiết bị — `nuc/check-remove`
2. **Chỉ dùng bản Zapret từ nguồn xác minh** — so sánh hash, đừng lấy `.bat` lạ
   (mục 1)
3. **Bảo vệ SOCKS5 localhost** nếu bạn dùng VLESS/xray/sing-box — mục 7