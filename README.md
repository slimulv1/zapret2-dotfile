# zapret2-dotfile

Ba tầng lọc cho CachyOS / Arch. **NextDNS** quyết định trang nào bị chặn,
**zapret2** chống chuyện bị chặn nhầm, **ufw** đóng cửa những thứ lọt vào máy.

Có một cách hình dung cả hệ thống trong một câu: mọi câu hỏi tên miền đều được
dồn về đúng một chỗ, rồi để chỗ đó quyết định. Phần nào nằm trong máy thì script
lo hết. Riêng danh sách chặn thì nằm trên đám mây NextDNS — phần đó bạn phải tự
bật.

## Vấn đề

Ở Việt Nam, phần lớn trang bị chặn đều bị chặn **theo tên miền**, chứ không phải
theo địa chỉ IP. Bạn vẫn vào được IP đó từ máy bất kỳ, chỉ cần gõ đúng địa chỉ —
không có quy tắc nào ở tầng đường truyền chặn được. Nói cách khác, chỗ duy nhất
quyết định cho đi hay chặn là chỗ hỏi tên miền.

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
│  [4]  TẦNG 2b · ufw · tường chặn DNS                                               │
│      Chỉ cho phép hỏi NextDNS ở 53/udp và 853/tcp, chặn mọi nơi                    │
│      hỏi DNS khác — cả IPv4 lẫn IPv6.                                              │
└────────────────────────────────────────────────────────────────────────────────────┘
```

## Một điều dễ hiểu nhầm

**Tầng 1 không phải là thứ cứu truy cập.** Nó sửa gói tin, chứ không tạo ra gói
tin. Tên miền đã bị chặn ở bước [1] thì ở bước [2] không còn kết nối nào để mà
sửa cả. Hãy hiểu nó là lưới an toàn, không phải chốt chặn cuối.

Chặn ở đây thuộc kiểu **DNS**, không phải kiểu DPI — và điều đó tôi đo được, không
suy ra. Tắt hẳn zapret2 đi thì `github`, `wikipedia`, `example` vẫn trả `200` trọn
vẹn: đường truyền của tôi không có bộ lọc nào cả. Nghĩa là thứ thật sự chặn trang
chính là câu trả lời của NextDNS ở bước [1].

## Đã đo được gì

Mỗi tầng đều có phép đo, không phải lời hứa:

| tầng | đo bằng gì | kết quả |
|---|---|---|
| **[1]** NextDNS qua DoT | `ss` bắt `systemd-resolved` nối cổng 853 | tên miền bị chặn → `NXDOMAIN`, tên miền thường → IP thật |
| **[2]** zapret2 cắt đoạn | bắt gói thẳng trên dây, tắt TSO/GSO trước khi đo | đoạn đầu **1 byte** (`0x16`), cả IPv4 lẫn IPv6 |
| [2] — tác dụng thật | lab DPI giả trong network namespace | zapret2 **bật** → `HTTP 200` · **tắt** → bị chặn |
| **[3]** chặn INPUT | quét từ một "máy ngoài" cùng netns | chỉ `1716` mở khi nguồn trong `192.168.0.0/16`; ngoài subnet thì chặn hết |
| **[4]** tường DNS | hỏi 8 resolver lạ, cả hai họ, cả `tcp` | `8/8` không có câu trả lời, và counter của rule DENY tăng |

Cách đo, những bẫy đo phải tránh, và chỗ nào **còn chưa** chứng minh được — tất cả ở
[docs/NETWORK-DESIGN.md](docs/NETWORK-DESIGN.md).

> Hai lab trong bảng trên dựng bằng `tests/lab/`, chạy tự động bằng pytest. Máy
> này không có `tcpdump` cũng không có `nmap`, mà cài hai thứ đó vào đúng máy đang
> kiểm rồi không dám xoá thì phiền hơn là tự làm.

## Cài đặt

### Bước 1 — Tạo profile NextDNS

Làm trước khi cài gì cả, vì bạn cần lấy ID ở đây.

1. Vào <https://my.nextdns.io>, đăng ký nếu chưa có, tạo một profile.
2. Bật hai công tắc **Threat Intelligence Feeds** và **AI Threat Detection**.
   Hai cái này quyết định gần như hết kết quả — tắt đi thì phần lớn chặn biến
   mất, còn danh sách chặn thủ công vẫn giữ nguyên.
3. Lấy **Profile ID**: <https://my.nextdns.io> → Settings → General. Sáu ký tự
   hex, ví dụ `785fad`.

### Bước 2 — Lấy repo

```bash
sudo pacman -S --needed git        # chỉ cần git; phần còn lại script tự cài
git clone https://github.com/slimulv1/zapret2-dotfile.git
cd zapret2-dotfile
```

### Bước 3 — Chạy installer

Xem trước đã, chưa sửa gì cả:

```bash
sudo bash install.sh --nd-id 785fad --dry
```

Đọc hết các bước, thấy `XEM XONG` rồi hãy chạy thật:

```bash
sudo bash install.sh --nd-id 785fad
```

Script tự lo phần còn lại:

| việc | chi tiết |
|---|---|
| cài gói thiếu | `nftables` `ufw` `networkmanager` `procps-ng` `iproute2` `git` `make` `gcc`, rồi 5 thư viện lúc chạy: `libnetfilter_queue` `libnfnetlink` `libmnl` `luajit` `zlib` |
| dựng tầng 1 | clone zapret2 ở tag `v1.0.5.2` rồi `make systemd` ra `nfq2/nfqws2` |
| đặt tầng 2 | ghi `resolved.conf`, tắt DNS của router trên mọi profile, trỏ `resolv.conf` vào stub |
| đặt tầng 2b + 3 | 20 dòng rule ufw: 8 ALLOW + 8 DENY cho DNS, 4 cho KDE Connect |
| chọn đường mặc định | đặt metric cáp `100`, wifi `50000` — xem [mục dưới](#đường-mặc-định-cáp-trước-wifi-chỉ-dự-phòng) |
| siết cứng | 18 khoá sysctl qua 3 lớp, kèm một `systemd.path` canh khoá bị kernel tự đặt lại |

Trước khi sửa bất cứ thứ gì, script chụp trạng thái hiện tại vào
`/var/backups/zapret2-dotfile/`. Chỉ một bản, tên cố định, lần sau ghi đè.

Xong thì kiểm lại:

```bash
sudo bash test/t1-config.sh      # chỉ đọc — không sửa gì
```

Dòng cuối in ra `đạt N · LỆCH M` — N là số mục, M là số mục lệch.

> **Đã thử trên máy trắng.** Hệ thống 3 tầng từng được gỡ sạch khỏi máy thật rồi
> cài lại từ đầu. Lần đó phải sửa **8 lỗi thật** trong `install.sh` mới cài được —
> toàn những lỗi loại "chạy trơn trên máy đã có sẵn, chết ngay trên máy trắng".
>
> "Máy trắng" ở đây là **không còn hệ thống 3 tầng**, không phải máy trống không
> gói gì. Các gói nền (`gcc` `make` `git` `nftables` `ufw` `luajit`) để nguyên —
> gỡ chúng sẽ làm hỏng `paru`, `mpv`, `gamescope`, `dnsmasq`, `dkms`.

### Installer tự kiểm

Trước khi in `HOÀN TẤT`, installer tự kiểm — và các phép kiểm đó nhìn vào
**kernel** chứ không chỉ đọc tệp cấu hình:

| phép kiểm | nó thật sự đo cái gì |
|---|---|
| `DoT thật` | `ss` thấy `systemd-resolved` đang nối cổng **853** thật |
| `policy INPUT: kernel v4/v6` | đọc `nft list ruleset`: kernel tự nói `policy drop` |
| `18/18 khoá sysctl` | đọc `sysctl -n` — giá trị **đang hiệu lực**, không phải dòng trong tệp |
| `tường DNS 16 rule` | dò từng rule theo nghĩa, kiểm cả IPv4 lẫn IPv6 |
| `route-metric` | đọc metric từng profile, đếm sai từng cái |

## Hai việc còn lại, phải tự làm

Cả hai nằm ngoài máy. `install.sh` đọc được cái thứ nhất nhưng không bật được,
vì API key chỉ có quyền đọc.

**Bật cấu hình tầng 2 trên đám mây.** Script in ra tên profile, số mục chặn /
cho qua, và cảnh báo nếu `aiThreatDetection` hoặc `threatIntelligenceFeeds` đang
tắt. Bật thì bạn phải tự làm ở <https://my.nextdns.io>.

Ranh giới của việc kiểm: `install.sh` bắt được đúng hai công tắc đó, vì đó là
thứ nó đọc được. `test/t1-config.sh` thì chỉ kiểm **hình dạng** cấu hình, không
kiểm hành vi — ID sai, danh sách rỗng, hay NextDNS đổi ý bạn thì nó vẫn báo đạt.
Muốn biết chắc tầng 2 có thật sự lọc không, hỏi một tên miền mà bạn biết chắc
profile của bạn đang chặn:

```bash
dig +short <tên miền đó>     # 0.0.0.0 là đúng · IP thật là đang hỏng
```

**Ghim DoH cho trình duyệt.** Tường DNS chặn cổng 53 và 853, nhưng DoH (DNS mã
hoá chạy trên HTTPS) lại dùng cổng 443 — cùng cổng với web, nên không có cách nào
chặn riêng mà không chặn cả web. Để trình duyệt tự chọn provider thì nó đi vòng
khỏi NextDNS. Cách làm ở [`docs/tinh-chinh-trinh-duyet.md`](docs/tinh-chinh-trinh-duyet.md).

## Lỡ mất mạng thì gỡ

```bash
sudo bash install.sh --uninstall
```

Gỡ 3 tầng, dừng zapret2, xoá 20 dòng rule ufw, rồi **khôi phục tệp cũ từ backup**.
Có trong backup thì trả về; không có nghĩa là trước khi cài nó chưa tồn tại nên
xoá hẳn. Script tự báo đã xoá được bao nhiêu, và nếu thiếu thì in cảnh báo kèm
lệnh để bạn kiểm tay.

Gỡ xong thì ufw trở về đúng trạng thái bật/tắt như trước khi cài, kể cả khoá
sysctl siết cứng.

## Đường mặc định: cáp trước, wifi chỉ dự phòng

`install.sh` tự làm phần này, bạn không cần gõ gì. Nhưng nên hiểu vì sao, phòng
khi sau này bạn tự đỉnh.

Khi cáp và wifi cùng mở, Linux chọn đường bằng **metric** — đường nào có số nhỏ
hơn thì thắng. Installer đặt cáp `100`, wifi `50000`.

Con số bạn đặt chưa phải số thật. Wifi trên máy này là hotspot điện thoại, mà
NetworkManager liên tục thử xem mỗi kết nối có ra được Internet thật không:

```
cáp   enp8s0   full      ra được Internet bình thường
wifi  wlan0    limited   bị hạn chế
```

Tài liệu NetworkManager nói rõ: kết nối không ở mức `full` sẽ bị **cộng thêm
20000** vào metric. Nên metric thật trong bảng định tuyến là cáp `100`, wifi
`50000 + 20000 = 70000`. Cáp thắng, và thắng rộng.

Cái hay nhầm nhất là phần cộng 20000 đó. Nó **không** đến từ
`autoconnect-priority` — đảo priority của hai profile theo cả hai chiều thì metric
không nhúc nhích. Nó đến từ kết quả kiểm tra kết nối, và chỉ biến mất khi
NetworkManager xếp wifi lên `full`.

Cáp hỏng thì route của cáp biến mất, wifi thành đường mặc định — không cần làm
gì thêm. Đó cũng là lúc metric `50000` thành vô nghĩa, nhưng vẫn thắng vì chỉ còn
một đường.

Muốn tự chỉnh:

```bash
nmcli connection modify "profile cáp"  ipv4.route-metric 100   ipv6.route-metric 100
nmcli connection modify "profile wifi" ipv4.route-metric 50000 ipv6.route-metric 50000
```

Đặt xong **phải reapply thì mới có hiệu lực** — đây là chỗ hay tưởng đã xong trong
khi chưa:

```bash
nmcli device reapply enp8s0
nmcli device reapply wlan0
ip -4 route show default
```

Hai số `100` và `50000` không có ý nghĩa gì đặc biệt, chỉ cần cách nhau đủ xa.

## Cần ID, hay cả API key?

**Chỉ cần ID** để hệ thống chạy. Đó là thứ duy nhất nằm trong cấu hình máy, dạng
`45.90.28.0#<ID>.dns.nextdns.io`.

