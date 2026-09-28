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

Vì **chỉ tầng 2 quyết định chặn**, nên tầng 1 là lưới an toàn chứ không phải
thứ đang cứu truy cập. Nó sửa gói tin, chứ không tạo ra gói tin — mà tên miền
bị chặn ở bước [1] thì không có kết nối nào để mà sửa ở bước [2].

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

Hai trang đó **không nằm trong danh sách chặn thủ công**. NextDNS trả về
`Blocked by NextDNS: ai-threat-detection` và `threat-intelligence-feeds` — tức
là do hai công tắc `aiThreatDetection` và `threatIntelligenceFeeds` đang bật
trên đám mây. Đây là lý do một số trang bị chặn dù không hề có trong danh sách.

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

Script sẽ hỏi NextDNS xem ID đó có thật không, rồi in ra tên profile và số
mục chặn / cho qua / blocklist đang có trên đám mây. Cần API key ở
`/root/.config/nextdns/api.key` (quyền 600) — key nằm ngoài repo. Không có key
thì script **nói rõ là không kiểm được**, chứ không im lặng coi như đã kiểm; key
ở chỗ khác thì chỉ định bằng `--nd-key /đường/dẫn`.

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

Ba việc sau nằm ngoài máy. `install.sh` **kiểm được** cái thứ nhất, nhưng không
bật được — nó chỉ có quyền đọc.

**Bật cấu hình tầng 2 trên đám mây.** Đây là bước dễ bỏ nhất. Script sẽ báo tên
profile, số mục chặn / cho qua, và **cảnh báo nếu `aiThreatDetection` hoặc
`threatIntelligenceFeeds` đang tắt** — hai công tắc này quyết định gần như hết
kết quả, tắt đi thì phần lớn chặn biến mất mà danh sách chặn thủ công vẫn giữ
nguyên. Nhưng bật thì bạn phải tự làm ở <https://my.nextdns.io>.


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

## Về API key

Key **không** nằm trong repo, và giờ nó còn cần thiết hơn trước: không có key thì
`GET /profiles/<ID>` trả `403` cho **mọi** ID, kể cả ID thật — tức là không kiểm
được profile có tồn tại không.

Đặt ở `/root/.config/nextdns/api.key`, quyền 600:

```bash
sudo install -d -m 700 /root/.config/nextdns
sudo tee /root/.config/nextdns/api.key >/dev/null   # dán key, rồi Ctrl-D
sudo chmod 600 /root/.config/nextdns/api.key
```

Lấy key ở <https://my.nextdns.io> → Account → API. Key cho phép **sửa** danh
sách chặn DNS, nên không để trong repo — repo private vẫn hiện với người được
mời cộng tác, và chuyển sang public chỉ mất vài giây.

Không có key thì `install.sh` vẫn cài được. Nó chỉ không kiểm được ID, và sẽ báo
điều đó.

