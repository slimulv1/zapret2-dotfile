# Cài Zapret 2 GUI trên Windows 11 — bypass DPI

Hướng dẫn này chỉ làm **một việc**: cài Zapret 2 GUI trên Windows 11 để nó sửa gói tin
đi ra, khiến DPI của nhà mạng không đọc được tên miền trong đó.

**Không đụng DNS.** Không đổi resolver, không DoH, không sửa `hosts`.

> Nguồn: đào toàn bộ 303 trang wiki.zapret.moe ngày 2026-10-11.
> Bản tham chiếu: Zapret GUI `21.0.0.x`, engine `winws2`.
> Dùng **bản STABLE**, không dùng bản dev — dev là nightly, và đã có bug logic làm sập
> cả Internet (đã vá ở `21.0.0.100–104`).

---

## 1. Tải và cài

### 1.1 Tải từ Forgejo — có checksum để đối chiếu

<https://git.zapret.moe/zapretdiscordyoutube/zapretgui/releases>

Trang phát hành có tệp `.exe` **và tệp `.sha256`**. Tệp `.sha256` không phải để chạy, nó
để **chứng minh** tệp bạn tải về không bị đổi trên đường đi.

```powershell
# tải cả hai về cùng thư mục, rồi:
Get-FileHash .\ZapretSetup.exe -Algorithm SHA256
```

Chuỗi phải **giống hệt** nội dung tệp `.sha256`. Không giống → đừng chạy.

*(Muốn tiện hơn thì lấy bản STABLE qua bot <https://t.me/zapretbypass_bot> lệnh
`/get_stable`. Nhưng cách đó không kiểm chứng được.)*

### 1.2 Unblock rồi chạy bằng quyền admin

```powershell
# 1. Chuột phải file .exe → Properties → tick "Unblock" → Apply
#    Không tick thì Windows giữ "Zone.Identifier" và cảnh báo tiếp.

# 2. Chạy:
.\ZapretSetup.exe
```

Windows 11 sẽ hỏi UAC — bấm **Yes**. Bắt buộc admin, vì phải cài driver WinDivert.

> SmartScreen chặn → **More info** → **Run anyway**. Chỉ làm khi đã đối chiếu SHA256 ở 1.1.

### 1.3 Nhớ thư mục cài đặt

Chương trình cài vào **gốc ổ hệ thống**: `C:\Zapret\...`

Toàn bộ cấu hình nằm trong **một tệp `settings.json`** trong thư mục đó — trước đây nằm
trong registry, từ bản `21.0.0.51–54` chuyển ra tệp.

**Backup thư mục `C:\Zapret` trước khi nâng cấp.** Nâng cấp mà mất là mất sạch profile.

---

## 2. Bật TCP timestamps — bắt buộc

**Đây là bước mà hầu hết người bỏ qua, và là lý do "cấu hình này chạy trên Linux mà
không chạy trên máy tôi".**

### Vì sao

Cách desync phổ biến nhất: gửi **paket giả** với SNI vô hại để DPI cho rằng bạn đang vào
trang vô hại, rồi mới gửi ClientHello thật. Nhưng nếu pakết giả **sống tới server**,
server nhận dữ liệu rác và phiên hỏng.

Nên phải làm cho pakết giả **chết trước khi đến server**. Cách kinh điển: dịch `TSval`
đi đủ xa để server coi là quá cũ (cơ chế PAWS). Nhưng điều đó **chỉ chạy khi TCP option
timestamps có mặt trong SYN**.

### Vấn đề

> «TCP-сеанс открывает сама Windows, а она по умолчанию держит timestamps **выключенными**»
> — Chính Windows mở TCP, và nó **tắt timestamps mặc định**.

Linux thì bật sẵn. Nên `ts` chạy được luôn trên Linux, không chạy trên Windows.

### Làm

```powershell
netsh interface tcp set global timestamps=enabled
netsh interface tcp show global      # phải thấy enabled
```

Ba điều dễ sai:

1. **Phải bật ở từng máy.** Không có preset nào tự bật được cho máy khác.
2. **Phải mở kết nối MỚI.** Đóng hẳn trình duyệt rồi mở lại. Phiên TCP đã thiết lập
   không tự thành phiên có timestamp hồi tốc.
3. **Chiến thuật chỉ dựa vào `ts` mà không ghi kèm `netsh` là không đáng tin trên Windows.**

