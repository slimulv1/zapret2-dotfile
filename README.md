# zapret2-dotfile

Ba tầng chặn lọc trên CachyOS / Arch: **NextDNS** quyết định trang nào bị chặn,
**zapret2** chống bị chặn nhầm, **ufw** chặn thứ lọt vào máy.

## Vấn đề

Ở Việt Nam, phần lớn trang bị chặn đều bị chặn **theo tên miền**, chứ không phải
theo địa chỉ IP. Bạn vẫn vào được IP đó từ máy bất kỳ, chỉ cần gõ đúng địa chỉ —
không có quy tắc nào ở tầng đường truyền chặn được. Nói cách khác, chỗ duy nhất
quyết định cho đi hay chặn là chỗ hỏi tên miền.

Hệ thống này gom mọi câu hỏi tên miền về đúng một chỗ, rồi để chỗ đó quyết định.
Phần nào nằm trong máy thì script lo hết. Riêng danh sách chặn thì nằm trên
đám mây NextDNS, nên bạn phải tự bật ở đó.

```
┌─────────────────────────────────── MÁY CỦA BẠN ────────────────────────────────────┐
│                                                                                    │
│  KHI BẠN MỞ MỘT TRANG WEB                                                          │
│                                                                                    │
│  [1]  TẦNG 2 · NextDNS qua DoT                                                     │
│      Hỏi tên miền ở cổng 853. NextDNS trả về IP thật, hoặc chặn tuỳ                │
│      danh sách nằm trên đám mây của bạn.                                           │
│                                                                                    │
│      << ĐÂY LÀ CHỖ DUY NHẤT QUYẾT ĐỊNH CHẶN.                                       │
│      Danh sách chặn nằm trên đám mây chứ không nằm trong máy,                      │
│      nên phần cài đặt bên dưới chỉ kiểm được, không bật được.                      │
│                                                                                    │
│  [2]  TẦNG 1 · zapret2 · desync                                                    │
│      Mở kết nối tới IP vừa nhận được. Cắt gói đầu của kết nối                      │
│      HTTPS thành hai đoạn, đoạn đầu chỉ mang 1 byte. Bộ lọc của                    │
│      nhà mạng cần nguyên gói đó để đọc tên miền, nên không khớp                    │
│      mẫu nào và cho qua.                                                           │
│                                                                                    │
│      Tầng này không chặn gì cả — nó chỉ chống bị chặn. Nếu tên                     │
│      miền bị chặn ở bước [1] thì không có kết nối nào để mà sửa                    │
│      ở bước [2].                                                                   │
│                                                                                    │
│  KHI CÓ AI GỌI TỚI MÁY BẠN                                                         │
│                                                                                    │
│  [3]  TẦNG 3 · ufw · chặn INPUT                                                    │
│      Chặn mọi thứ đi vào máy, trừ KDE Connect trong mạng LAN.                      │
│                                                                                    │
│  LUÔN LUÔN BẬT, MỌI LÚC MỞ MÁY                                                     │
│                                                                                    │
│  [4]  TẦNG 2b · ufw · tường chặn DNS                                               │
│      Chỉ cho phép hỏi NextDNS ở cổng 53 và 853, chặn mọi nơi hỏi                   │
│      DNS khác — cả IPv4 lẫn IPv6.                                                  │
└────────────────────────────────────────────────────────────────────────────────────┘
```

Điều dễ hiểu nhất về sơ đồ này: **tầng 1 không phải là thứ cứu truy cập.** Nó
sửa gói tin, chứ không tạo ra gói tin. Tên miền bị chặn ở bước [1] thì ở bước
[2] không có kết nối nào để mà sửa cả. Nên hãy hiểu tầng 1 là lưới an toàn.

## Đo được

**Tầng 1 thật sự cắt gói.** Đo bằng cách nhìn gói tin thật trên cáp, tách theo
từng kết nối, rồi đo chiều dài đoạn TCP đầu tiên:

| | đoạn đầu của 5 kết nối tới cổng 443 |
|---|---|
| tầng 1 bật | `[1, 1, 1, 1, 1]` byte |
| tầng 1 tắt | `[1570, 1570, 1570, 1571, 1573]` byte |

**Chặn thật ra nằm ở tầng 2, và là chặn kiểu DNS chứ không phải DPI.** Ví dụ
`viet69.be` và `erothots.co` bị NextDNS chặn. Ép thẳng IP của chúng, giữ nguyên
phần định danh bảo mật, thì cả hai trả về `HTTP 200`, tức là nhà mạng không chặn
gì cả. Bật hay tắt tầng 1 thì kết quả y hệt.

