# Cài Zapret 2 GUI trên Windows 11

> Tài liệu này viết từ **toàn bộ** wiki.zapret.moe (303 trang markdown, đào ngày **2026-10-11**),
> không phải từ kinh nghiệm chung về "cài phần mềm bypass". Mỗi khẳng định kỹ thuật
> đều truy được về một trang wiki cụ thể — trang đó được dẫn ở cuối mỗi mục.
>
> **Bản tham chiếu:** Zapret GUI `21.0.0.x` (dev, tháng 6–7/2026), engine `winws2`.
> Wiki nói các bản dev là **nightly và không ổn định**. Nếu bạn không phải
> dò/chỉnh sửa, hãy lấy bản **STABLE** (mục 2.2).

---

## 0. Cổng chặn: đo trước, đừng cài trước

**Đọc mục này trước khi tải bất cứ thứ gì.**

Zapret làm đúng một việc: **làm cho DPI của nhà mạng không đọc được tên miền** trong
gói tin đang đi. Nó *sửa* gói tin. Nó **không** chặn, **không** thay IP, **không** đổi DNS.

Nên câu hỏi phải là: *nhà mạng của bạn có thực sự lọc nội dung gói tin không?*

| Nhà mạng lọc ở đâu | Nối thẳng IP, giữ nguyên SNI | zapret2 có ích? |
|:--|:--|:--|
| Tầng DNS (chặn tên khi phân giải) | **Lên bình thường** | ❌ Vô dụng |
| Tầng DPI (đọc SNI trong ClientHello) | **Hỏng** | ✅ Có ích |
| Chặn IP | Không lên, dù có SNI gì | ❌ Vô dụng |
| Chặn cổng | Không lên | ❌ Vô dụng |

Phép thử đúng chỉ có một: **ép IP nhưng giữ nguyên SNI**, bỏ qua DNS.

```powershell
curl.exe -s -o NUL --resolve "github.com:443:20.205.243.166" --tlsv1.2 -w "%{http_code}" https://github.com/
```

Trả `200` ⇒ **không có chặn SNI/DPI** trên đường đó.

Repo này có sẵn script đo, chạy được cả Linux lẫn Windows:

```powershell
powershell -ExecutionPolicy Bypass -File do-thu-dpi.ps1
```

### Kết quả đo được ở Việt Nam

Ngày **2026-10-11**, đo trên **AS18403 (FPT)**, ép IP + giữ SNI:

| Tên miền | Kết quả |
|:--|:--|
| `wikipedia.org` | HTTP 301 |
| `github.com` | HTTP 200 |
| `cloudflare.com` | HTTP 301 |
| `viet69.be` *(NextDNS đang chặn)* | **HTTP 200** |
| `erothots.co` *(NextDNS đang chặn)* | **HTTP 200** |
| `facebook.com` | HTTP 301 |

Hai domain bị NextDNS chặn vẫn lên khi nối thẳng IP. Phép đo ngày **2026-09-28** cho
kết quả giống hệt: khảo sát 20 domain hay bị chặn ở Việt Nam, **0** bị chặn ở tầng SNI.

> **Kết luận đo được, không phải suy đoán:** ở Việt Nam hiện nay chặn chủ yếu ở **tầng DNS**.
> Zapret 2 **không phải** công cụ đúng cho chặn DNS. Công cụ đúng là lớp DNS mã hóa —
> mục 9.

Đừng hiểu nhầm: điều trên là kết quả **ở đường đo**. Nhà mạng khác, tỉnh khác có thể khác.
Bạn **phải tự đo** trên đường của mình trước khi cài. Nếu đo thấy có DPI thật, quay lại
đây và làm tiếp từ mục 5.

> 📄 Nguồn: `docs/NETWORK-DESIGN.md` §1, `Zapret2/symptom-not-cause`,
> `Zapret/hosts` ("`hosts` … против блокировки по имени сайта в TLS-приветствии он бесполезен")

---

## 1. Điều kiện

| Mục | Yêu cầu |
|:--|:--|
| Hệ điều hành | **Windows 10 1809 trở lên**, hoặc Windows 11 |
| Đặc quyền | Administrator — vì cài driver WinDivert |
| Driver | **WinDivert** 2.x — do chương trình tự cài, không cài tay |
| Kiến trúc | x64 hoặc ARM64 đều có bản |

Windows 7, 8 và Windows 10 1803 trở xuống dùng **bản riêng** (trang `🐳 Win 7 и 8`).
Windows 11 thì dùng bản GUI chính, không có gì đặc biệt.