### Nếu không muốn đụng `netsh`

Bỏ bước 2, và **đừng dùng `ts`**. Dùng `md5sig` hoặc `badseq` — chúng không cần
timestamps. Wiki khuyến nghị đúng điều này cho preset "cài xong quên": đừng gắn hết TCP
vào `ts`, hãy để biến thể `ts` qua điều kiện `cond_tcp_has_ts` để nó không bắn nhầm
vào hư không, và giữ một phương án dự phòng.

---

## 3. Thêm exception cho Defender

WinDivert là driver bắt gói tin ở tầng kernel — đúng loại thứ AV cảnh báo.

```
Windows Security → Virus & threat protection → Manage settings
→ Exclusions → Add an exclusion → Folder → C:\Zapret
```

Không làm bước này thì Defender có thể **xoá file giữa lúc đang chạy**, và triệu chứng
là "lúc chạy được, lúc không".

---

## 4. Chọn chế độ lọc WinDivert

WinDivert phải bắt gói tin **trước** khi zapret2 kịp xử lý. Lọc càng rộng càng chắc bắt
được, nhưng càng nặng và càng dễ phá ứng dụng khác.

| Chế độ | Tham số | Khi nào dùng |
|---|---|---|
| **Nhẹ (cơ bản)** ✅ | `--wf-l3=ipv4,ipv6 --wf-tcp=80,443 --wf-udp=443,50000-50100` | **Bắt đầu từ đây** |
| Rất nhẹ | `--wf-raw=@windivert.discord_media+stun+sites.txt` | Chỉ gọi thoại Discord/STUN, muốn đụng tối thiểu |
| Thông minh (mọi cổng) | `--wf-raw=@windivert.all.txt` | Chế độ nhẹ không đủ |
| Hung hãn (mọi cổng) | `--wf-l3=ipv4,ipv6 --wf-tcp=80,443,444-65535 --wf-udp=443,444-65535` | Nhà mạng lọc trên nhiều cổng lạ |
| Tắt | *(rỗng)* | Tắt tạm để thử |

Khoảng `50000–50100` trong chế độ mặc định không ngẫu nhiên — đó là dải cổng media trong
cuộc gọi (Discord, Teams, Zoom). Không có nó thì giọng hay vỡ.

⚠️ **Hai chế độ cuối làm hỏng game và ứng dụng.** Nếu máy bạn chơi game, đó là thông tin
quan trọng. Chỉ leo lên khi đã chứng minh chế độ nhẹ không đủ.

---

## 5. Chạy

Mở Zapret 2 GUI → chọn một preset → bấm chạy. Thế là xong phần chính.

### Cấu hình tối thiểu

Nếu không preset nào ăn, vào **chế độ chạy trực tiếp** và bắt đầu từ tối thiểu:

```bash
--filter-tcp=443 --filter-l7=tls --payload=tls_client_hello --lua-desync=multisplit:pos=1
```

Từ đó **cộng dần**: `fake` → `fooling` → UDP/QUIC → thêm domain.

### HTTP (cổng 80)

```bash
--filter-tcp=80 --filter-l7=http --payload=http_req \
--lua-desync=fake:blob=fake_default_http:tcp_md5 \
--lua-desync=multisplit:pos=method+2
```

`pos=method+2` cắt ngay sau `GE` `T ` của `GET`/`POST` — DPI mất phần định tuyến, phần
còn lại vẫn là HTTP hợp lệ để server dựng lại.

### Bảng chọn fooling

Fake phải **chết trước server**. Mỗi cách giết fake sống trên một đường khác nhau:

| Fooling | Cơ chế | Chết ở đâu | **Trên Windows** |
|---|---|---|---|
| `badseq` | Lệch sequence ra ngoài cửa sổ TCP | Server | ✅ An toàn nhất |
| `md5sig` / `tcp_md5` | Thêm TCP MD5 option | Server | ✅ Nhưng làm header TCP to ra; ClientHello lớn (Kyber) + split nhỏ có thể vỡ MTU |
| `ts` / `tcp_ts` | Lệch `TSval` → server thấy quá cũ | Server | ⚠️ **Cần `netsh` — mục 2** |
| `badsum` | Hỏng checksum | Bất kỳ node nào | ❌ NAT router cắt trước DPI |
| `datanoack` | Bỏ cờ ACK | Server | ❌ NAT masquerade cắt |
| TTL / `ip_autottl` | Fake chết dỡ trên đường | Giữa đường | ⚠️ Phải đoán số hop tới DPI; đổi router là hỏng |

