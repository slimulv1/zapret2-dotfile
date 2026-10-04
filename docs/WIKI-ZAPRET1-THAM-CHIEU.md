# Zapret 1 (`nfqws` / `winws`) — cờ, danh sách, cài đặt, chẩn đoán

Tài liệu tham khảo từ namespace `Zapret/` của <https://wiki.zapret.moe/> — 86 trang.
Phần này nói về **Zapret 1** (`nfqws` trên Linux, `winws` trên Windows), tức là
kiến trúc **một khối C**, khác hẳn Zapret 2 đã mô tả trong
[`ZAPRET2-WIKI-TONG-HOP.md`](ZAPRET2-WIKI-TONG-HOP.md).

> **Vì sao vẫn cần biết Zapret 1?** Vì `nfqws` vẫn chạy được, vẫn được dùng rộng
> rãi, và — quan trọng hơn — **bảng ánh xạ cờ sang** giúp hiểu logic của Zapret 2
> (mục 8).

---

## 1. Ba cách vượt chặn ở Nga

| Cách | Nguyên lý | Đổi IP? | Cần máy chủ? |
|:--|:--|:--:|:--:|
| **VPN** | Đường đi qua máy chủ trung gian | ✅ Có | ✅ Có |
| **Tor** (+ cầu nối) | Onion routing, nhiều lớp bọc | ✅ Có | ✅ Có |
| **Vượt DPI** (Zapret, GoodbyeDPI) | Sửa gói tin **trên máy mình** để DPI phân tích sai | ❌ Không | ❌ Không |

Zapret **không đổi IP, không tạo đường hầm, không định tuyến qua máy chủ ngoài**.
Nó thao tác **nội dung gói tin**. Vì vậy nó **vô dụng** với chặn theo IP.

---

## 2. Bốn kiểu chặn — và cái nào Zapret không giải được

Đây là phần quan trọng nhất khi chẩn đoán.

### 2.1 Chặn theo IP

Zapret **bất lực**. Nó sửa nội dung gói, không sửa địa chỉ đích.
→ Cần **VPN hoặc proxy**, hoặc sửa `/etc/hosts`.

### 2.2 Chặn theo cổng

Dạng riêng của chặn mạng: **kết nối TCP tới cổng đó không bao giờ thiết lập được** —
SYN bị vứt, bắt tay (handshake) không bắt đầu.

Mọi kỹ thuật desync của Zapret thao túng gói **bên trong** kết nối đang
thiết lập hoặc đã thiết lập. **Kết nối không bắt đầu thì không có gì để can
thiệp.**

Cổng có thể "connect được" mà **không ổn định** — lúc được lúc không — đó vẫn là
chặn mức IP/cổng, chỉ là không phải lúc nào cũng kích hoạt.

**Cách kiểm tra:**

```bash
curl -v https://domain        # hoặc
telnet domain 443             # treo ở bước connect
```

> **bolvan (tác giả zapret), ntc.party, 08/2026:**
> *«Mогу сказать только одно. Если не коннектит на порт, то это полностью и окончательно
> "приехали". Оно может нестабильно конектить на порт. То да, то нет.»*

### 2.3 Chặn theo DPI (phân tích nội dung)

**Đúng việc của Zapret.** Chia gói (`ipfrag`), bẻ ClientHello (`multisplit`), gửi
gói giả (`fake`), và các kỹ thuật khác.

### 2.4 Trottling (giảm tốc)

Thay vì chặn hẳn, ISP **hạ tốc** với các mẫu traffic đáng ngờ. Zapret "chạy được"
nhưng tốc độ không dùng được. Khó phát hiện hơn chặn hẳn.

### Thứ tự chẩn đoán

```
Không mở được?
├─ Kết nối TCP không dựng lên?  → chặn IP/cổng → Zapret vô dụng, cần VPN/proxy
├─ Kết nối dựng được nhưng treo?
│  ├─ Có chặn theo nội dung (DPI) → Zapret dùng được
│  └─ Chỉ chậm → trottling
└─ Mở được nhưng chức năng hỏng? → nhiều domain, hoặc tương thích (xem mục 6)
```