> ⚠️ Zapret 2 **không chạy** trên macOS/iOS. Muốn dùng trên đó thì cài trên router.

> 📄 Nguồn: `Zapret/download`, `Zapret2/Zapret2.md` (bảng "Thiết bị nào cài gì")

---

## 2. Tải và cài

Wiki liệt kê 5 cách. Khác nhau ở mức **kiểm chứng được** — và đó là điều quyết định.

### 2.1 Forgejo — cách duy nhất có checksum để đối chiếu

<https://git.zapret.moe/zapretdiscordyoutube/zapretgui/releases>

Trang phát hành có tệp `.exe` **và tệp `.sha256`**. Tệp `.sha256` không phải để chạy, nó
để **chứng minh** tệp `.exe` bạn tải về không bị đổi trên đường đi.

```powershell
# tải cả hai về cùng thư mục
Get-FileHash .\ZapretSetup.exe -Algorithm SHA256
# so với nội dung tệp .sha256 tải kèm
```

Hai chuỗi phải **giống hệt**. Không giống ⇒ đừng chạy.

### 2.2 Các cách khác (tiện hơn, ít kiểm chứng hơn)

| Cách | Nguồn | Ghi chú |
|:--|:--|:--|
| 1. Link trực tiếp | <https://t.me/bypassblock/399> → `ZapretSetup.exe` | Dễ nhất |
| 2. Kênh Telegram | <https://t.me/zapretnetdiscordyoutube> | Tìm `🔄 Канал обновлений: STABLE` để lấy bản ổn định |
| 3. Bot Telegram | <https://t.me/zapretbypass_bot> → lệnh `/get_stable` | Tự lấy bản stable |
| 5. Tự build | <https://git.zapret.moe/…/zapretgui/src/branch/main/docs/build.md> | Dành cho người muốn sửa mã |

> 💡 Cách 2 nói rõ: bản `dev` ra thường xuyên; bản `STABLE` nằm ở kênh cập nhật riêng.

### 2.3 ⚠️ Trước khi bấm "run"

**Windows 11 sẽ chặn `.exe` chưa ký.** Đây là hành vi đúng, không phải lỗi:

1. Chuột phải file → **Properties** → tick **Unblock** ở cuối tab General → **Apply**.
   Không tick thì Windows giữ "Zone.Identifier" và tiếp tục cảnh báo.
2. Chạy với **Run as administrator**.
3. Nếu SmartScreen chặn → **More info** → **Run anyway**. Chỉ làm khi bạn đã đối chiếu
   SHA256 ở mục 2.1.

### 2.4 ⚠️ Chương trình cài vào **gốc ổ đĩa hệ thống**

Từ changelog 21.0.0.51–54:

> «Настройки переехали из реестра в один файл, программа ставится в корень системного диска»
> — Cài đặt chuyển từ registry sang **một tệp**, chương trình cài vào **gốc ổ hệ thống**.

Trên thực tế đường dẫn là `C:\Zapret\...`, ví dụ wiki dẫn tới
`C:\Zapret\Dev\lists\ipset-amazon.txt`.

Hai hệ quả thực tế:

- **Backup trước khi cài bản mới.** Toàn bộ cấu hình nằm trong tệp `settings.json`
  cùng thư mục cài đặt. Nâng cấp mà mất thư mục này là mất sạch profile của bạn.
- Đừng tưởng đường dẫn ngẫu nhiên kiểu `AppData` là "sạch". Nó ở gốc ổ `C:`,
  cùng khu vực với `Windows` và `Program Files` — nhiều phần mềm quét AV hay soi đó.

> 📄 Nguồn: `Zapret/changelog-21.0.0-dev-june-2026` §"💾 Хранение настроек"

---

## 3. Bật TCP timestamps — BƯỚC BẮT BUỘC trên Windows

**Đây là khác biệt lớn nhất giữa Windows và Linux, và là nguyên nhân "sao cấu hình
này chạy trên Linux mà không chạy trên máy tôi".**

### Vì sao

Chiến thuật desync phổ biến nhất: gửi **paket giả** với SNI vô hại để DPI cho rằng bạn
đang vào trang vô hại, rồi mới gửi ClientHello thật. Nhưng nếu pakết giả đó **sống sót**
tới tận server, server nhận dữ liệu rác và phiên hỏng.

Vì vậy phải làm cho pakết giả **chết trước khi đến server**. Cách kinh điển: dịch
`TSval` đi một khoảng đủ xa để server coi là quá cũ (cơ chế PAWS). Nhưng điều đó **chỉ
chạy khi TCP option timestamps có mặt trong SYN**.