Quy tắc: **thứ phụ thuộc vào việc gói "hỏng" thì chết ở NAT. Thứ phụ thuộc sequence /
timestamp thì sống qua NAT.** Nên `ts` và `badseq` an toàn hơn `badsum` và `datanoack`
khi bạn ở sau router.

---

## 6. Thêm domain của bạn

Chỉ cần hostlist, không cần profile phức tạp:

1. Trang chính → mở **"Редактор"** (Editor)
2. Tab **Hostlist** → gõ tên miền vào **"Ваши записи"** → **"Сохранить список"**
3. Bắt đầu bằng **tên chính xác đang không lên**, không phải domain chung

### ⚠️ Đừng chỉ điền tên trên thanh địa chỉ

Khi bạn gõ `soundcloud.com`, trình duyệt chỉ tải **khung** trang từ tên đó. Script, ảnh,
font, dữ liệu feed, player, đăng nhập — tất cả tải **riêng**, và thường từ **tên khác**:
`api-v2.soundcloud.com`, `sndcdn.com`, CDN quảng cáo.

DPI quyết định số phận **từng kết nối một**, theo tên miền trong đó. Thiếu domain con
trong hostlist sẽ thành: *"trang mở được nhưng nút không bấm được, feed trống, video
không phát"*.

### Khi nào cần tới profile

Profile là cách giới hạn việc desync vào đúng tên miền — nhanh hơn và ít phá app hơn so
với để zapret đụng mọi thứ. Tạo bằng:

1. **Copy preset đang chạy** và bật bản copy
2. **"Профили пресета"** → `+` → đặt tên + TCP cổng → **"Добавить"**
3. Trong profile: **"Редактор"** → Hostlist → gõ domain → lưu
4. **"Готовые стратегии"** → chọn chiến thuật → tick **"Включён"**

### Về "nút loại trừ"

Không có nút đó, và đó là **cố ý** — không có ở GUI lẫn định dạng preset. Thứ bạn muốn
làm được bằng hai cơ chế:

| Cơ chế | Dùng khi |
|---|---|
| Profile với chiến thuật `pass` | Chỉ muốn một phần đi qua nguyên vẹn |
| `--hostlist-exclude` / `--ipset-exclude` | Danh sách chính có mặc ngoài danh sách loại trừ |

---

## 7. Khi không vào được — đọc log

Từ `21.1.4.0`, GUI có trang **"Анализ лога winws2"** ở mục **"Диагностика"**. Nó dịch log
thô thành bảng kết nối: host, IP, cổng, profile nào khớp, số gói, verdict.

### Bật log

