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

## Cài

```bash
git clone https://github.com/slimulv1/zapret2-dotfile.git
cd zapret2-dotfile
sudo bash install.sh --nd-id ABC123 --dry     # xem trước, không sửa gì
sudo bash install.sh --nd-id ABC123           # cài thật
```

`--nd-id` là ID profile NextDNS, 6 ký tự hex, lấy ở
<https://my.nextdns.io> → Settings → General. Máy chưa có zapret2 thì script tự
cài luôn.

Muốn có phần kiểm tra ID thì đặt API key ở `/root/.config/nextdns/api.key`,
quyền 600 — cách đặt ở mục [Về API key](#về-api-key) bên dưới. Key ở chỗ khác thì
chỉ định bằng `--nd-key /đường/dẫn`.

Trước khi sửa gì, script chụp lại trạng thái hiện tại vào
`/var/backups/zapret2-dotfile/`. Chỉ một bản, tên cố định, lần sau ghi đè.

Kiểm lại bất cứ lúc nào:

```bash
sudo bash test/t1-config.sh      # 37 mục, chỉ đọc — không sửa gì
```

Mất mạng thì gỡ ra:

```bash
sudo bash install.sh --uninstall
```

## Ba việc còn lại, phải tự làm

Cả ba nằm ngoài máy. `install.sh` đọc được cái thứ nhất nhưng không bật được, vì
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

**Đặt đường mặc định.** Hệ thống này chỉ được đo trên cáp, nhưng NetworkManager
mặc định lại ưu tiên wifi, nên lưu lượng sẽ chạy nhầm qua wifi. Cần tự đặt
`ipv4.route-metric` cho từng profile. Một chỗ dễ hiểu sai: hạ riêng metric của
profile cáp thì vô dụng, vì NetworkManager cộng thêm 20000 vào metric của profile
có `autoconnect-priority` thấp hơn.

**Ghim DoH cho trình duyệt.** Tường DNS chặn cổng 53 và 853, nhưng DoH (DNS mã
hoá chạy trên HTTPS) lại dùng cổng 443, cùng cổng với web, nên không có cách nào
chặn riêng mà không chặn cả web. Để trình duyệt tự chọn provider thì nó đi vòng
khỏi NextDNS. Cách làm ở
[`docs/tinh-chinh-trinh-duyet.md`](docs/tinh-chinh-trinh-duyet.md).

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
