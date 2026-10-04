# DPI và ТСПУ — nền tảng và diễn biến 2026

Tài liệu từ namespace `DPI/` của <https://wiki.zapret.moe/> — 30 trang, ~1 MB.
Đây là phần **lý thuyết nền**: DPI phân tích ra sao, ТСПУ (Технические средства
противодействия угрозам) là gì, và chuyện gì đã xảy ra trong năm 2026.

> **Trích dẫn quan trọng về mức độ tin cậy.** Wiki tự ghi rõ: các thông tin trong
> mục này là **quan sát của cộng đồng** ([ntc.party](https://ntc.party/)) và
> **reverse engineering**, *không phải* đặc tả chính thức của ТСПУ. Các con số cụ
> thể (5 gói, 83 byte, 16 KB, 1–5 ms…) nên đọc là **quy mô và ước lượng của tác
> giả**, không phải hằng số hệ thống. Hiện thực thật **khác nhau theo nhà mạng**
> và **thay đổi theo thời gian**.

---

## 1. Phễu kiểm tra — từ SYN đến ML

> Nguồn: bài của **Aleksandr Murzin** (@cyberscoper) trên Habr,
> *«Как работает DPI: разбор по слоям»*.

**Điểm cốt lõi: DPI KHÔNG ra phán quyết từ một gói tin.** Nó tích luỹ dữ liệu và
**loại dần ở mỗi tầng**: kiểm tra rẻ trước, ML đắt điểm cuối và chỉ cho những cái
còn sống sót.

```text
                    traffic
                      │
 gói 1–5      ┌──────▼──────┐  TTL, tuỳ chọn TCP (MSS/WS/SACK/TS) → dấu vân tay OS
 (TCP/IP)      └──────┬──────┘
                      │
 byte 0–5      ┌──────▼──────┐  marker giao thức: 16 03 01… / SSH-2.0- / …
 (chữ ký)      └──────┬──────┘
                      │
 byte 6–300    ┌──────▼──────┐  ClientHello → JA3 / JA4 (vân tay client)
 (TLS hello)   └──────┬──────┘
                      │
 byte          ┌──────▼──────┐  chứng thư*: CT-log, ASN, CN/SAN ↔ SNI
 300–3000      └──────┬──────┘  (* TLS 1.3: chứng thư mã hoá →
                      │            thụ động chỉ còn SNI và ASN)
 byte          ┌──────▼──────┐  phân tích meta luồng: kích thước, nhịp độ,
 3000–16000   └──────┬──────┘  tỉ lệ in/out, thời lượng
                      │
 sau 16 KB     ┌──────▼──────┐  phân loại hành vi bằng ML
               └──────┬──────┘
                     │
              verdict → cho qua / RST / drop / throttle
```

**Càng sâu trong phễu thì kiểm tra càng đắt và càng khó lừa.** Các thao tác vượt
đánh nhau để **bị loại sớm nhất** — trông "nhạt nhàm" ngay ở các tầng đầu.

### Tầng 0 — TCP/IP, trước cả khi tới TLS

**TTL — dấu vân tay OS và công cụ phát hiện gói giả.**

| OS | TTL khởi đầu |
|:--|:--|
| Windows | 128 |
| Linux | 64 |
| macOS / iOS | 64 |

Mỗi chặng trung gian giảm 1. `TTL 63` → đã qua một chặng; `TTL 62` → hai chặng.

Hai hệ quả:

1. Có thể đoán thô OS của client.
2. **Quan trọng cho vượt chặn:** theo TTL mà bắt được **gói giả** của Zapret /
   GoodbyeDPI — chúng cố tình gửi gói giả với **TTL nhỏ** để nó tới được DPI nhưng
   "chết" dở đường tới máy chủ. **Nếu DPI biết đối chiếu TTL, nó phân biệt được
   gói giả với gói thật.**

> Đây chính là mối liên hệ trực tiếp giữa "phễu" của DPI với thế giới Zapret.

**Tuỳ chọn TCP — vân tay thụ động (p0f).** Tập và **thứ tự** các tuỳ chọn TCP
trong gói SYN — `MSS`, `Window Scale`, `SACK`, `Timestamps` — khác nhau giữa các OS
và phiên bản. Chỉ từ một gói SYN đã nói được "giống Windows 11" hay "giống Linux".

> *Ước lượng của tác giả (có điều kiện):* "Năm gói đầu tiên của kết nối đi qua mà
> không can thiệp chủ động" — DPI trước hết **gom ngữ cảnh**. Và: "nếu gói nội
> dung đầu tiên sau bắt tay ngắn hơn **83 byte** thì đáng ngờ". Các con số này minh
> hoạ logic, không phải hằng số đã xác nhận.

### Tầng 1 — Marker giao thức, vài byte dữ liệu đầu

| Giao thức | Marker đầu |
|:--|:--|
| **TLS ClientHello** | `16 03 01 xx xx  01 00 xx xx xx  03 03 …` |
| **SSH** | chuỗi ASCII `SSH-2.0-…` |
| **OpenVPN** | header đặc trưng |
| **WireGuard** | header UDP đặc trưng (loại message) |
| **Shadowsocks** (không obfuscate) | **byte ngẫu nhiên thống kê** — *vắng mặt chính là đặc trưng* |

Giải thích marker TLS: `16` = Content Type Handshake · `03 01` = phiên bản
**tầng record** (legacy, luôn là "TLS 1.0" để tương thích) · `01` = Handshake Type
ClientHello · `03 03` = `legacy_version`.

> ⚠️ **Đính chính của wiki so với nguồn:** bản gốc nói `03 03` là "TLS 1.3 bên
> trong ClientHello" — **không chính xác**. `0x0303` là `legacy_version` (hợp lệ
> về mặt kỹ thuật là **TLS 1.2**), đặt ở đó để tương thích. Phiên bản TLS 1.3 thật
> được công bố **không phải ở đây** mà trong extension `supported_versions`
> (`0x0304`).

Shadowsocks đi qua tầng này **ngược lại**: không có marker nào, luồng trông như
nhiễu entropy. Giữa biển web nơi gần như mọi thứ đều là TLS với đầu nhận biết
được, "byte hoàn toàn ngẫu nhiên ngay từ gói đầu" **bản thân nó là bất thường** —
và chính theo dấu hiệu này nhiều giao thức obfuscate bị bắt.

### Tầng 2 — JA3 / JA4, vân tay client từ ClientHello

```text
JA3 = MD5(
  SSLVersion,
  Ciphers,            # danh sách cipher, KHÔNG giá trị GREASE
  Extensions,         # danh sách extension, KHÔNG giá trị GREASE
  EllipticCurves,
  EllipticCurvePointFormats
)
```

**JA4** (FoxIO, 2023) mới hơn và bền hơn: ít nhạy với việc đảo thứ tự extension
(nó **sắp xếp** chúng), tách phần client và phần server, cho vân tay ổn định hơn.

Ở tầng này DPI nói "đây là Chrome 13x" hoặc "đây là client Go trần". Cũng ở đây
nằm bẫy của chiến lược `fingerprint: chrome` dùng đại trà.

> **Nghịch lý GREASE trong JA3.** Việc JA3 **loại** giá trị GREASE là con dao hai
> lưỡi: một mặt vân tay không "trôi" vì GREASE ngẫu nhiên; mặt khác Chrome **xoay
> thứ tự extension** ở mỗi kết nối (chính thức từ Chrome 110, thực tế đã thấy ở
> bản 108–109, đầu 2023), mà JA3 có tính thứ tự → JA3 của Chrome vẫn trôi. **Chính
> vì vậy JA4 mới ra đời** (có sắp xếp).

### Tầng 3 — Chứng thư: kiểm tra danh tính TLS của máy chủ

Kiểm tra chứng thư đối chiếu với SNI: chứng thư có hợp lệ với tên miền trong SNI
không. Ở TLS 1.3 chứng thư **được mã hoá**, nên về phía thụ động chỉ còn SNI và ASN
hạ tầng.

*(Phần còn lại của tầng 3 và các tầng sau được wiki phân tích sâu trong các bài
riêng — xem mục 4.)*

---

## 2. Bắt/chặn DNS trên ТСПУ (tháng 8/2026)

> **Trang này liên quan trực tiếp tới hệ thống NextDNS + tường DNS trong dự án
> `zapret2-dotfile` của bạn.**

**Hiện tượng:** từ tối **26/08/2026** (số liệu đầu tiên từ 21/08), truy vấn DNS
thường qua **UDP/53** tới `8.8.8.8` / `1.1.1.1` của một phần thuê bao Nga **không
tới được** đích. ТСПУ nhận diện DNS bên trong gói và **ghi đè địa chỉ nhận** sang
máy chủ **НСДИ**. Nó trả lời thay: domain bị chặn → **`NXDOMAIN`**, còn lại → địa
chỉ thật.

| Mốc | Sự kiện |
|:--|:--|
| **21/08/2026** | Thuê bao đầu tiên ghi nhận bị thay |
| **26/08/2026** | Đợt thông báo bùng nổ (theo ngày đăng bài Habr) |
| **27/08/2026** | Bài Habr của `angry_agent` công bố cơ chế |
| **28/08/2026** | Đo đạc resolver НСДИ; **một phần đã bị gỡ** |

### Ba dấu hiệu độc lập chứng minh bị thay

**1. Cờ `aa` và mục `AUTHORITY` rỗng.**

| Cờ | Ý nghĩa |
|:--|:--|
| `qr` | đây là **trả lời**, không phải câu hỏi |
| `rd` | client yêu cầu tìm đệ quy |
| `ra` | server làm được |
| **`aa`** | **authoritative answer** — server **tự giữ** zone này |

Google và Cloudflare **không giữ** zone `youtube.com`; họ là **recursive** — đi hỏi
server authoritative rồi trả lại **không** kèm cờ `aa`. Đo từ host ngoài Nga cho
thấy cả `8.8.8.8`, `1.1.1.1`, `77.88.8.8` đều trả `qr rd ra` — **không** `aa`.

Trong các ảnh chụp bị can thiệp: **`flags: qr aa rd ra`** và **`AUTHORITY: 0`**.

Mảnh thứ hai củng cố: theo RFC 2308, `NXDOMAIN` phải kèm bản ghi **SOA** (bản
"hộ chiếu" của zone, cho biết ai và bao lâu đã báo tên không tồn tại). Thực tế mọi
resolver công cộng đều kèm SOA, kể cả **chính** resolver НСДИ khi trả lời
trung thực: `dig nonexistent-zzz.com @195.208.5.1` → `AUTHORITY: 1` + SOA của zone
`com`. Trong các câu trả lời bị can thiệp, `AUTHORITY` **rỗng**.

**Sự bất thường nằm ở sự kết hợp:** `NXDOMAIN` + cờ `aa` + `AUTHORITY` rỗng.

```bash
dig www.youtube.com @8.8.8.8 | grep -E "^;; (->>HEADER|flags)"
```

Xuất hiện `aa` cạnh `NXDOMAIN` → gần như chắc chắn **không phải** Google trả lời.

**2. TTL và ICMP lộ người nhận thật.**

Trường **TTL** trong header IP là bộ đếm số lần chuyển tiếp cho phép; khi về 0 gói
bị hủy và gửi ICMP Time-to-Live Exceeded. Thông điệp ICMP đó **chứa bên trong bản
sao header gói bị hủy** — tức là nhìn thấy **địa chỉ nhận tại thời điểm gói chết**,
sau mọi biến đổi.

Chính tác giả bài Habr dùng cách này (gửi TTL nhỏ bằng `hping3`) và thấy địa chỉ
nhận là `195.208.5.1`. Đó chính là resolver **НСДИ**.

**3. Mạng của máy chủ thật sự trả lời.**

Thay vì Google, thực tế là **hạ tầng MSK-IX**.

### Máy chủ НСДИ

`195.208.5.1` và `195.208.4.1` trả lời tên `b.res-nsdi.ru` và `a.res-nsdi.ru` —
resolver **НСДИ** (Национальная система доменных имён), hạ tầng DNS nhà nước dựng
theo luật "chủ quyền Internet Nga". Đây cũng chính là resolver ghi trong **hướng
dẫn chính thức** cho các nhà mạng kết nối vào hệ thống.

Đo 28/08: trả `NXDOMAIN` cho `youtube.com` và `rutracker.org`; phân giải bình thường
`ya.ru`, `github.com`, `discord.com`.

### Lỗ hổng và bất thường của cơ chế

| Bất thường | Chi tiết |
|:--|:--|
| **Gần như không đụng TCP** | DNS kinh điển **bắt buộc** phải chạy qua TCP (RFC 7766), tự động khi đáp không vừa gói UDP. Trong các ca quan sát, truy vấn TCP (`dig +tcp`, `nslookup -vc`) **tới được** resolver thật |
| **Can thiệp "qua đôi"** | Không phải lúc nào cũng trúng. Có thể do cân bằng tải giữa các node xử lý |
| **Chuỗi truy vấn nhanh phá logic** | 5 truy vấn giống nhau trong vài mili giây (cùng port, cùng ID): cái đầu `NXDOMAIN`, **4 cái sau trả địa chỉ thật**. Giả thuyết: thiết bị tạo bản ghi "cuộc trò chuyện" ở gói đầu rồi quyết định theo bản ghi đó |
| **"Hâm nóng" bằng TTL thấp vô hiệu hoá thay thế** | Gửi trước một truy vấn TTL 2 (nó qua ТСПУ và chết ở node kế, không tới resolver nào), rồi lặp lại với TTL 64 bình thường → **nhận đáp thật**. Với nội dung ngẫu nhiên thay vì truy vấn DNS thì thao tác này **không** hiệu quả |
| **Ngay cả truy vấn tới chính НСДИ cũng bị can thiệp** | Thuê bao Дом.ру: truy vấn tới `195.208.4.1`, `195.208.5.1`, `62.76.62.76`, `62.76.76.62` cũng đi lệch — detector cho thấy resolver thật là `RIPN-RU-RND` thay vì `RIPN-NS5-RU-MSK` |
| **DNSSEC chỉ bắt được trên zone có ký** | `youtube.com`, `rutracker.org`, `facebook.com` **không** ký → validator không thấy. Nhưng `torproject.org` **có** ký → đáp bị can thiệp **không vượt** kiểm tra |

### Triệu chứng và cách kiểm

Triệu chứng **rất dễ nhầm**: Internet vẫn chạy, ping vẫn đi, dịch vụ Nga vẫn mở,
nhưng YouTube báo *"Connect to the internet — you're offline"* hay
`DNS_PROBE_FINISHED_NXDOMAIN`.

**Hai triệu chứng khác nhau ở chặng khác nhau:**

| Triệu chứng | Nghĩa là |
|:--|:--|
| "Domain not found" | Kết nối **chưa từng bắt đầu** — hỏng DNS |
| `TLS DROP` + treo bắt tay | **Đã có địa chỉ**, kết nối đã bắt đầu và bị đứt khi bắt tay. Đây là việc ТСПУ khác, không thấy liên hệ trực tiếp với thay DNS |

**Vì sao lúc mở lúc không** — bốn giải thích:

1. **Thay thế không trúng mọi truy vấn.** Bấm "Làm mới" chính là truy vấn lại.
2. **Hệ thống thường có nhiều DNS.** Lần lặp lại có thể rơi vào server thứ hai,
   không bị chặn ở node của bạn.
3. **Trình duyệt đã tự chuyển sang kênh mã hoá.** Chrome/Edge có "Bảo mật DNS"
   (DoH), ở một số cấu hình bật tự động.
4. **Đáp âm tính được cache không lâu.** Trong đáp bị thay **không có bản ghi SOA**,
   nên thời gian do resolver quyết định, thường tính bằng phút. Cache còn đáp từ chối
   thì site không mở **dù rule đã ngừng kích hoạt**.

```bash
# chạy 5 lần, xem NXDOMAIN có ổn định không
dig www.youtube.com @8.8.8.8
dig www.youtube.com @8.8.8.8
dig www.youtube.com @8.8.8.8
dig www.youtube.com @8.8.8.8
dig www.youtube.com @8.8.8.8
```

Kết quả "bay" nghĩa là can thiệp **không ổn định**, không thể dựa vào "lúc này nó
lại chạy".

### Cách khắc phục

Xếp theo **độ bền tăng dần** — các dòng trên giữ được chừng nào rule chưa mở rộng.

| Cách | Chống thay thế | Lưu ý |
|:--|:--:|:--|
| Resolver khác (`77.88.8.8`) | ⚠️ đôi khi | Một số thuê bao không bị chặn, nhưng resolver Nga có thể lọc theo danh sách riêng |
| DNS qua **TCP** | ✅ trong các ca quan sát | Thủ công; khó ép hệ thống và ứng dụng đi qua TCP; rule dễ mở rộng sang TCP |
| **DoT** (853/TCP), **DoQ** (853/UDP) | ✅ ngày 28/08 | Kết nối theo **IP trực tiếp** thì còn sống; gọi theo **tên** có thể bị đứt |
| **DoH** theo IP trực tiếp | ✅ ngày 28/08 | Một số client cần tách tên khỏi địa chỉ vì chứng thư |
| Ghi vào `hosts` | ✅ cho domain đã biết | Không có mask, địa chỉ cũ dần, **không** cứu được chặn theo SNI |
| **DNSCrypt** (kể cả Anonymized DNS) | ✅ không thể thay | **Không có tên server trong traffic** nên né được chặn theo SNI; nhưng địa chỉ resolver vẫn lộ và bị chặn theo IP |
| **DoH theo tên + zapret theo hostlist** | ✅ khi bị chặn theo SNI | **Vô dụng** nếu resolver bị chặn theo IP |
| Kiểm tra DNSSEC | ⚠️ chỉ là chỉ báo | Chỉ việc với zone **đã ký**; `youtube.com` không ký |
| Resolver recursive **của riêng bạn**, không forward | ⚠️ tạm thời | Chạy được tới khi rule mở rộng tới server gốc và TLD |
| **DNS trong đường hầm** (VLESS, AmneziaWG) | ✅ bền vững | ТСПУ **không thấy** cả resolver lẫn nội dung truy vấn |

**Chỗ bật thực tế:**

| Nền tảng | Cách |
|:--|:--|
| Android | Cài đặt → Kết nối → **DNS riêng tư** (đây là DoT). Ô nhập **chỉ nhận tên host**, mà tên của resolver phổ biến lại bị chặn theo SNI → nếu không được, chỉ còn đường hầm |
| Windows 11 | Cài đặt → Mạng và Internet → thuộc tính adapter → Gán máy chủ DNS → sửa → *"Mã hoá DNS: chỉ mã hoá"* |
| Trình duyệt | Chrome: Cài đặt → Quyền riêng tư → "Dùng DNS bảo mật". Firefox: Cài đặt → Quyền riêng tư → "DNS qua HTTPS". **Chỉ chữa được trình duyệt** |
| Linux | `systemd-resolved` + DoT (`DNSOverTLS=yes`) |

**Sau mọi lần đổi DNS, xoá cache** — không thì đáp từ chối cũ còn "mọi giây":
`ipconfig /flushdns` (Windows) · `resolvectl flush-caches` (Linux) ·
`chrome://net-internals/#dns` (Chrome) · khởi động lại router.

### ⚠️ Đây chính là lý do dự án của bạn cần tường DNS

Cơ chế thay DNS của ТСПУ chỉ hoạt động với **UDP/53 tới địa chỉ ngoài**. Một hệ
thống như của `zapret2-dotfile` — NextDNS qua **DoT** (TCP/853) + tường ufw **DROP**
mọi 53/853 không trỏ về 4 IP NextDNS — khiến:

1. Truy vấn DNS **không bao giờ** đi qua đường UDP/53 có thể bị can thiệp.
2. Nếu ТСПУ có nới thay thế sang DoT theo tên, profile hostlist có thể vượt — nhưng
   nếu chặn theo IP thì chỉ còn đường hầm.
3. Chặn theo **IP** của resolver là biện pháp không giải được bằng Zapret.

---

## 3. Chặn theo vân tay trình duyệt (JA4)

**Tình huống thật:** site `wireflow.space` (IP `82.24.123.105`) **không mở** ở Chrome
và Edge, nhưng **mở** ở Firefox, Safari, và qua `curl`.

| Quan sát | Chi tiết |
|:--|:--|
| Trong Chromium | Sau ClientHello là một loạt **TCP Retransmission**, rồi **RST**. Bản thân IP **không** bị chặn |
| Điều bị chặn | Đúng **một** JA4: `t13d1516h2_8daaf6152771_d8a2da3f94cd` |
| Ý nghĩa | Không phải "Chrome nói chung" mà vân tay **thế hệ Chrome 134** (trong CSDL JA4 ghi là "Chrome 134, macOS") — đúng vân tay mà **MTPROTO FakeTLS Telegram** dùng. Cùng chữ ký này xuất hiện ở một số bản Chrome/Edge trên Windows |
| Chrome 148 trên Windows | JA4 **khác** — `t13d1514h2_8daaf6152771_827b515c4f52` (14 extension thay vì 16) → **không** dính block |
| F5 thường "chữa" được | Chromium thêm extension `pre_shared_key` (tls session resumption) → vân tay đổi thành `t13d1517h2_8daaf6152771_b6f405a00624` → không dính rule nữa |
| Firefox, curl không bị chặn | Vì JA4 khác — "chữ viết" khác |

### Cách vượt

**1. Cờ Chrome `cryptography-compliance-cnsa`** — bật chế độ CNSA (chuẩn mật mã
Hoa Kỳ), đổi **thứ tự ưu tiên** cipher và nhóm trao khoá trong ClientHello (gần
Chrome 146 còn gồm cả thoả thuận **post-quantum**) → chữ viết TLS đổi.

```
chrome://flags/cryptography-compliance-cnsa → Enabled → restart
```

Chạy được trên các trình duyệt Chromium (Chrome, Brave, Opera, Yandex.Browser).
Trên Windows có sẵn file `.bat` đặt cờ qua registry.

> ⚠️ **Không phải thuốc trị bệnh.** Chỉ đổi chữ viết TLS, chỉ giúp chống chặn gắn với
> nó.

**2. `curl-impersonate`** — công cụ **chẩn đoán**, không phải vượt trình duyệt.
Nó giả lập bắt tay đúng bằng trình duyệt cụ thể (Chrome, Edge, Firefox, Safari),
tới cả tập extension TLS, cipher, curve và tham số HTTP/2.

Giá trị lớn nhất: **kiểm trong vài giây xem DPI có phản ứng với vân tay client
không**. Site mở với `curl_ff117` nhưng không với `curl_chrome116` (hoặc ngược lại)
→ chứng minh chặn đi theo JA3/JA4, không phải IP hay SNI.

```bash
curl_chrome116 https://example.com
curl_ff117     https://example.com
curl_safari15_3 https://example.com
```

Có thể nạp `libcurl-impersonate.so` vào ứng dụng khác qua
`LD_PRELOAD` + `CURL_IMPERSONATE=chrome116` mà không sửa mã ứng dụng.

**3. Tắt QUIC.** Triệu chứng: site hỗ trợ HTTP/3 nhưng tải "lúc được lúc không" hoặc
treo timeout, trong khi trình duyệt khác có lúc lại mở.

Lý do: QUIC đi trên **UDP**, DPI xử lý UDP kém và khó đoán hơn TCP → một phần luồng
UDP bị cắt âm thầm.

```
chrome://flags/enable-quic → Disabled → restart
```

Trình duyệt chuyển sang TCP (HTTP/1.1 hoặc HTTP/2). Cái giá: có thể chậm hơi ở site
mà QUIC thực sự tăng tốc. **Không ảnh hưởng khả năng tiếp cận nội dung.**

---

## 4. Các trang phân tích chuyên biệt khác

| Trang | Nội dung |
|:--|:--|
| `dpi-analysis-pipeline` | Phễu kiểm tra (mục 1) — dựa trên bài Habr của @cyberscoper |
| `statistical-morphing-concept` | **Thống kê biến dạng**: không giấu *giao thức* mà giấu *hành vi*. Kênh vượt lặp lại thống kê của chính lưu lượng thường của bạn — cùng nhịp, cùng dung lượng — để bên ngoài trông như "người này đang đọc feed", không phải "đây là proxy". Giá thành thật mà tác giả nói thẳng: **"kênh phương án cuối"** cho văn bản (64–128 Kbit/s), không phải VPN nhanh. Bài chỉ ra cả **trần lý thuyết** của ý tưởng này |
| `olcrtc` | **OlcRTC** — đường hầm TCP mã hoá trên WebRTC. Bên ngoài trông như **cuộc gọi video hợp pháp** tới dịch vụ đã được phép. Sơ đồ: app → SOCKS5 cục bộ → `olcrtc cnc` → WebRTC/SFU → `olcrtc srv` → Internet. Mã hoá XChaCha20-Poly1305, mux bằng smux trên data/video channel. Khuyến nghị bắt đầu: Jitsi + datachannel. Có bản cho router OpenWRT/LuCI, desktop (Electron), Android |
| `browser-ja4-fingerprint-block` | Case study JA4 (mục 3) |
| `rdp-ecodpi` | **Phần cứng** (mục 5) |
| `tspu-inspectors-checkers-2026` | Bảy bộ dò lỗi (mục 7) |

---

## 5. Phần cứng: EcoDPI và công ty РДП.РУ

**РДП.РУ** (RDP.ru, Research & Development Partners) — nhà phát triển Nga thiết bị
DPI vận hành, thành lập 2010. **Từ 2020 kiểm soát 100% bởi «Ростелеком»**; theo
CNews, phí gom quyền kiểm soát năm 2020 khoảng **1,68 tỷ rúp** (≈1,7 tỷ).

Nền tảng **EcoSGE** (*Service Gateway Engine*) — **một chiếc hộp** trên phần cứng
x86, gộp:

| Thành phần | Chức năng |
|:--|:--|
| **EcoNAT** | CG-NAT |
| **EcoBRAS** | Kiểm soát thuê bao |
| **EcoFilter** | Lọc URL |
| **EcoZR** | Zero-rating |
| **EcoQoE** | Metric chất lượng |
| **EcoDPI** | Phân tích traffic **tới tầng 7 OSI**, nhận diện **hơn 3200 ứng dụng** |

> Con số 3200 là **metric tiếp thị**, tăng dần theo thời gian: 2000 → 3000 → 3200.

**Chính phần mềm РДП.РУ** — theo dữ liệu HRW và các nghiên cứu học thuật
**Censored Planet** — nằm nền tảng của ТСПУ, hệ thống DPI thống nhất do
Roskomnadzor quản lý qua ЦМУ ССОП.

Theo hướng dẫn chính thức của EcoSGE, thiết bị làm đúng những gì thuê bao quan
sát ở ТСПУ:

- lọc theo trường **SNI** trong TLS kèm **đứt kết nối**
- **tiêm gói RST** cho HTTPS và **redirect** cho HTTP
- "**whitelist**" với mặc định **chặn tất cả**
- ghi nhật ký

---

## 6. Nhật ký sự kiện năm 2026

| Thời điểm | Sự kiện |
|:--|:--|
| **Từ 06/2026** | **Thiệt hại kèm theo**: site hợp pháp trên host Nga bắt đầu "sập" |
| **23/06/2026** | Discord không hoạt động, **Twitch bị chặn** — đợt thay đổi chặn |
| **Từ 08/2026** | **Chặn subnet Cloudflare và Amazon** theo whitelist — cả dải địa chỉ bị ảnh hưởng |
| **03/07/2026** | **Chặn 8.8.8.8** — DoH/DoT Google ngừng trả lời, nhiều VPN "chết" |
| **02–03/2026** | **НСДИ như công tắc ngắt**: domain YouTube và WhatsApp đơn giản **bị gỡ khỏi** cơ sở dữ liệu nhà nước; site ngừng phân giải được |
| **08/2026** | **Bắt DNS qua ТСПУ** (mục 2) |
| **H1/2026** | **YouTube +24%** bất chấp bị chặn — dữ liệu Future Lab trên chín video platform; cách Mediascope đo YouTube qua VPN |
| **06/2026** | **Bẫy tham số `scMinPostsIntervalMs`** của bản 3x-ui — tham số này **kích hoạt** ТСПУ |
| **T8/2026** | Đợt trừng phạt mới: hệ sinh thái CDN Cloudflare bị ảnh hưởng |

### Сопутствующий ущерб — vì sao site hợp pháp lại "chết"

Từ tháng 6/2026 nhiều site trên host Nga bắt đầu "rớt" dù **không** nằm trong
danh sách cấm. Wiki có phân tích phóng bút riêng:
`post-pochemu-legli-ru-sajty-iyun-2026`.

---

## 7. Bảy bộ dò lỗi chặn

> **Đừng lẫn kết luận của chúng với nhau.** Chúng trả lời **ba câu hỏi khác nhau.**

| Loại | Số | Trả lời câu hỏi nào |
|:--|:--|:--|
| **Nhìn mạng của bạn** | 5 | Nhà mạng làm gì với các kết nối của bạn? |
| **Nhìn máy chủ của bạn từ bên ngoài** | 1 | Máy chủ bạn giống VPN bao nhiêu trong mắt nhà kiểm duyệt? |
| **Nhìn mạng người khác** | 1 | Trông như thế nào từ các zone đo ở nhiều vùng Nga? |

| Công cụ | Đặc điểm |
|:--|:--|
| **DPI Detector** (Python, 2240 ★ ngày 20/09/2026) | Chi tiết nhất về phía client: **năm** bài kiểm, **110** mục tiêu trong **43** hệ thống độc lập, tự dò SNI "trắng", kiểm tra DNS hai pha với chuẩn DoH và xác định resolver thoát thật |
| **dpi-checkers** | Về mặt phương pháp hay nhất: checker chạy **trong trình duyệt, không cài gì**; tiện ích `dpi-ch` viết bằng Go với chọn mục tiêu **động** qua bộ lọc kiểu `org("hetzner") && country("de")` — để nhà kiểm duyệt không có gì để đưa vào whitelist |

### ⚠️ "Chặn TCP 16–20 KB" **không phải** ngưỡng byte

Theo quan sát cộng đồng, giới hạn này **đếm gói** (thường khoảng **25** ở cả hai
chiều cộng lại). Nên trong báo cáo thấy cả 15 KB lẫn 24 KB ở các dòng liền nhau.

Tác giả dpi-checkers đề xuất cái tên trung thực: **`l4-25`** — và cái tên đó giải
thích vì sao hiệu ứng tương tự cũng xuất hiện trên **UDP**.

---

## 8. Thủ pháp phía client

| Thủ pháp | Cơ chế |
|:--|:--|
| `chrome-cnsa-flag-bypass` | Cờ `cryptography-compliance-cnsa` đổi thứ tự cipher/trao khoá trong ClientHello (mục 3) |
| `tspu-disable-quic-chrome` | Tắt QUIC để tránh timeout ТСПУ (mục 3) |
| `curl-impersonate` | Giả lập chữ viết TLS của trình duyệt để **chẩn đoán** (mục 3) |
| `olcrtc` | Đường hầm WebRTC trong "cuộc gọi hợp pháp" (mục 4) |
| `statistical-morphing-concept` | Giấu **hành vi** thay vì giấu giao thức (mục 4) |

---

## 9. Cho chủ website và chủ mạng

### Sửa site bị chặn nhầm

Trang `economic-filter-foreign-channels-2026` và phần thân của DPI cho **cách tự
bảo vệ**: **HTTP/2 Only + TLS 1.2**. Đây là cấu hình mà bài hướng dẫn wiki khuyến
nghị cho chủ site gặp chặn nhầm.

### Có nên chặn lưới Nga (ASN/CIDR) không?

Trang `subnet-whitelist-blocking-2026` phân tích: có nên chặn subnet của Yandex,
VK, Sber trên máy chủ của bạn không.

### Phong tỏa mạng Nga (Blacklist)

`ru-network-blocklists` — cơ sở dữ liệu các dải bị chặn.

---

## 10. Chính sách và dự báo

### 🎯 Lộ trình tới 2030

| Hạng mục | Nội dung |
|:--|:--|
| **VPN** | Chỉ thị Roskomnadzor (đầu 05/2026) giao KPI cho ГРЧЦ: **"hiệu quả chặn truy cập các biện pháp vượt (VPN) đạt 92% trước 31/12/2030"**. Ngân sách ~**40 tỷ rúp** (≈20 tỷ cho 2026 và ≈20 tỷ cho 2027–2028). **Nghĩa đúng của "92%" không được giải thích** |
| **Traffic** | Kế hoạch Bộ Số (03/2026): tới 2026 **100%** traffic Internet Nga phải đi qua **АСБИ** — hệ thống an ninh mạng tự động, lõi là ТСПУ. Năng lực lọc tăng **2,5 lần**, lên **954 Tbit/s** vào 2030. Ngân sách dự án "Hạ tầng an ninh mạng" tăng 14,9 tỷ lên **83,7 tỷ rúp** |
| **Ẩn danh** | Chuyển sang định danh bắt buộc: từ phát biểu của đại biểu Svincov (10/2025: *"trong 3–5 năm truy cập Internet chỉ sau khi định danh"*) tới đề xuất **internet-ID** thống nhất của Bộ Số, gắn với số điện thoại và qua đó tới hộ chiếu (12/2025; lý do chính thức: *"đếm chính xác số người dùng"*) |

### 💸 Bộ lọc kinh tế

Từ **03/2026** có **quy chế đồng thuận** (không phải "lệnh cấm" hình thức): các
nhà mạng chỉ được **mở rộng kênh ra nước ngoài khi có sự đồng ý của Bộ Số**. Theo
Gudenko, **chưa ai** qua được quy chế, và **tiêu chí chưa công bố** cho các nhà
mạng.

Khoảng **20 công ty** chủ kênh ra nước ngoái đã ký cam kết **không mở rộng** (theo
РБК, theo đề nghị của Bộ Số, trong bối cảnh đấu VPN).

Traffic VPN nhìn từ phía nhà mạng **giống traffic nước ngoài**, nên **mọi** traffic
vượt đều dính. Mùa hè traffic quốc tế giảm theo mùa, tới tháng 12–01 lên đỉnh.

Khi traffic chạm trần của kênh mà không được mở rộng, nhà mạng chỉ còn lựa chọn:
lọc nó, hoặc **"đặt bộ lọc kinh tế"** — **nâng giá** ra nước ngoài. Dự báo: hậu quả
đầu tiên **08–09/2026**.

**Kịch bản xấu nhất** (theo Gudenko): tách giá bán lẻ làm đôi — Internet trong
nước (giá hiện tại hoặc rẻ hơn) và Internet nước ngoài (đắt hơn).

### 🌐 Ngày Internet 2026

Tổng kết 10/2025 – 09/2026 và "**Антифрод 3.0**" với nhật ký đăng nhập trên các
site. Xem `internet-day-2026-rkn-year`.

### 📋 Cải cách cấp phép nhà mạng

Khoảng **hai mươi** loại giấy phép bị thay bằng **ba**. Xem
`isp-licensing-reform-2026`.

### 🗺️ 27 vùng mất nhà mạng địa phương

Xem `isp-licensing-27-regions-september-2026`.

### 🎭 VPN "ngụy trang" và whitelist

Xem `mincifry-whitelist-vpn-hosting-august-2026`.

### 🌊 Dự báo đợt chặn VPN mới

Xem `vpn-blocking-wave-forecast-summer-2026`.

### 🔍 Truy vấn VPN bằng IP hosting

Xem `mincifry-whitelist-vpn-hosting-august-2026`.

---

## 11. Index 30 trang namespace DPI

| Nhóm | Trang |
|:--|:--|
| **Cơ chế** | `DPI` · `dpi-analysis-pipeline` · `rdp-ecodpi` · `statistical-morphing-concept` · `olcrtc` |
| **Sự cố 2026** | `tspu-false-blocks-june-2026` · `tspu-disable-quic-chrome` · `tspu-http2-tls12-fix` · `tspu-whitelist-cloudflare-june-2026` · `tspu-dns-nsdi-dnat-august-2026` · `tspu-3xui-scmininterval-trap` · `nsdi-domain-removal-2026` · `twitch-block-2026` · `youtube-video-consumption-h1-2026` · `google-dns-8888-block-july-2026` · `post-pochemu-legli-ru-sajty-iyun-2026` · `internet-day-2026-rkn-year` |
| **Fingerprint** | `browser-ja4-fingerprint-block` · `chrome-cnsa-flag-bypass` · `curl-impersonate` |
| **Giả thuyết** | `tspu-h2-h3-fingerprint-hypothesis` |
| **Chẩn đoán** | `tspu-inspectors-checkers-2026` · `ru-network-blocklists` |
| **Chính sách** | `rkn-vpn-2030-roadmap` · `economic-filter-foreign-channels-2026` · `isp-licensing-reform-2026` · `isp-licensing-27-regions-september-2026` · `mincifry-whitelist-vpn-hosting-august-2026` · `subnet-whitelist-blocking-2026` · `vpn-blocking-wave-forecast-summer-2026` |