Trang chính → khối **"Дополнительные настройки"** (khối có cảnh báo *"Изменяйте только
если знаете что делаете"*) → tăm **"Включить лог-файл (--debug)"**.

Nó tự thêm vào preset:
```bash
--debug=@logs/<tên_preset>_debug.log
```

⚠️ **Phải áp lại preset sau khi bật.** Cờ `--debug` chỉ vào đối số lúc khởi động engine.

⚠️ **Tắt xong.** Log ghi từng gói một; wiki ví dụ một phiên ngắn đã cho 43.000 dòng
(~2,9 MB). Để quên thì tốn hàng trăm MB.

### ⚠️ Đừng đưa nhầm file

| File | Là gì | Đọc được? |
|---|---|---|
| `<preset>_debug.log` | Output của winws2 | ✅ |
| `orchestra_*.log` | Output orchestrator | ✅ |
| **`zapret_log_*.txt`** | **Log của chính GUI** | ❌ |
| `tg_proxy.log`, `crashes.log` | Telegram proxy, crash | ❌ |

### Đỏng đỏ `drop` trên SYN là BÌNH THƯỜNG

> «Красный `drop` на исходящем SYN или ClientHello — это обычно **нормальная работа
> стратегии** (оригинал заменён поддельными пакетами), а не ошибка.»

`drop` ở đây nghĩa là chiến thuật **đang chạy**: gói thật bị thay bằng gói giả. Tưởng
là lỗi rồi đi sửa là phá đúng thứ đang hoạt động.

---

## 8. Trước khi kết luận là hỏng

| Phải tắt | Vì sao |
|---|---|
| Tiện ích mở rộng trình duyệt (**uBlock Origin, AdGuard**, Privacy Badger…) | Có bộ lọc riêng, gói tin bị bóp méo, không còn giống hệt gói thật |
| VPN / proxy | Đường đi không còn là đường nhà mạng |
| `mitmproxy` và công cụ MITM khác | Cố giải mã TLS để sửa nội dung, cắt ngang việc desync |
| Yandex Browser | Có lớp lọc riêng |

### Hai bẫy khi kiểm kết quả

**1. blockcheck và trình duyệt có "vân tay" khác nhau.** Blockcheck kiểm bằng `curl`, bạn
dùng trình duyệt — ClientHello khác nhau. Verdict lệch được **cả hai chiều**: blockcheck
nói "chạy" mà trình duyệt không vào, hoặc ngược lại. Không suy ra gì về trải nghiệm thật
chỉ từ blockcheck.

**2. Blockcheck tự bật `netsh ... timestamps=enabled` trước khi test.** Nên nó báo `ts`
chạy được **không chứng minh** máy bạn sẽ chạy được ở đời thường.

### Cách kiểm trung thực

1. Đóng hẳn trình duyệt (xóa hết phiên).
2. Mở lại, vào **thẳng** trang cần kiểm — không qua Google.
3. Xem tab **"Сеть"**: request nào treo, request nào fail.
4. Với site nhiều tên miền con, kiểm **từng tên**, không chỉ trang chủ.
5. Vẫn không rõ thì bật log (mục 7).

---

## 9. Gỡ

```powershell
# 1. Tắt zapret trong GUI trước (nút dừng, rồi đóng hẳn cửa sổ)

# 2. Settings → Apps → Installed apps → gỡ

# 3. Kiểm driver còn sót không
sc query windivert

# 4. Gỡ nếu còn
sc stop windivert
sc delete windivert
```

Driver sót sẽ tiếp tục bắt gói tin — triệu chứng là mạng chậm/lỗi mà **không còn chương
trình nào chạy**. Đó là lý do bước 3, 4 tồn tại.

`settings.json` **không bị gỡ** — đó là dữ liệu của bạn. Xóa tay là mất profile.

---

## 10. Một lưu ý cuối

Nếu bạn đã làm đúng tất cả 9 mục trên mà **vẫn không có gì thay đổi** — không site nào
khác biệt, cả khi tắt zapret lẫn khi bật — thì khả năng cao đường của bạn **không có DPI
chặn SNI**, và zapret không có gì để sửa.

Cách kiểm trong 5 giây:

```powershell
curl.exe -s -o NUL --resolve "github.com:443:20.205.243.166" --tlsv1.2 -w "%{http_code}" https://github.com/
```

Trả `200` ⇒ nối thẳng IP mà vẫn lên ⇒ **không có chặn SNI/DPI**. Khi đó zapret2 không
phải công cụ bạn cần, và mọi thứ mục 1–9 đều vô nghĩa.

Script đo đầy đủ cho cả hai hệ điều hành nằm trong repo: `do-thu-dpi.sh` (Linux) và
`do-thu-dpi.ps1` (Windows).

---

## Nguồn

Các trang wiki đã dùng, đọc 2026-10-11:

| Trang | Dùng cho mục |
|---|---|
| `Zapret/download` | Tải, yêu cầu Win10 1809+ |
| `Zapret/changelog-21.0.0-dev-june-2026` | Đường dẫn `C:\Zapret`, `settings.json`, bug sập Internet |
| `Zapret2/ts-and-fooling` | TCP timestamps trên Windows, bảng fooling, cảnh báo blockcheck |
| `Zapret2/windivert` | 5 chế độ lọc WinDivert |
| `Zapret2/add-profile` | Tạo profile |
| `Zapret2/find-site-domains` | Vì sao chỉ tên trên thanh địa chỉ là chưa đủ |
| `Zapret2/exclusions` | Không có nút loại trừ, hai cơ chế thay thế |
| `Zapret2/log-analyzer` | Bật `--debug`, đọc log, `drop` đỏ là bình thường |
| `Zapret2/verify-strategy` | Hai bẫy khi kiểm kết quả |

Mã nguồn engine: <https://github.com/bol-van/zapret2> · `docs/manual.md`