### Vấn đề

> «TCP-сеанс открывает сама Windows, а она по умолчанию держит timestamps **выключенными**»
> — Chính Windows mở TCP, và nó **tắt timestamps mặc định**.

Linux thì bật sẵn. Nên `--dpi-desync-fooling=ts` trên Linux "chạy được luôn", còn trên
Windows thì không.

| Nền tảng | TCP timestamps mặc định |
|:--|:--|
| Linux client | ✅ Bật |
| **Windows client** | ❌ **Tắt** — phải tự bật bằng `netsh` |
| Sau NAT router | Theo client |
| Trên router (OpenWrt…) | Theo OS router |

### Cách làm

```powershell
# 1. Kiểm tra hiện trạng
netsh interface tcp show global

# 2. Bật
netsh interface tcp set global timestamps=enabled
```

Ba điều dễ sai:

1. **Phải bật trên TỪNG máy client.** Không có cách nào "mặc định cho cả mạng" từ phía
   zapret. Bạn đưa preset cho người khác dùng, họ mở máy ra thấy hỏng — vì máy họ tắt.
2. **Phải mở kết nối MỚI.** Phiên TCP đã thiết lập không tự biến thành phiên có
   timestamp hồi tốc. Đóng trình duyệt hẳn ra rồi mở lại.
3. **Profile chỉ dựa vào `ts` mà không ghi kèm `netsh` là profile không đáng tin trên
   Windows.** Wiki nói thẳng: "Профиль, который держится **только** на `ts`, без этой
   настройки — ненадёжный Windows-профиль."

### Cách an toàn hơn: đừng đặt cược vào `ts`

Wiki khuyến nghị nếu muốn preset "cài xong quên": **đừng gắn hết TCP vào `ts`**.
Hãy thử `md5sig`, `badseq`, `datanoack`, TTL/autottl, `seqovl` — hoặc gate biến thể `ts`
qua điều kiện `cond_tcp_has_ts` để nó **không bắn nhầm vào hư không**.

```bash
--lua-desync=fake:...,cond_tcp_has_ts
```

### ⚠️ blockcheck tự bật timestamps — kết quả bị méo

> «blockcheck.sh и blockcheck2.sh на Windows **сами** пытаются включить timestamps через `netsh`»

Nghĩa là: blockcheck báo `ts` chạy được **không chứng minh** máy bạn sẽ chạy được ở
đời thường. Blockcheck đã bật timestamps trước khi test. Khi đọc kết quả, luôn giả định nó
đã sửa môi trường của bạn.

Nếu blockcheck nói `ts` sống sót, hãy tự kiểm lại bằng `netsh interface tcp show global`
xem nó có bật không.

> 📄 Nguồn: `Zapret2/ts-and-fooling` §"Как правильно атаковать сервер на разных платформах",
> §"Почему blockcheck может вводить в заблуждение"

---

## 4. Cấu hình Windows Defender và SmartScreen

WinDivert là **driver chặn gói tin ở tầng kernel**. Đây đúng loại thứ trình quét AV
cảnh báo — nhiều phần mềm quét coi nó là công cụ can thiệp mạng.

Nếu chưa làm gì và zapret vẫn chạy, bạn may mắn. Nếu không:

1. **Windows Security → Virus & threat protection → Manage settings**
2. **Exclusions → Add an exclusion → Folder** → thêm thư mục cài đặt `C:\Zapret`
3. Thêm cả bản `.exe` cài đặt.

Bỏ qua bước này thì Defender có thể **xoá file giữa lúc đang chạy**, và triệu chứng
bạn thấy là "lúc chạy được, lúc không".

### Ngoài ra, phải tắt trước khi kết luận là hỏng

| Thứ cần tắt | Vì sao |
|:--|:--|
| Tiện ích mở rộng trình duyệt (uBlock Origin, **AdGuard**, Privacy Badger…) | Chúng có bộ lọc riêng, kết nối của bạn bị bóp méo, không còn giống hệt gói tin thật |
| **Trình duyệt dùng DNS mã hóa riêng** | Nếu Chrome/Edge bật "Dùng DNS bảo mật", trình duyệt tự phân giải và **bỏ qua `hosts`** |
| VPN / proxy | Nếu còn VPN, đường đi của bạn không còn là đường nhà mạng |
| `mitmproxy` và công cụ MITM khác | Chúng cố giải mã TLS để sửa nội dung, cắt ngang việc desync |
| Yandex Browser | Có lớp lọc riêng, xung đột |

