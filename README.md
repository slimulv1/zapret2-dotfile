# zapret2-dotfile

Hệ thống mạng 3 tầng cho CachyOS / Arch.

## Vấn đề cần giải

Ở Việt Nam, phần lớn trang bị chặn bị chặn **theo tên miền**, không phải theo
địa chỉ IP. Nghĩa là bạn có thể vào được IP đó từ bất kỳ máy nào, chỉ cần nhập
đúng địa chỉ. Chặn kiểu đó không thể "vá" ở tầng thiết bị mạng — nó nằm ở chỗ
hỏi tên miền.

Hệ thống này giải quyết đúng chỗ đó: **mọi câu hỏi tên miền đều phải đi qua
một nơi duy nhất**, và nơi đó quyết định cho đi hay chặn.

```
   gói tin đi ra Internet
            │
   ┌────────▼──────────────┐
   │  1 · zapret2          │  Sửa gói tin để bộ lọc (DPI) của nhà mạng
   │  nfqws2               │  không đọc được tên miền. Không chặn gì cả.
   └────────┬──────────────┘
            │
   ┌────────▼──────────────┐
   │  2 · NextDNS          │  ◀ Chỗ DUY NHẤT quyết định chặn.
   │  hỏi tên miền qua    │  Trả IP thật, hoặc chặn tuỳ danh sách trên
   │  DoT · cổng 853      │  đám mây. Không có kết nối nào đi được tới tầng 1
   └────────┬──────────────┘  nếu tên miền bị chặn ở đây.
            │
   ┌────────▼──────────────┐
   │  2b · ufw tường DNS  │  Chỉ cho hỏi NextDNS, chặn mọi nơi hỏi DNS khác
   │  16 rule              │  (cổng 53 và 853, cả IPv4 lẫn IPv6).
   └────────┬──────────────┘  Đây là siết lại, không phải quyết định.
            │
   ┌────────▼──────────────┐
   │  3 · ufw chặn vào máy │  Chặn mọi thứ từ ngoài vào, trừ KDE Connect
   │  INPUT deny           │  trong mạng LAN. Chặn theo cổng, không quyết định.
   └───────────────────────┘
```

(DoT là DNS mã hoá chạy trên TLS, cổng 853. Cần mã hoá vì DNS thường cổng 53 thì
nhà mạng tiêm được: đo được FPT trả `127.0.0.1` cho domain bị chặn.)

Vì chỉ tầng 2 mới quyết định, nên **tầng 1 là lưới an toàn, không phải thứ đang
cứu truy cập**. Nó sửa gói tin, chứ không tạo ra gói tin — một tên miền không
phân giải được thì không có kết nối nào để mà sửa.

Ví dụ cho ranh giới đó. Hai trang `viet69.be` và `erothots.co` bị
NextDNS chặn. Nếu ép thẳng IP của chúng, giữ nguyên phần định danh bảo mật,
thì cả hai trả về `HTTP 200` — nghĩa là nhà mạng **không** chặn gì, chỉ có
NextDNS chặn. Bật hay tắt tầng 1 thì kết quả y hệt nhau.

## Tầng 1 làm gì cụ thể

DPI của nhà mạng đọc tên miền ở gói đầu tiên của mỗi kết nối HTTPS — gói đó
chứa `ClientHello`, và tên miền nằm nguyên trong đó.

Tầng 1 cắt gói đó làm hai đoạn, đoạn đầu chỉ mang **1 byte**. DPI cần nguyên
`ClientHello` trong một gói để khớp mẫu — thấy 1 byte thì không mẫu nào khớp,
nên nó cho qua. Máy đích thì vẫn ghép lại được, vì TCP chỉ cần đúng thứ tự byte.

Đo trên máy thật, bằng cách xem chiều dài đoạn TCP đầu tiên của 5 kết nối:

| | đoạn đầu tiên |
|---|---|
| tầng 1 bật | `[1, 1, 1, 1, 1]` byte |
| tầng 1 tắt | `[1570, 1570, 1570, 1571, 1573]` byte |

Phạm vi có giới hạn: chỉ cổng **80 và 443**, và loại trừ 9 dải IP nội bộ
(loopback, LAN, CGNAT, link-local). Domain bị tầng 2 chặn trả về `127.0.0.1` —
nằm trong 9 dải đó — nên lưu lượng của nó không bao giờ tới được tầng 1.

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

Trước khi sửa gì, script chụp lại trạng thái hiện tại vào
`/var/backups/zapret2-dotfile/`. Chỉ có một bản, tên cố định, lần sau ghi đè.

Kiểm lại bằng:

```bash
sudo bash test/t1-config.sh      # 37 mục, chỉ đọc — không sửa gì
```

Mất mạng thì:

```bash
sudo bash install.sh --uninstall
```

## Ba việc còn lại, phải tự làm

Ba việc sau nằm ngoài máy, nên script không tự làm được.

**Bật cấu hình tầng 2 trên đám mây.** Đây là bước dễ bỏ nhất, và bỏ thì mọi
kiểm vẫn báo đạt — vì cấu hình sai nằm trên đám mây chứ không nằm trong máy.
Cấu hình đang dùng được chép lại ở [`nextdns/README.md`](nextdns/README.md).

**Đặt đường mặc định.** Hệ thống này chỉ được đo trên cáp, nhưng
NetworkManager mặc định lại ưu tiên wifi, nên lưu lượng sẽ chạy nhầm qua
wifi. Cần tự đặt `ipv4.route-metric` cho từng profile. Lưu ý: hạ riêng metric của
profile cáp thì vô dụng, vì NetworkManager cộng thêm 20000 vào metric của
profile có `autoconnect-priority` thấp hơn.

**Ghim DoH cho trình duyệt.** Tường DNS chặn cổng 53 và 853, nhưng DoH (DNS
mã hoá chạy trên HTTPS) lại dùng cổng 443 — cùng cổng với web, nên không có
cách nào chặn riêng mà không chặn cả web. Để trình duyệt tự
chọn provider thì nó đi vòng khỏi NextDNS. Cách làm:
[`docs/tinh-chinh-trinh-duyet.md`](docs/tinh-chinh-trinh-duyet.md).

## Đọc thêm

| Tệp | Nội dung |
|---|---|
| [`docs/NETWORK-DESIGN.md`](docs/NETWORK-DESIGN.md) | Thiết kế chi tiết, kết quả đo, và những chỗ đã biết là chưa ổn |
| [`docs/NGUOI-SUA.md`](docs/NGUOI-SUA.md) | Bẫy cần tránh khi sửa script trong repo này |
| [`docs/tinh-chinh-trinh-duyet.md`](docs/tinh-chinh-trinh-duyet.md) | Ghim DoH cho Firefox và Chromium |
| [`nextdns/README.md`](nextdns/README.md) | Ảnh chụp profile NextDNS |

## Về API key

Repo không chứa API key của NextDNS, dù dữ liệu profile đọc được mà không cần
key. Repo private vẫn hiện với người được mời cộng tác, và chuyển sang public chỉ
mất vài giây — mà key thì cho phép sửa cả danh sách chặn DNS.

Key đặt ở `/root/.config/nextdns/api.key`, quyền 600, ngoài repo.