---

## 3. Sáu nguyên nhân "không ăn"

### 3.1 Hạ tầng chặn không đồng nhất

Thiết bị ТСПУ khác nhau ở từng vùng: một nơi thiết bị cũ chỉ cần phân mảnh đơn giản,
nơi khác thiết bị mới ghép lại được mảnh và phân tích sâu TLS handshake.

Ngoài ra **lọc có thể xảy ra nhiều tầng**: ở ISP của bạn, ở hạ tầng trục, hoặc cả
hai. Chiến lược vượt được tầng này có thể không qua tầng kia.

### 3.2 Xung đột với môi trường cục bộ

| Nguồn xung đột | Giải thích |
|:--|:--|
| **Antivirus / firewall** | Thấy chương trình bắt và sửa gói mạng → coi là mối đe dọa → chặn. **Phải thêm exception.** |
| **VPN client khác** | Tạo bảng định tuyến riêng, có thể lách traffic khỏi Zapret hoặc xung đột ở tầng network stack |
| **DoH / DoT trong trình duyệt hoặc OS** | DNS mã hoá đi thẳng ra ngoài. Có thể **giúp** (ISP không thấy DNS) hoặc **hại** (zapret ở chế độ tpws không biết IP đích thật) |
| **DNS của router** | Router cưỡng ép cấp DNS của ISP → xung đột với cấu hình Zapret, DNS bị thay **trước khi** Zapret kịp can thiệp |

### 3.3 Trang web hiện đại quá phức tạp

Một trang tải tài nguyên từ **hàng chục domain** (CDN, phân tích, font, API). Zapret
có thể vượt được domain chính, nhưng nếu **tài nguyên quan trọng** đến từ domain
khác cũng bị lọc → trang hiển thị sai hoặc không tải.

### 3.4 Cả chuỗi, thiếu mắt xích là hỏng

```
Trình duyệt → OS → Antivirus → zapret → Router → ISP → Trục → Máy chủ
```

Hỏng hay xung đột ở bất kỳ mắt xích nào thì cả sơ đồ hỏng. Đây là lý do **cùng
một chiến lược cho kết quả khác nhau ở hai người cùng ISP cùng thành phố**.

---

## 4. Tìm hiểu vì sao không ăn

### Bước 0 — Tự loại trừ trước

Nếu trang **vốn vẫn chạy được** mà giờ hỏng khi bật Zapret, thì không phải chặn mà
là **hỏng do chính Zapret**: gói giả tới tận máy chủ thật, máy chủ coi là rác
(tương tự DDoS) và reset. Trường hợp này cần **loại trừ** (chiến lược `pass`),
không phải đánh lừa.

### Bước 1 — Kiểm bằng `curl -v`

Ví dụ **bình thường** (đã tới máy chủ, nhận HTTP 302):

```
* Host porno365.sexy:80 was resolved.
* IPv4: 5.196.61.237
*   Trying 5.196.61.237:80...
* Connected to porno365.sexy (5.196.61.237) port 80
> GET / HTTP/1.1
> Host: porno365.sexy
* Request completely sent off
< HTTP/1.1 302 Found
< Server: Apache
< Location: https://my.porno365x.link/
* Connection #0 to host porno365.sexy left intact
```

Các dấu hiệu phân biệt:

| Dòng | Nghĩa |
|:--|:--|
| `* Host ... was resolved` | DNS phía bạn đã phân giải được |
| `* Connected to ... port N` | **TCP đã bắt tay xong** → không phải chặn cổng/IP |
| `* Request completely sent off` | Yêu cầu đã ra hết khỏi máy |
| `< HTTP/1.1 ...` | Máy chủ đã **trả lời** → đường đi hai chiều tốt |
| `* Connection #0 left intact` | Kết nối đóng sạch |

