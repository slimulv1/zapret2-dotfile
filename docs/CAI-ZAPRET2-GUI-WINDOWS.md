# Cài Zapret 2 GUI trên Windows

Hướng dẫn đầy đủ, từ tải tới khi site mở được. Viết theo tài liệu wiki của dự án
Zapret (<https://wiki.zapret.moe/>), tháng 10/2026.

---

## 0. Đọc mục này trước tiên

Repo `zapret2-dotfile` này dựng cho **Linux/CachyOS**, nơi chặn đi qua **DNS**.
Tài liệu này nói về **Zapret 2 GUI trên Windows**, và cái nó chữa là một kiểu chặn
**khác hẳn**:

| | Repo này (Linux) | Zapret 2 GUI (Windows) |
|:--|:--|:--|
| Cái chặn tên miền | **DNS** — NextDNS trả về IP hoặc chặn | **DPI** — bộ lọc đọc SNI/`Host:` trong gói tin |
| Công cụ vượt | Tầng 2 NextDNS quyết định | `nfqws2` cắt gói mở đầu để bộ lọc đọc hỏng |
| Chặn theo IP | Zapret **vô dụng** | Zapret **vô dụng** |

> ⚠️ **Nếu máy bạn ở Việt Nam và chặn kiểu DNS như README mô tả, thì Zapret 2
> GUI không có tác dụng gì.** Lý do nằm ngay trong kiến trúc: Zapret **sửa** gói tin
> đang đi, không **tạo** ra gói tin. Tên miền bị chặn ở tầng DNS thì không còn kết
> nối nào để mà sửa.
>
> Zapret 2 GUI sinh ra cho môi trường có **ТСПУ** — hệ thống lọc sâu ở tầng đường
> truyền, kiểu Nga. Hướng dẫn này vẫn đầy đủ và đúng, nhưng nó **không phải** thứ
> bạn cần cho trường hợp trong README. Ở Việt Nam, hãy dùng tầng NextDNS của repo.

Tài liệu này giữ nguyên góc nhìn của wiki: nói về **cách dùng Zapret 2 GUI trên
Windows**, không phán xét môi trường của bạn.

---

## 1. Điều kiện

| Yêu cầu | Chi tiết |
|:--|:--|
| **Windows** | **10 bản 1809 trở lên** |
| Quyền | Chạy với **quyền quản trị** |
| Mạng | Đã có sẵn một kết nối Internet |

**Windows 7, Windows 8, Windows 10 build 1803 trở xuống** — xem mục 9.

---

## 2. Tải — năm cách

### Cách 1 — dễ nhất

Vào <https://t.me/bypassblock/399>, tải `ZapretSetup.exe`, cài đặt.

Sau khi cài, Zapret xuất hiện trong **Start Menu**.

### Cách 2 — qua kênh Telegram

Vào <https://t.me/zapretnetdiscordyoutube>.

- Tải bản **`dev`** nào bất kỳ (ra khá thường xuyên), **hoặc**
- Tìm trong kênh: `🔄 Канал обновлений: STABLE`

Tải tệp `.exe`, cài y như cách 1.

### Cách 3 — qua bot Telegram

Vào <https://t.me/zapretbypass_bot>, gõ lệnh:

```
/get_stable
```

Bot phát tệp về. Cài y cách 1.

### Cách 4 — Forgejo (có tệp kiểm tra)

Mở trang phát hành:
<https://git.zapret.moe/zapretdiscordyoutube/zapretgui/releases>

Chọn bản ổn định hoặc bản thử nghiệm, tải tệp `.exe` ở mục **Загрузки**.

Tệp `.sha256` cạnh bên **chỉ để đối chiếu checksum** — nên kiểm.

```powershell
# PowerShell — đối chiếu trước khi chạy
Get-FileHash .\ZapretSetup.exe -Algorithm SHA256
# so với nội dung tệp .sha256 tải kèm
```

### Cách 5 — tự dựng từ mã nguồn

Làm theo hướng dẫn:
<https://git.zapret.moe/zapretdiscordyoutube/zapretgui/src/branch/main/docs/build.md>

### Lưu ý an toàn

Trước khi chạy bất kỳ tệp `.exe` nào:

1. Chỉ lấy từ **một trong năm nguồn trên**.
2. Đối chiếu **SHA256** nếu có (cách 4).
3. Sự cố **11/08/2026**: GitHub gỡ bỏ nhiều dự án sạch, **nhưng lại để lại các
   repo chứa malware dưới cùng tên**. Repo hợp pháp của Zapret **không nằm trên
   GitHub** — nó ở Forgejo (`git.zapret.moe`), đúng như các link trên.

Chi tiết các ca giả mạo:
[`docs/WIKI-VAN-DE-AN-TOAN.md`](WIKI-VAN-DE-AN-TOAN.md) mục 1.

---

## 3. Lỗi lúc cài đặt

> **Bấm `Пропустить этот файл` — "Bỏ qua tệp này".**

Lỗi này **không nguy hiểm**. Tệp đó **không đổi qua các phiên bản**, nên installer
không ghi đè được. Cứ bỏ qua.

---

## 4. Chọn preset và chạy

### Bước 1 — chọn preset

Vào menu preset. **Lần chạy đầu mặc định là `Default`.`

Bấm vào preset → **áp dụng ngay**.

Trạng thái Zapret phải là **đang chạy**. Nếu không, báo lại trong nhóm hỗ trợ
(<https://t.me/bypassblock/399>).

### Bước 2 — kiểm

Mở trình duyệt, thử site bị chặn.

> **Không** mở site bằng `F5` trên tab đã có. TСПУ giữ lại kết nối cũ, nên chiến
> lược mới không bao giờ chạy. Đóng hẳn trình duyệt rồi mở lại, hoặc dùng cửa sổ
> ẩn danh mới.

---

## 5. Không preset nào ăn thì dùng "chạy trực tiếp"

Đây là bước quan trọng nhất sau khi cài. **Sửa profile, đừng đổi cả preset.**

Vì sao: đổi preset đổi chiến lược **ở mọi profile cùng lúc**, nên sửa site này
lại hỏng site kia.

### Vào chế độ chạy trực tiếp

Menu cài đặt → **chạy trực tiếp** (`Прямой запуск`).

> ⚠️ Tên này **gây hiểu nhầm**. Đây **không phải** một kiểu vượt đặc biệt, chỉ là
> khả năng chỉnh từng profile một.

### Bắt đầu bằng `Basic`

Chỉ dùng `Advanced` **sau khi** đã hiểu `tcpseg`, `oob`, `multisplit`,
`multidisorder`, `fake`, `fakedsplit`, `fakeddisorder`, `hostfakesplit`.

### Thứ tự làm

1. Chọn **hạng mục** cần sửa chiến lược
2. Chọn **chiến lược** cho hạng mục đó (mỗi hạng mục có bảng chiến lược riêng bên
   phải)
3. Với mục chỉ có **UDP** (không có tên miền), bật tùy chọn **bypass theo IP** nếu có
4. Số gói xử lý: bắt đầu ở **`3`–`4`**, tăng lên `10`–`20` nếu cần

### Sau mỗi lần đổi chiến lược

Đóng hẳn ứng dụng — kể cả **không còn trong tray** — rồi mở lại.

---

## 6. Tinh chỉnh danh sách

### Thêm tên miền của riêng bạn

Mỗi dòng một tên miền, **không** ghi `https://`, **không** ghi `www`:

```
blocked-site.com
another-blocked-site.org
ru                     ← toàn bộ vùng *.ru
^onlyThisSite.com     ← CHỈ đúng domain này, không gồm subdomain
```

- Mặc định **bao gồm subdomain**: có `example.com` thì `mail.example.com` cũng
  được xử lý. Muốn **chỉ** domain gốc thì viết `^example.com`
- Danh sách được đọc lại khi tệp đổi

### Lọc theo IP

Mỗi dòng một IP hoặc CIDR (v4 hoặc v6). Hữu ích cho **UDP**, nơi không có tên miền.

### Loại trừ một site

Zapret có thể **làm hỏng** một site vốn vẫn chạy được: nó chèn gói giả, gói đó tới
tận máy chủ thật, máy chủ coi là rác và reset.

Nếu site vốn chạy mà giờ hỏng → cần **loại trừ** (`pass`), không phải đánh lừa.

Trong GUI: chọn chiến lược **`pass` (không làm gì)** và đặt profile đó **lên trên**.

### Đổi DNS

Trong GUI có phần sửa DNS. Dùng **Google DNS** hoặc **Dns.SB**.

⚠️ **Đừng dùng Yandex DNS** — đã ngừng mở được Discord và site bị chặn khác.

---

## 7. Phải tắt những thứ này trước khi kết luận là hỏng

### Tiện ích mở rộng trình duyệt

Tắt hẳn trước khi thử. **Không** thêm trang YouTube vào danh sách miễn trừ — **tắt
đi**:

- SaveFrom · Юбуст
- Adblock
- Антизапрет
- AdGuard

**AdGuard chặn kết nối âm thanh của Discord** khi Zapret đang chạy.

Thay SaveFrom bằng [`yt-dlp`](https://github.com/yt-dlp/yt-dlp).

### Yandex Browser

**Không khuyến nghị.** Nó tự thay DNS, tự chặn YouTube bằng cơ chế riêng, và cài
sẵn tiện ích gây nhiễu.

### VPN và proxy

Tắt **mọi** VPN và proxy của Windows. Chúng có thể làm hỏng toàn bộ Zapret.

### Antivirus

Antivirus thấy chương trình cài driver bắt gói mạng (WinDivert) và ghi vào stack
mạng — đúng hành vi, nhưng khớp mẫu cảnh báo. **Thêm exception.**

### mitmproxy

Cả hai đều dùng WinDivert. Tắt Zapret thì mitmproxy chạy lại.

---

## 8. Lỗi và cách xử lý

| Triệu chứng | Nghĩa là | Làm gì |
|:--|:--|:--|
| Lỗi lúc cài | Không nguy hiểm | Bấm **Bỏ qua tệp này** |
| `ERR_CONNECTION_TIMED_OUT` | **ТСПУ chặn chiến lược đang chọn** | Đổi chiến lược trong GUI |
| *"Có thể trang không tồn tại hoặc thiết bị dùng DNS sai"* | **DNS hỏng** | Đổi DNS qua GUI sang Google DNS hoặc Dns.SB |
| Một site hỏng, site khác vẫn mở | Chỉ **một profile** hỏng | Sửa đúng profile đó |
| Trang vốn chạy được giờ hỏng | Zapret làm hỏng | **Loại trừ** bằng `pass` |
| Đổi hết preset vẫn hỏng | Chưa có chiến lược đúng | Dùng chạy trực tiếp, sửa profile |
| **"Không khởi động được DPI"** | — | Xem mục 8.1 |
| Lỗi GEO-block | Site **tự** chặn người ở nước bị trừng phạt | Dùng `hosts` / VPN, xem mục 8.2 |

### 8.1 "Không khởi động được DPI"

Ba cách, theo thứ tự:

**1. Chạy tệp `.bat` bằng tay**

Vào thư mục Zapret → mở thư mục **`bat`** → thử chạy từng tệp `.bat` một.

Thấy dòng **`capture is started`** trong cửa sổ console nghĩa là **đang hoạt động**.

**2. Chuyển sang chạy trực tiếp**

Đôi khi tệp `.bat` không chạy đúng. Vào **chạy trực tiếp** → chọn chiến lược cho
các site cần thiết.

**3. Hỏi hỗ trợ, kèm tệp log**

<https://t.me/zaprethelp> — **đính kèm tệp log**.

### 8.2 Lỗi GEO-block

Site **không** bị chặn bởi RKN. Nó **đã chạy được ở Nga** — nó **tự** không muốn
nối tới người ở nước bị trừng phạt. Zapret **vô dụng** ở đây.

Cách xử lý: tab **`hosts`** trong GUI (đổi địa chỉ), hoặc VPN.

**Lưu ý tháng 8/2026:** tab `hosts` hỏng vì DNS mã hoá bị chặn theo tên, và DNS
thường bị thay. Chi tiết và cách tự điền tay:
[`docs/WIKI-ZAPRET1-THAM-CHIEU.md`](WIKI-ZAPRET1-THAM-CHIEU.md) mục 5.3.

---

## 9. Blockcheck — lúc cuối cùng

Khi **không còn chiến lược nào trong sẵn có** mà chạy.

1. Tạo thư mục `blockcheck`
2. Giải nén toàn bộ archive lên desktop
3. Vào thư mục `blockcheck`
4. Chạy **`blockcheck.cmd`**
5. **Chờ khoảng 1 giờ. KHÔNG đóng cửa sổ console** — không thì phải làm lại từ đầu
6. Gửi `blockcheck.log` vào <https://t.me/zapretblockcheck/4>

> ⚠️ **Chiến lược `wssize` nằm cuối log — đừng lấy bừa.**
> `wssize` **không** dùng được với `--hostlist`, **không** dùng được với bộ lọc
> `l7`, và **làm chậm** mọi kết nối trên cổng bị lọc.
> Nếu trong log có chiến lược chạy được **không** kèm `wssize` — lấy cái đó.
>
> Chính tác giả zapret khuyên: **tốt hơn bỏ `wssize` và tìm cách khác.**

Giải thích đầy đủ:
[`docs/WIKI-ZAPRET-NENH-TANG-GAME.md`](WIKI-ZAPRET-NENH-TANG-GAME.md) mục 3.

---

## 10. Windows 7 và 8

Bản console, dùng tệp `.bat` thay vì GUI. **Không hỗ trợ GUI Python.**

| Điều | Nội dung |
|:--|:--|
| Đổi chiến lược | Phải **đóng tay toàn bộ cửa sổ** cũ rồi mở cửa sổ mới |
| Gặp sự cố | Chạy **`stop.bat`** để dừng |
| Có lỗi | Chuyển sang bản GUI ổn định hơn |
| Tự khởi động | **Chỉ thủ công** — thêm vào registry hoặc thư mục Start Menu |

| Phiên bản | Nguồn |
|:--|:--|
| **Zapret 2** | <https://git.zapret.moe/zapretdiscordyoutube/zapret2-youtube-discord> |
| **Zapret 1** | <https://t.me/bypassblock/666> hoặc Forgejo, tag [`win7`](https://git.zapret.moe/zapretdiscordyoutube/zapretgui/releases/tag/win7) |

---

## 11. Cộng đồng và hỗ trợ

### Kênh

| Việc | Link |
|:--|:--|
| Nhóm chính | <https://t.me/bypassblock/399> |
| Nhóm về chặn | <https://t.me/youtubenotwork> |
| **Tải Zapret** (mọi bản) | <https://t.me/zapretnetdiscordyoutube> |
| Tải bản dev | <https://t.me/zapretguidev> |
| **Hỏi cấu hình** | <https://t.me/zaprethelp> |
| **Blockcheck** | <https://t.me/zapretblockcheck> |
| Lộ trình dự án | <https://t.me/approundmap> |
| **Virus trong Zapret?** | <https://t.me/zapretvirus> |
| Bot tải Zapret | <https://t.me/zapretbypass_bot> |
| Toàn bộ chat | <https://t.me/addlist/xjPs164MI7AxZWE6> |

### Mã nguồn và phát hành

| Việc | Link |
|:--|:--|
| Phát hành | <https://git.zapret.moe/zapretdiscordyoutube/zapretgui/releases> |
| Mã nguồn GUI | <https://git.zapret.moe/zapretdiscordyoutube/zapretgui> |
| Mã nguồn wiki | <https://git.zapret.moe/zapretdiscordyoutube/todo> |
| Lõi `nfqws2` (bol-van) | <https://github.com/bol-van/zapret2> |

---

## 12. Sau khi cài xong

Ba việc nên làm ngay:

1. **Tắt VPN, proxy, AdGuard, Yandex DNS** — nếu không, mọi phép thử đều vô nghĩa
2. **Đóng hẳn trình duyệt và mở lại** trước mỗi lần thử — `F5` không tạo kết nối mới
3. **Chạy `t1-config` tương đương**: bật debug log
   (`--debug=@logs/<tên>_debug.log`) rồi đọc xem profile nào thực sự chiếm kết nối

Chi tiết cách đọc log:
[`docs/WIKI-ZAPRET2-CAU-HINH.md`](WIKI-ZAPRET2-CAU-HINH.md) mục 8.

---

## Tài liệu liên quan trong repo này

| Tệp | Nội dung |
|---|---|
| [`docs/ZAPRET2-WIKI-TONG-HOP.md`](ZAPRET2-WIKI-TONG-HOP.md) | Zapret 2 là gì, kiến trúc, pipeline, 11 kỹ thuật desync |
| [`docs/WIKI-ZAPRET2-CAU-HINH.md`](WIKI-ZAPRET2-CAU-HINH.md) | Preset, profile, blob, orchestrator `circular`, log analyzer |
| [`docs/WIKI-DESYNC-PACKET-SO-DO.md`](WIKI-DESYNC-PACKET-SO-DO.md) | Sơ đồ packet từng byte của cả 11 kỹ thuật |
| [`docs/WIKI-ZAPRET1-THAM-CHIEU.md`](WIKI-ZAPRET1-THAM-CHIEU.md) | Cờ `nfqws`, hostlist/ipset/hosts, chẩn đoán |
| [`docs/WIKI-ZAPRET-NENH-TANG-GAME.md`](WIKI-ZAPRET-NENH-TANG-GAME.md) | Router, Android, Steam, game, `wssize`, bộ `.bat` |
| [`docs/WIKI-DPI-TSPU.md`](WIKI-DPI-TSPU.md) | DPI và ТСПУ: phễu kiểm tra, bắt DNS, vân tay JA4 |
| [`docs/WIKI-VAN-DE-AN-TOAN.md`](WIKI-VAN-DE-AN-TOAN.md) | Virus giả, chứng thư НУЦ, bảo mật |