⚠️ **DoH cấp hệ thống thì VÔ HƠI với `hosts`**, khác với DoH cấp trình duyệt.
Wiki nói rõ: "DoH на уровне системы (Windows 11, `systemd-resolved`) файлу не мешает" —
vì bản ghi `hosts` được kiểm **trước khi** cây truy vấn hình thành. Đây là điểm hay của
Windows 11: DoH sẵn có mà không phá `hosts`.

> 📄 Nguồn: `Zapret/hosts`, `DPI/tspu-dns-nsdi-dnat-august-2026`

---

## 5. Chọn chế độ lọc WinDivert

WinDivert phải bắt gói tin **trước** khi zapret2 kịp xử lý. Bộ lọc càng rộng thì càng
chắc bắt được nhưng càng nặng và càng dễ phá ứng dụng khác.

| Chế độ | Tham số | Bắt gì | Khi nào dùng |
|:--|:--|:--|:--|
| **Rất nhẹ (light)** | `--wf-raw=@windivert.discord_media+stun+sites.txt` | Chỉ media Discord, STUN, và danh sách site chỉ định | Gọi thoại messenger, muốn đụng tối thiểu |
| **Nhẹ (cơ bản)** | `--wf-l3=ipv4,ipv6 --wf-tcp=80,443 --wf-udp=443,50000-50100` | TCP 80/443, UDP 443, UDP 50000–50100 | **Mặc định nên dùng** |
| **Thông minh (mọi cổng)** | `--wf-raw=@windivert.all.txt` | Mọi TCP và UDP | Chế độ nhẹ không đủ |
| **Hung hãn (mọi cổng)** | `--wf-l3=ipv4,ipv6 --wf-tcp=80,443,444-65535 --wf-udp=443,444-65535` | 100% cổng | Nhà mạng lọc trên nhiều cổng lạ |
| **Tắt** | *(rỗng)* | Không lọc | Tắt tạm để thử |

**Bắt đầu từ "Nhẹ (cơ bản)".** Nó phủ đúng những gì DPI thường đọc: HTTP và TLS.
Chỉ leo lên chế độ rộng hơn khi đã chứng minh chế độ nhẹ không đủ.

> ⚠️ Chế độ rộng **làm hỏng game và ứng dụng** — wiki nói thẳng ở cả hai chế độ cuối.
> Nếu bạn chơi game qua máy này, đó là thông tin quan trọng.

Khoảng `50000–50100` trong chế độ mặc định không ngẫu nhiên — đó là dải cổng thường dùng
cho **media trong cuộc gọi** (Discord, Teams, Zoom). Không có nó thì giọng hay vỡ.

> 📄 Nguồn: `Zapret2/windivert`

---

## 6. Chạy: cấu hình tối thiểu, đừng chép đại

Sau khi mở Zapret 2 GUI, chọn một preset và bấm chạy. Nếu không preset nào ăn, đừng nhảy
thẳng vào chế độ "chạy trực tiếp" với cấu hình 20 dòng — hãy đi từ tối thiểu:

```bash
--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1
```

Từ đó cộng dần: `fake` → `fooling` → UDP/QUIC → thêm domain vào hostlist.

### Hai preset làm việc khác nhau

**HTTP (cổng 80):**
```bash
--filter-tcp=80 --filter-l7=http --payload=http_req \
--lua-desync=fake:blob=fake_default_http:tcp_md5 \
--lua-desync=multisplit:pos=method+2
```

**TLS (cổng 443):**
```bash
--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello \
--lua-desync=multisplit:pos=1
```

> `pos=method+2` — cắt ngay sau `GE` `T ` của `GET`/`POST`, tức DPI mất phần định tuyến
> nhưng phần còn lại vẫn là HTTP hợp lệ để server dựng lại.

### Bảng "kẻ giết fake" — chọn fooling nào

Fake phải **chết trước server**. Mỗi cách giết fake sống trên một đường khác nhau:

| Fooling | Cơ chế | Chết ở đâu | **Trên Windows** |
|:--|:--|:--|:--|
| `ts` / `tcp_ts` | Lệch `TSval` → server thấy quá cũ (PAWS) | Server | ⚠️ **Cần `netsh` — mục 3** |
| `md5sig` / `tcp_md5` | Thêm TCP MD5 option | Server | ⚠️ Làm header TCP to ra; ClientHello lớn (Kyber) + split nhỏ có thể vỡ MTU |
| `badsum` | Hỏng checksum | Bất kỳ node nào | ❌ NAT router thường cắt trước DPI |
| `badseq` | Lệch sequence ra ngoài cửa sổ TCP | Server | ✅ Sống qua NAT |
| `datanoack` | Bỏ cờ ACK | Server | ❌ NAT masquerade cắt |
| TTL / `ip_autottl` | Fake chết dỡ trên đường | Ở giữa đường | ⚠️ Phải đoán số hop tới DPI; router đổi firmware là hỏng |

Quy tắc đơn giản rút ra: **thứ phụ thuộc vào việc gói "hỏng" thì chết ở NAT. Thứ phụ
thuộc vào sequence/timestamp thì sống qua NAT.** Vì thế `ts` và `badseq` là lựa chọn an
toàn hơn `badsum` và `datanoack` khi bạn ở sau router.

> 📄 Nguồn: `Zapret2/ts-and-fooling` §"Каталог способов", `Zapret2/windivert`

---

## 7. Tạo profile cho site của bạn

Profile là cách **giới hạn** việc desync vào đúng tên miền cần thiết. Không có profile
thì zapret2 đụng vào mọi thứ — chậm và dễ vỡ.

### 5 bước (theo wiki)

1. **Copy preset đang chạy** và bật bản copy. Mọi sửa đổi sẽ nằm trong bản copy.
2. **"Профили пресета"** → nút `+` → đặt tên và TCP cổng → **"Добавить"**.
3. Trong profile: **"Редактор"** → tab **Hostlist** → gõ tên miền vào **"Ваши записи"** →
   **"Сохранить список"**. Bắt đầu bằng **subdomain chính xác** đang không lên.
4. **"Готовые стратегии"** → chọn chiến thuật → tick **"Включён"**.
5. Kiểm tra thứ tự profile rồi mở site bằng **kết nối mới**, quan sát tab **"Сеть"**.

### ⚠️ Đừng chỉ điền tên trên thanh địa chỉ

Khi bạn gõ `soundcloud.com`, trình duyệt chỉ tải **khung** trang từ tên đó. Script, ảnh,
font, dữ liệu feed, player, đăng nhập — tất cả tải **riêng**, và thường từ **tên khác**:
`api-v2.soundcloud.com`, `sndcdn.com`, CDN quảng cáo.

DPI quyết định số phận **từng kết nối một**, theo tên miền trong đó. Nên bạn sẽ thấy
*"trang mở được nhưng nút không bấm được, feed trống, video không phát"* — và đó **không
phải** zapret hỏng, đó là **thiếu domain trong hostlist**.

> 📄 Nguồn: `Zapret2/add-profile`, `Zapret2/find-site-domains`

### Về "nút loại trừ" — nó không tồn tại, và đó là cố ý

Wiki có một trang riêng giải thích chuyện này vì người dùng hỏi hoài:

> «Глобального поля "Исключения" на весь пресет не существует — **ни в GUI, ни в формате
> пресета**. Есть только узкие механизмы»

Thứ người dùng gọi là "loại trừ" thực ra là **hai cơ chế khác nhau**:

| Cơ chế | Dùng khi | Ghi chú |
|:--|:--|:--|
| Profile với chiến thuật `pass` | Chỉ muốn một phần đi qua nguyên vẹn | Tốn profile slot |
| `--hostlist-exclude` / `--ipset-exclude` | Danh sách chính có mặc ngoài danh sách loại trừ | Nhanh hơn |

Trang này còn nêu một cái bẫy: nếu profile của bạn dùng cả hostlist và ipset, cách
loại trừ **phải khớp với đúng loại danh sách** — lọc sai loại thì không có tác dụng.

> 📄 Nguồn: `Zapret2/exclusions` (phân tích từ mã nguồn `nfq2/hostlist.c`, `nfq2/ipset.c`)

---

## 8. Đọc log — cách duy nhất để biết chuyện gì xảy ra

Từ 21.1.4.0 (7/2026), GUI có trang **"Анализ лога winws2"** ở mục **"Диагностика"**.
Nó dịch hàng nghìn dòng log thô thành bảng **kết nối**: host, IP, cổng, giao thức, profile
nào khớp, bộ đếm gói, và verdict.

### Bật log

Trang chính **"Управление Zapret 2"** → khối **"Дополнительные настройки"** (khối có
cảnh báo *"Изменяйте только если знаете что делаете"*) → tăm **"Включить лог-файл (--debug)"**.