API key chỉ để **đọc**: nó giúp script hỏi NextDNS xem ID bạn đưa có thật không, và
đọc xem profile đang có bao nhiêu mục chặn / cho qua. Không có key thì hệ thống vẫn
chạy y hệt, chỉ mất phần kiểm — và script nói thẳng là không kiểm được chứ không
im lặng coi như đã kiểm. Lý do phải nói thẳng: ID sai không gây lỗi gì cả,
NextDNS chỉ trả lời bằng profile mặc định của họ, nên máy vẫn thông mạng mà
không lọc gì.

Đặt key ở `/root/.config/nextdns/api.key`, quyền 600, lấy ở
<https://my.nextdns.io> → Account → API:

```bash
sudo install -d -m 700 /root/.config/nextdns
sudo tee /root/.config/nextdns/api.key >/dev/null   # dán key, rồi Ctrl-D
sudo chmod 600 /root/.config/nextdns/api.key
```

Key nằm ngoài repo, và cũng không nằm trong bất kỳ tệp cấu hình nào trên máy — chỉ
được đọc lúc chạy `install.sh`. Lý do rất đơn giản: key cho phép **sửa** danh
sách chặn, chứ không chỉ đọc. Repo private vẫn hiện với người được mời cộng tác,
mà chuyển sang public thì chỉ mất vài giây.