Nếu lệnh **treo sau `Trying ...`** → chặn cổng/IP → đổi chiến lược vô ích.

### Bước 2 — Tắt mọi VPN và proxy

Cả VPN lẫn proxy của Windows có thể làm hỏng toàn bộ Zapret.

### Bước 3 — Tắt tiện ích mở rộng gây nhiễu

Các tiện ích **gây nhiễu, không liên quan gì tới site**: **SaveFrom**, **Юбуст**,
**Adblock**, **Антизапрет**, **AdGuard**.

Đặc biệt: **AdGuard chặn kết nối âm thanh của Discord** khi Zapret đang chạy.

### Bước 4 — Bỏ Yandex DNS / Yandex Browser

> ⚠️ **Yandex DNS đã ngừng mở được Discord** và các site bị chặn khác.
> Khuyến nghị chuyển sang **Google DNS** hoặc **Quad9 DNS**.

Yandex Browser **không được khuyến nghị**: nó tự thay DNS, tự chặn YouTube bằng cơ
chế riêng, và cài sẵn tiện ích mở rộng gây nhiễu.

### Bước 5 — Blockcheck (bước cuối)

Khi **không còn chiến lược nào trong sẵn có** mà chạy:

1. Tạo thư mục `blockcheck`
2. Giải nén toàn bộ archive lên desktop
3. Vào thư mục `blockcheck`
4. Chạy `blockcheck.cmd`
5. **Chờ ~1 giờ. KHÔNG đóng cửa sổ** — không thì phải làm lại từ đầu
6. Gửi `blockcheck.log` vào nhóm Telegram

> ⚠️ **Chiến lược `wssize` nằm cuối log — đừng lấy bừa.**
> Ở chế độ standard, blockcheck chỉ thử `wssize` cho TLS 1.2 và **chỉ khi** toàn
> bộ phần thử không `wssize` mà không tìm được gì. Ở chế độ force thì chạy lại cả
> danh sách kèm `wssize`. Cả hai trường hợp, chúng đều ở **cuối** `blockcheck.log`.
>
> `wssize` **làm chậm mọi kết nối** trên các cổng bị lọc và **không làm việc được
> với hostlist**. Nếu trong log có chiến lược chạy được **không** kèm `wssize` —
> lấy cái đó.

### Bước 6 — Thử rộng hơn

1. Kiểm tra bản cập nhật (chức năng kiểm tra update từng hỏng vì server bị DDoS)
2. Thử chiến lược **"Alt 2"**
3. Thử trên **chế độ chạy trực tiếp** (direct launch), tắt **hết** tab rồi bật
   **đúng một** tab có tên site cần sửa
4. Thử bản **dev**
5. Chạy Blockcheck
6. Thử **ByeByeDPI** (có cả Windows và Android; nhóm của họ có chiến lược do người
   dùng đóng góp)

---

## 5. Danh sách: hostlist, ipset, hosts

### 5.1 `--hostlist` — lọc theo tên miền

```
blocked-site.com
another-blocked-site.org
example.net
ru                       ← toàn bộ vùng *.ru
^onlyThisSite.com       ← CHỈ đúng domain này, không gồm subdomain
```

**Cơ chế:** `nfqws` nhìn tên site từ header `Host:` (HTTP) hoặc SNI (TLS ClientHello).
Nếu tên đó có trong danh sách → áp mọi thủ thuật của profile. Không có → bỏ qua.

**Mặc định bao gồm subdomain.** Có `example.com` thì `mail.example.com` và
`www.example.com` cũng được xử lý. Muốn **chỉ** domain gốc thì viết `^example.com`.

**Tính năng khác:**

- Danh sách đọc lúc khởi động, lưu **cấu trúc phân cấp** trong bộ nhớ để tra
  nhanh; khi mtime tệp đổi thì **tự đọc lại** khi cần
- Hỗ trợ **gzip**, tự nhận ra định dạng
- Được chỉ định **nhiều lần**
- Danh sách tổng rỗng = coi như không có