Nó tự thêm vào preset dòng:
```bash
--debug=@logs/<tên_preset>_debug.log
```

> ⚠️ **Phải áp lại preset sau khi bật.** Cờ `--debug` chỉ vào đối số lúc khởi động
> engine — bật sau khi winws2 đang chạy thì không có tác dụng.

### ⚠️ Log là công cụ tạm thời

Log ghi **từng gói một** và phình rất nhanh. Wiki đưa ví dụ: một phiên ngắn đã cho
**43.000 dòng (~2,9 MB)**. Bật lúc chẩn đoán, tắt xong. Để quên thì tốn hàng trăm MB.

### ⚠️ Đừng đưa nhầm file vào

| File | Là gì | Phân tích được? |
|:--|:--|:--|
| `<preset>_debug.log` | Output của winws2 | ✅ |
| `zapret_winws2_debug_*.log` | Cũ, vẫn đọc được | ✅ |
| `orchestra_*.log` | Output orchestrator | ✅ |
| **`zapret_log_*.txt`** | **Log của chính GUI** | ❌ |
| `tg_proxy.log`, `crashes.log` | Telegram proxy, crash | ❌ |

Parser sẽ nói thẳng *"В файле не найдено пакетных блоков — это debug-лог winws2?"* khi bạn
đưa nhầm. Đó không phải lỗi parser, đó là lỗi chọn file.

### Đọc log thô — mẫu thật

```bash
profile 1 (chatgpt) lua send(repeats="2" range_in=x0-x0 range_out=a0-d8 payload_type= all)
profile 1 (chatgpt) lua syndata(blob="tls_google" range_in=x0-x0 range_out=a0-d8 payload_type= all)
profile 1 (chatgpt) lua tls_multisplit_sni(seqovl_pattern="tls_google",seqovl="652" ...)
Loaded 117132 hosts from /lists/russia-blacklist.txt
```

Dòng `profile N (tên) lua hàm(tham số)` cho biết tên profile — và **đặt tên cho profile
làm analyzer hiển thị tên thay vì số trần**. `7 (youtube.com QUIC)` đọc được, `7` thì không.

Block của một gói:
```
packet: id=0 len=969 outbound IPv6=0 ...
IP4: 192.168.1.x => 31.77.140.129 proto=tcp ttl=128 sport=18131 dport=443 flags=A ...
desync profile/ipcache search target ip=31.77.140.129 port=443
* ipset check for profile 45 (Cloudflare TCP)
[/lists/ipset-cloudflare.txt] include ipset check for 31.77.140.129 : negative
desync profile 0 (no_action) matches
packet: id=0 reinject unmodified
```

Mỗi gói ghi ra: **gói gì → dưới profile nào → làm gì với nó → kết thúc thế nào**.

### Đỏng đỏ `drop` trên SYN gửi đi là BÌNH THƯỜNG

> «Красный `drop` на исходящем SYN или ClientHello — это обычно **нормальная работа
> стратегии** (оригинал заменён поддельными пакетами), а не ошибка.»

Đây là chỗ nhiều người hoảng nhầm nhất. `drop` ở đây nghĩa là **chiến thuật đang hoạt
động**: gói thật bị thay bằng gói giả. Nếu bạn tưởng đó là lỗi và đi sửa, bạn sẽ phá
đúng thứ đang chạy.

### Bonus: dùng analyzer thay Wireshark để gom IP của game

Tạm mở rộng `wf-` filter ra mọi cổng, bật log, chơi game, rồi đọc bảng kết nối — có địa
chỉ và cổng luôn. Hữu ích với **UDP**, nơi TCPView không hiện địa chỉ đích.

> 📄 Nguồn: `Zapret2/log-analyzer`

---

## 9. Nếu đo thấy KHÔNG có DPI: dùng lớp DNS (mục này chạy được trên MỌI nhà mạng)

Quay lại mục 0. Nếu phép đo của bạn cho "không có chặn SNI/DPI" — mà ở Việt Nam đó là
kết quả phổ biến nhất — thì zapret2 **không phải** công cụ bạn cần.

Chặn ở tầng DNS nghĩa là: nhà mạng không cho bạn hỏi "domain này ở đâu". Cách duy nhất
là **hỏi qua kênh mà họ không chặn được**: DNS mã hóa.

### Đây là lợi thế thật của Windows 11 so với Linux

Windows 11 có DoH **tích hợp sẵn ở cấp hệ thống**:

> **Windows 11:** Параметры → Сеть и Интернет → свойства адаптера →
> «Назначение DNS-сервера» → изменить → «Шифрование DNS: только зашифрованные».