Một chi tiết đáng biết: **key tự lộ ra ID**. Gọi `GET /profiles` với key là ra
danh sách profile kèm ID, nên lỡ quên ID mà vẫn còn key thì tìm lại được.

## Kiểm thử

Khung pytest nằm ở `tests/`, chạy được ngay trên máy thật:

```bash
python3 -m venv /tmp/z2d-qa/venv
/tmp/z2d-qa/venv/bin/python -m pip install pytest testinfra

# chỉ phép đọc — an toàn, không đổi gì
SUDO_ASKPASS=/tmp/.zz.sh sudo -A /tmp/z2d-qa/venv/bin/python -m pytest tests/ -q

# đầy đủ, gồm cài/gỡ thật
… -q --nd-id <ID> --run-destructive
```

Hai lab dùng netns — một máy quét từ "bên ngoài", một DPI giả chặn theo tên miền —
đều tự dựng và tự dọn trong `finally`. Cách dùng chi tiết: [`tests/README.md`](tests/README.md).

## Đọc thêm

| Tệp | Nội dung |
|---|---|
| [`docs/NETWORK-DESIGN.md`](docs/NETWORK-DESIGN.md) | Thiết kế chi tiết, kết quả đo, và những chỗ đã biết là chưa ổn |
| [`docs/NGUOI-SUA.md`](docs/NGUOI-SUA.md) | Bẫy cần tránh khi sửa script trong repo này |
| [`docs/tinh-chinh-trinh-duyet.md`](docs/tinh-chinh-trinh-duyet.md) | Ghim DoH cho Firefox và Chromium |
| [`tests/README.md`](tests/README.md) | Cách chạy khung kiểm thử |