```bash
--hostlist=/path/to/domains.txt
--hostlist=list1.txt --hostlist=list2.txt.gz
--hostlist-domains=youtube.com,google.com   # liệt kê trực tiếp, # để chú thích
--hostlist-exclude=/path/to/exclude.txt     # danh sách loại trừ
--hostlist-exclude-domains=local.domain,internal.net
```

#### `--hostlist-auto` — tự phát hiện chặn

| Cờ | Mặc định | Ý nghĩa |
|:--|:--|:--|
| `--hostlist-auto=<file>` | — | Tự phát hiện chặn DPI và điền domain vào danh sách. **Cần chuyển hướng traffic vào** |
| `--hostlist-auto-fail-threshold=<int>` | 3 | Số lần phải thấy dấu hiệu giống chặn |
| `--hostlist-auto-fail-time=<int>` | 60 | Khung thời gian (giây) cho các lần đó |
| `--hostlist-auto-retrans-threshold=<int>` | 3 | Số retransmit coi là chặn |
| `--hostlist-auto-debug=<logfile>` | — | Log quyết định để hiểu vì sao host vào danh sách |

### 5.2 `--ipset` — lọc theo IP

Mỗi dòng là một IP hoặc CIDR (v4 hoặc v6). Nhiều danh sách, hỗ trợ gzip, tự đọc
lại.

```bash
--ipset=/path/to/ips.txt
--ipset-ip=1.2.3.4,10.0.0.0/8      # liệt kê trực tiếp, # để chú thích
--ipset-exclude=/path/to/excl.txt
--ipset-exclude-ip=192.168.0.0/16
```

Wiki có sẵn `ipset-ovh.txt` — danh sách subnet OVH.

### 5.3 File `hosts` — chặn GEO, KHÁC hẳn chặn Роскомнадзор

Đây là điểm hay bị nhầm:

> **Chặn GEO không phải chặn RKN.** Trang web **đã chạy được ở Nga** — nó **tự**
> không muốn nối tới người ở nước bị trừng phạt. Zapret **vô dụng** ở đây: không có
> gì để "vượt", vì nó không bị chặn. Zapret không đổi vị trí nên không làm được.

Cơ chế tab `hosts`: chương trình hỏi địa chỉ site từ **DNS công cộng** do bạn chọn,
rồi chèn IP đó vào file hosts. Chỉ cần DNS trả lời là xong.

#### Vì sao từ cuối tháng 8/2026 hỏng

Chuỗi bị đứt ở **ngay bước đầu tiên**, vì hai nguyên nhân cộng lại:

1. **Kết nối tới server DNS mã hoá bị đứt theo tên server.** Được chặn:
   `dns.google`, `cloudflare-dns.com`, `dns.adguard.com`, `dns.quad9.net` — đúng
   những cái hay nằm trong danh sách này.
2. **Truy vấn DNS thường (không mã hoá) tới `8.8.8.8` và `1.1.1.1` bị bắt và đưa về
   resolver nhà nước**, vốn trả "tên miền không tồn tại" cho domain bị chặn.

> Chương trình **không hỏng** — đơn giản là **không còn chỗ nào để lấy địa chỉ**.
> Đổi provider trong danh sách chỉ giúp được khi danh sách còn **một** cái chạy.

#### Chẩn đoán trong nửa phút

```bash
nslookup chatgpt.com 8.8.8.8        # qua UDP
nslookup -vc chatgpt.com 8.8.8.8     # qua TCP
```

| UDP | TCP | Kết luận |
|:--|:--|:--|
| "Non-existent domain" | Có địa chỉ | Truy vấn DNS thường **đang bị thay** |
| Hỏng | Hỏng | Không tới được resolver nào cả |

Trên Linux/macOS dùng `dig +tcp +short chatgpt.com @8.8.8.8`.

#### Tự điền tay

Nguồn địa chỉ thật:

- [ ] truy vấn qua TCP (`dig +tcp +short … @8.8.8.8`)
- [ ] khi **bật VPN hoặc proxy** → truy vấn đi qua đường hầm, không bị bóp méo
- [ ] từ bất kỳ máy chủ nước ngoài nào bạn truy cập được
- [ ] qua dịch vụ kiểm tra DNS trên web — nhưng nhớ rằng bạn **trao địa chỉ cho
      site lạ**, mà `hosts` lại **tắt** mọi kiểm tra sau đó

Ghi vào `C:\Windows\System32\drivers\etc\hosts` (mở Notepad **quyền admin**) hoặc
`/etc/hosts` (Linux/macOS):

```
104.18.32.47 chatgpt.com
104.18.32.47 chat.openai.com
```

Sau đó xoá cache DNS (`ipconfig /flushdns` / `resolvectl flush-caches`) và mở lại
trình duyệt. Kiểm tra bằng `ping chatgpt.com`.

#### File hosts **không** làm được gì

- **Không hiểu mask**: dòng `*.openai.com` **không hoạt động**, từng subdomain phải
  ghi riêng
- Địa chỉ dịch vụ lớn **đổi theo thời gian**, bản ghi sẽ phải cập nhật
- Chỉ giải quyết câu hỏi **"địa chỉ là gì"** → vô dụng với chặn theo tên miền trong
  TLS handshake (chặn xảy ra **sau khi** đã có địa chỉ) — trường hợp đó cần Zapret