Hai trang đó không nằm trong danh sách chặn thủ công. NextDNS trả về
`Blocked by NextDNS: ai-threat-detection` và `threat-intelligence-feeds`, tức là do
hai công tắc `aiThreatDetection` và `threatIntelligenceFeeds` đang bật trên đám
mây. Đây là lý do một số trang bị chặn dù không hề có trong danh sách.

**Tầng 1 có giới hạn.** Nó chỉ xử lý cổng 80 và 443, và bỏ qua 9 dải IP nội bộ
(loopback, LAN, CGNAT, link-local).

## Cần ID hay API key?

**Chỉ cần ID.** Đó là thứ duy nhất nằm trong cấu hình máy, dạng
`45.90.28.0#<ID>.dns.nextdns.io`. Không có API key thì hệ thống chạy y hệt, chỉ
mất phần kiểm tra.

API key chỉ để **đọc**. Nó giúp script hỏi NextDNS xem ID bạn đưa có thật không,
và đọc xem profile đang có bao nhiêu mục chặn / cho qua. Không có key thì script
nói thẳng là không kiểm được chứ không im lặng coi như đã kiểm — vì ID sai không
gây ra lỗi nào cả, NextDNS chỉ trả lời bằng profile mặc định của họ, nên máy vẫn
thông mạng mà không lọc gì.

Một chi tiết đáng biết: **key tự lộ ra ID**. Gọi `GET /profiles` với key là ra
danh sách profile kèm ID, nên nếu lỡ quên ID mà vẫn còn key thì vẫn tìm lại được.

## Cài từ máy trắng

Giả định bạn mới cài Arch hoặc CachyOS, chưa có zapret2, chưa có NextDNS, chưa có
gì cả. Ba bước, theo đúng thứ tự.

### Bước 1 — Tạo profile NextDNS

Làm trước khi cài gì cả, vì bạn cần lấy ID ở đây.

1. Vào <https://my.nextdns.io>, đăng ký nếu chưa có, tạo một profile.
2. Trong profile mới, bật hai công tắc này: **Threat Intelligence Feeds** và
   **AI Threat Detection**. Hai cái này quyết định gần như hết kết quả — tắt đi
   thì phần lớn chặn biến mất.
3. Lấy **Profile ID**: <https://my.nextdns.io> → Settings → General. Đó là 6 ký
   tự hex, ví dụ `785fad`.

