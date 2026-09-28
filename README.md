# zapret2-dotfile

Hệ thống mạng 3 tầng cho CachyOS / Arch.

## Vấn đề cần giải

Ở Việt Nam, phần lớn trang bị chặn bị chặn **theo tên miền**, không phải theo
địa chỉ IP. Nghĩa là bạn vẫn vào được IP đó từ máy bất kỳ, chỉ cần nhập đúng
địa chỉ — không có quy tắc nào ở tầng đường truyền chặn được. Chặn kiểu đó chỉ
nằm ở chỗ hỏi tên miền.

Hệ thống này gom mọi câu hỏi tên miền về một nơi duy nhất, và để nơi đó quyết
định cho đi hay chặn. Toàn bộ nằm trên máy bạn, trừ danh sách chặn nằm trên
đám mây:

```
┌─────────────────────────────────── MÁY CỦA BẠN ────────────────────────────────────┐
│                                                                                    │
│  KHI BẠN MỞ MỘT TRANG WEB                                                          │
│                                                                                    │
│  ①  TẦNG 2 · NextDNS qua DoT                                                       │
│      Hỏi tên miền ở cổng 853. NextDNS trả về IP thật, hoặc chặn tuỳ                │
│      danh sách nằm trên đám mây của bạn.                                           │
│                                                                                    │
│      ◀ ĐÂY LÀ CHỖ DUY NHẤT QUYẾT ĐỊNH CHẶN.                                        │
│      Danh sách chặn nằm trên đám mây chứ không nằm trong máy,                      │
│      nên phần cài đặt bên dưới không tự làm được bước này.                         │
│                                                                                    │
│  ②  TẦNG 1 · zapret2 · desync                                                      │
│      Mở kết nối tới IP vừa nhận được. Cắt gói đầu của kết nối                      │
│      HTTPS thành hai đoạn, đoạn đầu chỉ mang 1 byte. Bộ lọc của                    │
│      nhà mạng cần nguyên gói đó để đọc tên miền, nên không khớp                    │
│      mẫu nào và cho qua.                                                           │
│                                                                                    │
│      Tầng này không chặn gì cả — nó chỉ chống bị chặn. Nếu tên                     │
│      miền bị chặn ở bước ① thì không có kết nối nào để mà sửa                      │
│      ở bước ②.                                                                     │
│                                                                                    │
│  KHI CÓ AI GỌI TỚI MÁY BẠN                                                         │
│                                                                                    │
│  ③  TẦNG 3 · ufw · chặn INPUT                                                      │
│      Chặn mọi thứ đi vào máy, trừ KDE Connect trong mạng LAN.                      │
│                                                                                    │
│  LUÔN LUÔN BẬT, MỌI LÚC MỞ MÁY                                                     │
│                                                                                    │
│  ④  TẦNG 2b · ufw · tường chặn DNS                                                 │
│      Chỉ cho phép hỏi NextDNS ở cổng 53 và 853, chặn mọi nơi hỏi                   │
│      DNS khác — cả IPv4 lẫn IPv6.                                                  │
└────────────────────────────────────────────────────────────────────────────────────┘
```

Vì **chỉ tầng 2 quyết định chặn**, nên tầng 1 là lưới an toàn chứ không phải
thứ đang cứu truy cập. Nó sửa gói tin, chứ không tạo ra gói tin — mà tên miền
bị chặn ở bước ① thì không có kết nối nào để mà sửa ở bước ②.

## Đo được

**Tầng 1 thật sự cắt gói.** Cách đo là nhìn gói tin thật trên cáp, tách theo
từng kết nối, rồi đo chiều dài đoạn TCP đầu tiên:

| | đoạn đầu của 5 kết nối tới cổng 443 |
|---|---|
| tầng 1 bật | `[1, 1, 1, 1, 1]` byte |
| tầng 1 tắt | `[1570, 1570, 1570, 1571, 1573]` byte |

**Tầng 2 mới là chỗ chặn, và chặn kiểu DNS chứ không phải kiểu DPI.** Ví dụ:
`viet69.be` và `erothots.co` bị NextDNS chặn. Ép thẳng IP của chúng, giữ nguyên
phần định danh bảo mật, thì cả hai trả về `HTTP 200` — nhà mạng **không** chặn
gì. Bật hay tắt tầng 1 thì kết quả y hệt nhau.

**Phạm vi có giới hạn.** Tầng 1 chỉ xử lý cổng 80 và 443, và loại trừ 9 dải IP
nội bộ (loopback, LAN, CGNAT, link-local).

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
wifi. Cần tự đặt `ipv4.route-metric` cho từng profile. Lưu ý: hạ riêng metric
của profile cáp thì vô dụng, vì NetworkManager cộng thêm 20000 vào metric của
profile có `autoconnect-priority` thấp hơn.

**Ghim DoH cho trình duyệt.** Tường DNS chặn cổng 53 và 853, nhưng DoH (DNS mã
hoá chạy trên HTTPS) lại dùng cổng 443 — cùng cổng với web, nên không có cách
nào chặn riêng mà không chặn cả web. Để trình duyệt tự chọn provider thì nó
đi vòng khỏi NextDNS. Cách làm:
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