> ⚠️ **Ghi đúng mà site vẫn không mở? Kiểm tra "DNS an toàn" của trình duyệt.**
> `hosts` do **resolver hệ thống** đọc. Trình duyệt bật DNS mã hoá (Chrome/Edge:
> "Dùng DNS bảo mật"; Firefox: "DNS qua HTTPS") sẽ **tự phân giải** và bỏ qua cả
> `hosts`. Với Firefox đây là đặc điểm lâu đã được mô tả của chế độ TRR
> (Mozilla [#1624112](https://bugzilla.mozilla.org/show_bug.cgi?id=1624112),
> [#1511643](https://bugzilla.mozilla.org/show_bug.cgi?id=1511643)), né bằng cách tắt
> chế độ hoặc dùng `network.trr.excluded-domains`. DoH ở mức **hệ thống** (Windows
> 11, `systemd-resolved`) **không** gây vướng.

### 5.4 Zapret có vượt được DoH bị chặn không?

| Bị chặn theo | Kết quả |
|:--|:--|
| **Tên miền** (ISP thấy bạn đi tới resolver nào) | ✅ **Zapret giúp được** — thêm domain của resolver vào hostlist, các chiến lược thường chạy |
| **Địa chỉ** (kết nối không dựng lên) | ❌ **Bất lực** — chỉ đổi địa chỉ resolver được, đổi chiến lược vô ích |

Và Zapret **không thể giấu trọn** việc bạn dùng DoH.

---

## 6. Discord — quy trình sửa nhiều tầng

Discord cần **nhiều hạng mục** cùng lúc. Thứ tự thực hiện rất quan trọng:

1. **Tắt chiến lược ở TẤT CẢ hạng mục** — dễ xung đột
2. **Sửa `discord.com` trước** — ứng dụng không thể chạy nếu site không chạy.
   Có thể đổi số gói xử lý (thường `3`–`4`, đến `10`–`20`)
3. **Nếu lỗi "Checking for updates"** → tải tay bản cập nhật, hoặc dùng hạng mục
   `updates.discord.com`. **Đổi chiến lược là khởi động lại ứng dụng hoàn toàn**,
   kể cả không còn trong tray
4. **Màn hình đen sau khi mở** — thường chỉ cần **khởi động lại ứng dụng**
5. **Lỗi "Подключение" trong voice** → dò hạng mục `discord.media` cho tới khi hết
   lỗi RTC. **Thoát khỏi cuộc gọi bằng tay** trước khi chọn chiến lược mới
6. **Có lỗi RTC** → dò hạng mục "Giọng điện". Bật **Discord Voice** trong hosts
7. **Voice vẫn không được** → kiểm tra hạng mục **"IPset TCP (Cloudflare)"**
8. **Lỗi ping 5000** → đổi vùng máy chủ voice channel

---

## 7. Cài đặt trên Linux

Wiki liệt kê 5 cách.

### 1. `zapret-linux-easy` (ImMALWARE)

```bash
git clone https://github.com/ImMALWARE/zapret-linux-easy && cd zapret-linux-easy
./install.sh
```

Cần có sẵn: `curl` + `iptables` + `ipset` (cho `FWTYPE=iptables`) **hoặc**
`curl` + `nftables` (cho `FWTYPE=nftables`).

### 2. `zapret-discord-youtube-linux` (Sergeydigl3)

Bộ chuyển đổi để chạy các cấu hình vượt chậm YouTube kiểu Flowseal trên Linux.

```bash
git clone https://github.com/Sergeydigl3/zapret-discord-youtube-linux.git
cd zapret-discord-youtube-linux
sudo bash main_script.sh
```

Cho chọn chiến lược từ các file `.bat` (`general.bat`, `general_mgts2.bat`,
`general_alt5.bat`…) và chọn giao diện mạng.

Lưu câu trả lời vào `conf.env` để chạy không tương tác:

```bash
sudo bash main_script.sh -nointeractive
```

```bash
# conf.env
strategy=general.bat
auto_update=false
interface=enp0s3
```

Xem danh sách giao diện: `ls /sys/class/net`

> ⚠️ Chỉ chạy với **nftables**. Khi dừng script, **mọi rule firewall đã thêm bị xoá**
> và tiến trình `nfqws` nền bị dừng.
> **Nếu bạn có rule nftables tuỳ chỉnh, hãy sao lưu** — script có thể xoá chúng.

### 3. `zapret.installer` (Snowy-Fluffy)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Snowy-Fluffy/zapret.installer/refs/heads/main/installer.sh)"
zapret      # mở bảng điều khiển
```

Cài zapret từ repo chính thức + CLI panel + kho cấu hình.

### 4. `zapret-discord-youtube` (kartavkun)

```bash
bash <(curl -s https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/setup.sh)
```

Tự nhận diện distro, cài phụ thuộc (`wget`, `git`), tải bản mới nhất từ repo
chính thức, cấu hình, cho chọn cấu hình.

### Nền tảng khác

| Nền tảng | Cách |
|:--|:--|
| **Router** | Xem `Zapret/router` — chạy trực tiếp trên router |
| **Android** | Module Magisk (`zapret2`, `zaprett`), ByeByeDPI (không cần root), DNS cho ChatGPT, biến thể Android TV |
| **Windows** | Zapret GUI / file `.bat` |

---

## 8. Tra cứu nhanh: `nfqws` → `nfqws2`

Đây là bảng chuyển để đọc cấu hình Zapret 1 rồi hiểu tương ứng ở Zapret 2.

| `nfqws` (Zapret 1) | `nfqws2` (Zapret 2) |
|:--|:--|
| `--dpi-desync=fake` | `--lua-desync=fake:blob=fake_default_tls` |
| `--dpi-desync=multisplit` | `--lua-desync=multisplit:pos=...` |
| `--dpi-desync=multidisorder` | `--lua-desync=multidisorder:pos=...` |
| `--dpi-desync=fakedsplit` | `--lua-desync=fakedsplit:pos=...` |
| `--dpi-desync=fakeddisorder` | `--lua-desync=fakeddisorder:pos=...` |
| `--dpi-desync=hostfakesplit` | `--lua-desync=hostfakesplit:host=...` |
| `--dpi-desync=syndata` | `--lua-desync=syndata` |
| `--dpi-desync=udplen` | `--lua-desync=udplen` |
| `--dpi-desync=tamper` | `dht_dn` / `pktmod` |
| `--dpi-desync=rst` / `rstack` | `--lua-desync=rst` |
| `--dpi-desync=ipfrag1` / `ipfrag2` | `ipfrag` + `ipfrag_pos_tcp/udp` |
| `--dpi-desync-fooling=md5sig` | `fool=tcp_md5` |
| `--dpi-desync-fooling=badseq` | `fool=tcp_seq=-10000` hoặc `tcp_ack=-66000` |
| `--dpi-desync-fooling=badsum` | `fool=badsum` |
| `--dpi-desync-fooling=datanoack` | `fool=tcp_flags_unset=ACK` |
| `--dpi-desync-fooling=ts` | `fool=tcp_ts=-600000` |
| `--dpi-desync-split-pos=<marker>` | `pos=<marker>` |
| `--dpi-desync-split-seqovl=<N>` | `seqovl=<N>` |
| `--dpi-desync-fake-tls-mod=<list>` | `tls_mod=<list>` |
| `--dpi-desync-start` / `--dpi-desync-cutoff` | `--out-range` |
| `--orig-*` | `dir=in` + `pktmod` |
| `--dup-*` | `repeats`, `fake` |
| `--wssize` + `--wssize-cutoff` | `--lua-desync=wssize` |
| `--wsize` | `--lua-desync=wsize` |
| `--hostcase` / `--domcase` | `--lua-desync=http_hostcase` / `http_domcase` |
| `--methodeol` | `--lua-desync=http_methodeol` |
| `--synack-split` | `synack_split` |
| `--filter-l7=<proto>` | `--filter-l7=<proto>` |
| `--hostlist` / `--ipset` | `--hostlist` / `--ipset` |
| `--new` | `--new` |

### Bảng tham chiếu đầy đủ

Tra cứu nhanh nhất:

```bash
# toàn bộ danh sách --help của bản bạn đang chạy
nfqws --help
```

Bộ cờ của `nfqws` v72.2 rất lớn. Nhóm chính:

| Nhóm | Cờ tiêu biểu |
|:--|:--|
| **Cấu hình** | `@<file>` (phải là cờ **đầu tiên**), `--debug`, `--dry-run`, `--version`, `--daemon`, `--pidfile`, `--user`, `--uid`, `--qnum` |
| **Hệ thống** | `--bind-fix4/6`, `--ctrack-timeouts=S:E:F[:U]` (mặc định `60:300:60:60`), `--ctrack-disable`, `--ipcache-lifetime`, `--ipcache-hostname` |
| **Sửa gói gốc** | `--orig-ttl`, `--orig-ttl6`, `--orig-autottl`, `--orig-tcp-flags-set/unset`, `--orig-mod-start/cutoff` |
| **Bản sao gói** | `--dup`, `--dup-replace`, `--dup-ttl`, `--dup-fooling`, `--dup-ts-increment`, `--dup-badseq-increment`, `--dup-badack-increment`, `--dup-ip-id`, `--dup-start/cutoff` |
| **DPI desync** | `--dpi-desync`, `--dpi-desync-fooling`, `--dpi-desync-split-pos`, `--dpi-desync-split-seqovl`, `--dpi-desync-fakedsplit-pattern`, `--dpi-desync-hostfakesplit-midhost`, `--dpi-desync-repeats`, `--dpi-desync-skip-nosni`, `--dpi-desync-any-protocol`, `--dpi-desync-fwmark`, `--dpi-desync-start/cutoff` |
| **Fake payload** | `--dpi-desync-fake-{http,tls,quic,wireguard,dht,discord,stun,syndata,unknown,unknown-udp}` |
| **Sửa header** | `--hostcase`, `--hostnospace`, `--methodeol`, `--hostspell`, `--domcase` |
| **Window size** | `--wsize`, `--wssize`, `--wssize-cutoff`, `--wssize-forced-cutoff` |
| **Lọc** | `--filter-l3/tcp/udp/l7/ssid`, `--hostlist*`, `--ipset*`, `--new`, `--skip` |

### Cú pháp quan trọng

| Mẫu | Nghĩa |
|:--|:--|
| `[n\|d\|s]N` | `n` = số gói · `d` = gói dữ liệu · `s` = sequence number |
| `marker±N` | Vị trí tương đối tính từ marker |
| `[+ofs]@file\|0xHEX` | Dữ liệu từ tệp (có offset) hoặc chuỗi hex |
| `#` đầu dòng | Chú thích (bỏ qua) |

**Marker cho cắt TCP:**

`method` · `host` · `endhost` · `sld` · `endsld` · `midsld` · `sniext`

**Cờ TCP (12 bit):**

Chuẩn: `FIN, SYN, RST, PSH, ACK, URG, ECE, CWR` — Dự trữ: `AE, R1, R2, R3`

### Mặc định đáng nhớ

| Cờ | Mặc định |
|:--|:--|
| `--dpi-desync-fooling-fwmark` | `0x40000000` |
| `--dpi-desync-autottl` | `1:3-20` |
| `--orig-autottl` | `+5:3-64` |
| `--dup-autottl` | `+1:3-64` |
| `--dup-ts-increment` | `-600000` |
| `--dup-badseq-increment` | `-10000` |
| `--dup-badack-increment` | `-66000` |
| `--dpi-desync-skip-nosni` | `1` (bỏ qua ESNI) |
| `--dpi-desync-any-protocol` | `0` (**chỉ** HTTP request và TLS ClientHello) |
| `--wssize-forced-cutoff` | `1` |

> ⚠️ **`--dpi-desync-any-protocol=0` là mặc định** — nghĩa là desync **chỉ** áp cho
> HTTP và TLS. Muốn áp cho **mọi** gói TCP phải bật `=1`.

---

## 9. Những trang khác trong namespace Zapret

### Bài hướng dẫn cụ thể theo tình huống

| Trang | Chủ đề |
|:--|:--|
| `discord` | Vượt Discord qua Zapret 2, theo hạng mục |
| `youtube`, `youtubeblockinrussia` | Vượt YouTube |
| `telegram calls` | Vượt cuộc gọi Telegram |
| `steam`, `League of Legends`, `Battlefield 6`, `Ubisoft`, `Blockcheck` | Game cụ thể |
| `wssize` | Khi nào dùng `--wssize` (và tại sao thường **không** nên) |
| `--wf-raw-part` | Raw filter WinDivert nội bộ |
| `Zapret flags`, `Zapret v72.2` | Tra cứu cờ |
| `about`, `home`, `download` | Tổng quan, tải về |
| `changelog-21.0.0-dev-june-2026` | Changelog ZapretGUI 21.0.0.6 → 21.0.0.181 |

### Cộng đồng và nguồn

| Nguồn | Nội dung |
|:--|:--|
| `Zapret ссылки`, `ZapretTeam`, `Test`, `LordSlon` | Kênh Telegram, thảo luận GitHub, `ipset-ovh` |
| `YTDisBystro_v3.5`, `DiscordFix_5.1.7`, `Dronator 4.2`, `Launcher zapret 2.9.1`, `Zapret GUI` | Bộ file `.bat` sẵn dùng cho `winws.exe` |
| `flowseal-zapret-discord-youtube-block-july-2026` | GitHub đình chỉ tài khoản Flowseal 10/07/2026 — **vì sao Zapret KHÔNG phải virus** |
| `virus` (namespace riêng) | Antivirus báo động: WinDivert, cách phân biệt đồ giả |
| `premium` (namespace riêng) | Zapret Premium, VPN trả phí |

### Sự kiện đáng chú ý

**10/07/2026 — GitHub đình chỉ tài khoản Flowseal** và repo
`zapret-discord-youtube` (cộng "shadow ban" tài khoản).

Wiki có hai bài phân tích chi tiết. Kết luận quan trọng: có tin đồn cho rằng nguyên nhân
là file `.bat` giả có **trojan SalatStealer**. **Zapret không phải virus** — và đó là
lý do bài `virus` tồn tại.