ID này là thứ **duy nhất** bạn cần để hệ thống chạy. Xem mục
[Cần ID hay API key?](#cần-id-hay-api-key).

### Bước 2 — Cài repo

```bash
sudo pacman -S --needed git        # chỉ cần git; phần còn lại script tự cài
git clone https://github.com/slimulv1/zapret2-dotfile.git
cd zapret2-dotfile
```

### Bước 3 — Chạy installer

Xem trước đã, không sửa gì:

```bash
sudo bash install.sh --nd-id 785fad --dry
```

Đọc hết 9 bước, thấy `XEM XONG` rồi hãy chạy thật:

```bash
sudo bash install.sh --nd-id 785fad
```

Script tự làm hết phần còn lại:

| việc | chi tiết |
|---|---|
| cài gói còn thiếu | `nftables` `ufw` `networkmanager` `procps-ng` `iproute2` `git` `make` `gcc`, rồi 5 thư viện lúc chạy: `libnetfilter_queue` `libnfnetlink` `libmnl` `luajit` `zlib` |
| dựng tầng 1 | clone zapret2 ở tag `v1.0.5.2` rồi `make systemd` ra `nfq2/nfqws2` |
| đặt tầng 2 | ghi `resolved.conf`, tắt DNS của router trên mọi profile, trỏ `resolv.conf` vào stub |
| đặt tầng 2b + 3 | 20 dòng rule ufw: 8 ALLOW + 8 DENY cho DNS, 4 cho KDE Connect |
| chọn đường mặc định | đặt metric cáp `100`, wifi `50000` — xem [mục bên dưới](#đường-mặc-định-cáp-trước-wifi-chỉ-dự-phòng) |
| siết cứng | 18 khoá sysctl qua 3 lớp phòng thủ |

Trước khi sửa bất cứ thứ gì, script chụp trạng thái hiện tại vào
`/var/backups/zapret2-dotfile/`. Chỉ một bản, tên cố định, lần sau ghi đè.

Xong thì kiểm lại:

```bash
sudo bash test/t1-config.sh      # chỉ đọc — không sửa gì
```

Dòng cuối in ra `đạt N · LỆCH M` — N là số mục, M là số mục lệch. Bản này
không ghi N cứng trong tài liệu vì số mục thay đổi theo máy; cứ ghi thì sẽ
lệch, y như lần trước.

> **Một giới hạn cần biết:** toàn bộ phép thử cho tới nay chạy trên máy **đã
> có sẵn** zapret2, NextDNS, ufw — tức là installer được chạy lại, chưa từng
> chạy lần đầu trên máy trắng. Riêng bước build (`make systemd` → `sd_notify`)
> đã kiểm gián tiếp và ra đúng binary đang chạy, nhưng phần `pacman` tự cài
> gói, copy unit systemd, dựng 3 lớp sysctl trên máy sạch thì **chưa** có
> bằng chứng. Nếu bạn chạy lần đầu và gặp lỗi, đó là chỗ chưa kiểm — xem
> [mục 8.2 của NETWORK-DESIGN.md](docs/NETWORK-DESIGN.md) để biết cụ thể
> chưa có bằng chứng ở đâu.

### Nên làm thêm: API key để kiểm ID

Không có key thì hệ thống vẫn chạy, chỉ không biết ID bạn đưa có đúng không. Xem
mục [Về API key](#về-api-key) — đặt xong chạy lại installer một lần là có phần
kiểm.

### Lỡ mất mạng thì gỡ

```bash
sudo bash install.sh --uninstall
```

Gỡ 3 tầng, dừng zapret2, xoá 20 dòng rule ufw, rồi **khôi phục tệp cũ từ
backup** — có trong backup thì trả về, không có nghĩa là trước khi cài nó chưa
tồn tại nên xoá hẳn. Script tự báo đã xoá được bao nhiêu; nếu thiếu thì nó in
cảnh báo kèm lệnh để bạn kiểm tay.

## Hai việc còn lại, phải tự làm

Cả hai nằm ngoài máy. `install.sh` đọc được cái thứ nhất nhưng không bật được, vì
API key chỉ có quyền đọc.

**Bật cấu hình tầng 2 trên đám mây.** Đây là bước dễ bỏ nhất. Script sẽ in ra tên
profile, số mục chặn / cho qua, và cảnh báo nếu `aiThreatDetection` hoặc
`threatIntelligenceFeeds` đang tắt. Hai công tắc đó quyết định gần như hết kết
quả: tắt đi thì phần lớn chặn biến mất, còn danh sách chặn thủ công vẫn giữ
nguyên. Bật thì bạn phải tự làm ở <https://my.nextdns.io>.

Ranh giới của việc kiểm: `install.sh` bắt được đúng hai công tắc trên, vì đó là
thứ nó đọc được. Còn `test/t1-config.sh` chỉ kiểm **hình dạng** cấu hình, không
kiểm hành vi — ID sai, danh sách rỗng, hay NextDNS đổi ý bạn thì nó vẫn báo đạt.
Muốn biết chắc tầng 2 có thật sự lọc không, hỏi một tên miền bạn biết chắc là
profile của bạn đang chặn:

```bash
dig +short <tên miền đó>     # 0.0.0.0 là đúng · IP thật là đang hỏng
```

**Ghim DoH cho trình duyệt.** Tường DNS chặn cổng 53 và 853, nhưng DoH (DNS mã
hoá chạy trên HTTPS) lại dùng cổng 443, cùng cổng với web, nên không có cách nào
chặn riêng mà không chặn cả web. Để trình duyệt tự chọn provider thì nó đi vòng
khỏi NextDNS. Cách làm ở
[`docs/tinh-chinh-trinh-duyet.md`](docs/tinh-chinh-trinh-duyet.md).

## Đường mặc định: cáp trước, wifi chỉ dự phòng

`install.sh` tự làm phần này, không cần bạn gõ gì. Nhưng nên hiểu vì sao, phòng
khi sau này bạn tự đổi.

Khi cáp và wifi cùng mở, máy phải tự chọn lưu lượng đi đường nào. Cách Linux quyết
định rất đơn giản: mỗi đường mang một con số gọi là **metric**, và đường nào có
số nhỏ hơn sẽ thắng. Installer đặt cáp `100`, wifi `50000`.

Wifi trên máy này là hotspot điện thoại. NetworkManager liên tục thử xem mỗi
kết nối có ra được Internet thật không, rồi xếp hạng từng đường:

```
cáp   enp8s0   full      ra được Internet bình thường
wifi  wlan0    limited   bị hạn chế
```

Tài liệu NetworkManager nói rõ: kết nối không ở mức `full` sẽ bị **cộng thêm
20000** vào metric. Nên con số ta tự đặt chưa phải số thật:

| | đặt trong profile | metric thật trong bảng định tuyến |
|---|---|---|
| cáp | 100 | 100 |
| wifi | 50000 | 50000 **+ 20000** = 70000 |

Cáp thắng, và thắng rộng — lưu lượng của bạn đi đường cáp, đúng ý.

Khi cáp hỏng, route của cáp biến mất và wifi thành đường mặc định — không cần
làm gì thêm, Linux tự chuyển. Tôi đã kiểm: đặt metric cáp lên 100000 (cao hơn
wifi) thì `ip route get 1.1.1.1` trả về `dev wlan0`, tức lưu lượng thật sự đi
wifi. Đó là trường hợp xấu nhất, và wifi vẫn đứng ra gánh.

Chỗ dễ hiểu nhầm nhất là phần cộng 20000 đó. Nó **không** đến từ
`autoconnect-priority`. Có thể kiểm: nếu nó đến từ priority thì hạ priority của
wifi xuống sẽ thấy metric nhảy theo. Tôi đã đảo priority của hai profile theo cả
hai chiều — metric không nhúc nhích. Nó đến từ kết quả kiểm tra kết nối, và chỉ
biến mất khi NetworkManager xếp wifi lên `full`.

Nếu bạn muốn tự chỉnh:

```bash
nmcli connection modify "profile cáp"  ipv4.route-metric 100   ipv6.route-metric 100
nmcli connection modify "profile wifi" ipv4.route-metric 50000 ipv6.route-metric 50000
```

Đặt xong **phải reapply thì mới có hiệu lực**. Lệnh `modify` chỉ ghi vào profile,
còn route đang chạy thì không đổi — đây là chỗ hay tưởng đã xong trong khi chưa:

```bash
nmcli device reapply enp8s0
nmcli device reapply wlan0
ip -4 route show default
```

Số 100 và 50000 không có ý nghĩa gì đặc biệt — chỉ cần cách nhau đủ xa. Nếu mai
bạn đổi hotspot điện thoại thành WiFi nhà và nó lên `full`, phần cộng 20000 biến
mất, nhưng 50000 vẫn thua 100. Còn nếu để trống, NetworkManager tự chọn 600 cho
wifi (đo được 20600 = 600 + 20000), vẫn thua nhưng chỉ hơn có 600 — mong manh hơn
nhiều.

## Về API key

Key không nằm trong repo, và giờ nó còn cần hơn trước: không có key thì
`GET /profiles/<ID>` trả `403` cho **mọi** ID, kể cả ID thật, tức là không kiểm
được profile có tồn tại không.

Đặt ở `/root/.config/nextdns/api.key`, quyền 600:

```bash
sudo install -d -m 700 /root/.config/nextdns
sudo tee /root/.config/nextdns/api.key >/dev/null   # dán key, rồi Ctrl-D
sudo chmod 600 /root/.config/nextdns/api.key
```

Lấy key ở <https://my.nextdns.io> → Account → API.

Vì sao không để trong repo: key cho phép **sửa** danh sách chặn DNS, không chỉ đọc.
Mà repo private vẫn hiện với người được mời cộng tác, và chuyển sang public chỉ mất
vài giây. Nên key nằm ngoài repo, và cũng không nằm trong bất kỳ file cấu hình nào
trên máy — chỉ được đọc lúc chạy `install.sh`.

## Đọc thêm

| Tệp | Nội dung |
|---|---|
| [`docs/NETWORK-DESIGN.md`](docs/NETWORK-DESIGN.md) | Thiết kế chi tiết, kết quả đo, và những chỗ đã biết là chưa ổn |
| [`docs/NGUOI-SUA.md`](docs/NGUOI-SUA.md) | Bẫy cần tránh khi sửa script trong repo này |
| [`docs/tinh-chinh-trinh-duyet.md`](docs/tinh-chinh-trinh-duyet.md) | Ghim DoH cho Firefox và Chromium |