Đây là **toàn hệ thống**, không chỉ trình duyệt — mọi ứng dụng đều đi qua nó.

### Ba tầng, chỉ tầng 1 là bắt buộc

| Tầng | Cách | Bắt buộc? |
|:--|:--|:--|
| **DoH cấp hệ thống** | Cài đặt Windows 11 ở trên | ✅ Chính |
| **DoH cấp trình duyệt** | Chrome/Edge "Dùng DNS bảo mật" | ⚠️ Tắt nếu muốn `hosts` có tác dụng |
| Tường chặn DNS nợi | ufw / Windows Firewall chặn 53/853 | Chặn thoát ra DNS thường |

Chọn resolver: **NextDNS** (lọc + chặn theo danh sách), **AdGuard**, **Quad9**
(bảo mật), hoặc **Cloudflare**.

### Sau khi đổi resolver — xóa cache, không là thất bại

```powershell
ipconfig /flushdns
```

Wiki nhấn mạnh: **câu trả lời tiêu cực được cache lại**. Không xóa cache thì bạn cứ
thấy lỗi cũ và kết luận giải pháp không work.

Ngoài ra phải bật **"gửi DNS qua đường hầm"** nếu bạn dùng VPN — chỉ riêng việc kết
nối VPN không đảm bảo truy vấn tên đi qua đường hầm.

> 📄 Nguồn: `DPI/tspu-dns-nsdi-dnat-august-2026`, `Zapret/hosts`

---

## 10. Hai bẫy khi kiểm tra kết quả

Wiki có trang riêng vì "kiểm tra xem chiến thuật có chạy không" là **bước dễ sai nhất**
trong toàn bộ quy trình.

### Bẫy 1: blockcheck và trình duyệt có "vân tay" khác nhau

> «Автоподбор (BlockCheck) проверяет доступность отдельной утилитой (обычно `curl`), а вы
> сидите в браузере или игре — у них разный сетевой "почерк" (отпечаток TLS, размеры пакетов)»

Trình duyệt và `curl` gửi **ClientHello khác nhau**. Verdict của blockcheck và thực tế
**có thể lệch theo CẢ HAI chiều**:

- blockcheck nói "chạy" → nhưng trình duyệt vẫn không vào
- blockcheck nói "không" → nhưng trình duyệt vào ngon

Không suy ra gì từ blockcheck về trải nghiệm thật của bạn nếu chưa kiểm cả hai.

### Bẫy 2: "Không lỗi" không phải "đang hoạt động"

Thay đổi chiến thuật xong, **mở kết nối mới** rồi mới kiểm. Phiên cũ đã bị
quyết định rồi.

### Cách kiểm trung thực

1. Đóng hẳn trình duyệt (xóa hết phiên).
2. Mở lại, vào **thẳng** trang cần kiểm — không qua Google.
3. Xem tab **"Сеть"** của trình duyệt: request nào treo, request nào fail.
4. Với site có nhiều tên miền con, kiểm **từng tên**, không chỉ trang chủ.
5. Đối chiếu log (mục 8) nếu vẫn không rõ.

> 📄 Nguồn: `Zapret2/verify-strategy`, `Zapret2/symptom-not-cause`

---

## 11. Có preset nào "làm sập cả Internet" không

Có. Và nên biết trước.

Changelog ghi lại bug nghiêm trọng ở khoảng **26/05**, đã vá lại trong **.102 và .103**
(vùng `21.0.0.100–104`):

> «фикс критичного бага в логике, который «крашил весь интернет»»

Nghĩa là có **logic bug làm sập toàn bộ kết nối mạng của máy**, không phải chỉ site
đang thử. Nó đã được sửa, nhưng nó nói lên điều quan trọng:

> ⚠️ **Đừng chạy bản dev trên máy bạn cần để làm việc.** Dev build là **nightly** —
> phát hành liên tục, không qua kiểm thử tự động. Nếu máy bạn là máy làm việc chính,
> lấy bản **STABLE**.

Các thay đổi cấu trúc lớn trong 21.0.0.x mà bạn cần biết:

| Phiên bản | Thay đổi | Ảnh hưởng tới bạn |
|:--|:--|:--|
| 21.0.0.51–54 | Cài đặt vào gốc ổ hệ thống; cấu hình ra **một tệp** thay registry | Đường dẫn đổi; **phải backup** |
| 21.0.0.66–96 | Chuyển sang kiến trúc profile, thêm thư mục | Profile cũ có thể phải dựng lại |
| 21.0.0.78 | Profile người dùng trong `settings.json`, section `user_profiles` | Cấu hình nằm trong tệp này |
| 21.0.0.97–117 | Tối ưu hoá, tách việc nặng sang worker | Ổn định hơn |
| 21.0.0.100–117 | Vá bug "sập Internet" | **Nên tránh các bản cũ hơn .117** |
| 21.1.4.0+ | Trang "Анализ лога winws2" | Cần ≥ .1.4.0 mới có |

> 📄 Nguồn: `Zapret/changelog-21.0.0-dev-june-2026`

---

## 12. Gỡ cài đặt

Vì chương trình cài ở **gốc ổ hệ thống** và đăng ký **driver WinDivert**, gỡ bằng
"Xóa chương trình" trong Windows có thể không đủ. Thứ tự an toàn:

```powershell
# 1. Tắt zapret trước — nếu không, driver còn giữ gói tin
#    (trong GUI: nút dừng, rồi đóng hẳn cửa sổ)

# 2. Gỡ từ Settings > Apps > Installed apps

# 3. Kiểm tra driver còn sót không
sc query windivert

# 4. Gỡ driver nếu còn
sc stop windivert
sc delete windivert
```

Driver `windivert` sót lại sẽ tiếp tục bắt gói tin — triệu chứng là mạng chậm/lỗi mà
không còn chương trình nào chạy. Đó là lý do bước 3, 4 tồn tại.

Cấu hình trong `settings.json` **không bị gỡ** — nó là tệp dữ liệu của bạn, không phải
tệp chương trình. Xóa tay thì mất profile.

---

## 13. Checklist

```powershell
# 0. ĐO TRƯỚC. Chưa đo thì chưa cài.
powershell -ExecutionPolicy Bypass -File do-thu-dpi.ps1

#    → "KHÔNG có chặn SNI/DPI"  → Đừng cài zapret. Đọc mục 9.
#    → "CÓ dấu hiệu chặn SNI"   → Tiếp tục:

# 1. Bật TCP timestamps (BẮT BUỘC cho fooling ts)
netsh interface tcp set global timestamps=enabled
netsh interface tcp show global      # xác nhận

# 2. Defender: thêm exclusion cho thư mục cài đặt C:\Zapret

# 3. Tắt hết tiện ích chặn trình duyệt + VPN + proxy

# 4. Chế độ lọc: bắt đầu từ "wf-l3" (TCP 80,443 + UDP 443,50000-50100)

# 5. Preset tối thiểu, chạy, đo lại

# 6. Không được → bật log, đọc log, xem profile nào khớp
```

---

## 14. Nguồn

Toàn bộ khẳng định trong tài liệu này truy về các trang wiki sau, đọc ngày 2026-10-11:

| Trang wiki | Dùng cho mục |
|:--|:--|
| `Zapret2/Zapret2.md` | Bảng thiết bị, khác biệt Zapret 2 vs Zapret |
| `Zapret/download` | 5 cách tải, yêu cầu Win10 1809+ |
| `Zapret/changelog-21.0.0-dev-june-2026` | Đường dẫn cài, `settings.json`, bug sập Internet, lịch sử thay đổi |
| `Zapret2/windivert` | 5 chế độ lọc WinDivert |
| `Zapret2/ts-and-fooling` | TCP timestamps trên Windows, bảng fooling, cảnh báo blockcheck |
| `Zapret2/add-profile` | Quy trình 5 bước tạo profile |
| `Zapret2/find-site-domains` | Vì sao chỉ tên trên thanh địa chỉ là chưa đủ |
| `Zapret2/exclusions` | Vì sao không có "nút loại trừ", hai cơ chế thay thế |
| `Zapret2/log-analyzer` | Bật `--debug`, đọc log, `drop` đỏ là bình thường |
| `Zapret2/verify-strategy` | Hai bẫy khi kiểm tra kết quả |
| `Zapret2/symptom-not-cause` | "Không chạy" là triệu chứng, không phải chẩn đoán |
| `Zapret/hosts` | `hosts` vô dụng với chặn SNI; DoH hệ thống không phá `hosts` |
| `DPI/tspu-dns-nsdi-dnat-august-2026` | DoH cấp hệ thống Windows 11, flush cache |

Đo đạc cục bộ (không phải wiki):
`docs/NETWORK-DESIGN.md` — phép đo FPT ngày 2026-09-28 và 2026-10-11.

Mã nguồn: <https://github.com/bol-van/zapret2> · `docs/manual.md`