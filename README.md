# zapret2-dotfile

Ba tầng lọc cho CachyOS / Arch. **NextDNS** quyết định trang nào bị chặn,
**zapret2** chống chuyện bị chặn nhầm, **ufw** đóng cửa những thứ lọt vào máy.

Cả hệ thống chỉ xoay quanh một ý: gom mọi câu hỏi tên miền về đúng một chỗ, rồi
để chỗ đó quyết định. Phần nào nằm trong máy thì script lo hết. Riêng danh sách
chặn thì nằm trên đám mây NextDNS — phần đó bạn phải tự bật.

## Vấn đề

Ở Việt Nam, người ta chặn theo **tên miền**, không theo địa chỉ IP. Bạn vẫn vào
được IP đó từ máy bất kỳ, chỉ cần gõ đúng địa chỉ — không có quy tắc nào ở tầng
đường truyền chặn được. Nói cách khác, chỗ duy nhất quyết định cho đi hay chặn
chính là chỗ hỏi tên miền.

```
┌─────────────────────────────────── MÁY CỦA BẠN ────────────────────────────────────┐
│                                                                                    │
│  KHI BẠN MỞ MỘT TRANG WEB                                                          │
│                                                                                    │
│  [1]  TẦNG 2 · NextDNS qua DoT                                                     │
│      Hỏi tên miền ở cổng 853. NextDNS trả về IP thật, hoặc chặn                    │
│      tuỳ danh sách nằm trên đám mây của bạn.                                       │
│                                                                                    │
│      << ĐÂY LÀ CHỖ DUY NHẤT QUYẾT ĐỊNH CHẶN.                                       │
│      Danh sách chặn nằm trên đám mây chứ không nằm trong máy,                      │
│      nên phần cài đặt bên dưới chỉ kiểm được, không bật được.                      │
│                                                                                    │
│  [2]  TẦNG 1 · zapret2 · desync                                                    │
│      Mở kết nối tới IP vừa nhận được, rồi cắt gói mở đầu                           │
│      thành hai đoạn, đoạn đầu chỉ mang 1 byte. Bộ lọc của                          │
│      nhà mạng cần nguyên gói đó để đọc tên miền, nên không                         │
│      khớp mẫu nào và cho qua.                                                      │
│                                                                                    │
│      Tầng này không chặn gì cả — nó chỉ chống bị chặn. Nếu tên                     │
│      miền bị chặn ở bước [1] thì bước [2] không còn kết nối                        │
│      nào để mà sửa.                                                                │
│                                                                                    │
│  KHI CÓ AI GỌI TỚI MÁY BẠN                                                         │
│                                                                                    │
│  [3]  TẦNG 3 · ufw · chặn INPUT                                                    │
│      Chặn mọi thứ đi vào máy, trừ KDE Connect trong mạng LAN.                      │
│                                                                                    │
│  [4]  TẦNG 2b · ufw · tường chặn DNS                                               │
│      Chỉ cho phép hỏi NextDNS ở 53/udp và 853/tcp, chặn mọi                        │
│      nơi hỏi DNS khác — cả IPv4 lẫn IPv6.                                          │
└────────────────────────────────────────────────────────────────────────────────────┘
```

## Một điều dễ hiểu nhầm

**Tầng 1 không phải là thứ cứu truy cập.** Nó sửa gói tin, chứ không tạo ra gói
tin. Tên miền đã bị chặn ở bước [1] thì ở bước [2] chẳng còn kết nối nào để mà
sửa. Hãy hiểu nó là lưới an toàn, không phải chốt chặn.

Chặn ở đây thuộc kiểu **DNS**, không phải kiểu DPI. Tắt hẳn zapret2 đi, `github`, `wikipedia`, `example` vẫn trả `200`
trọn vẹn: đường truyền không có bộ lọc nào cả. Nói cách khác, thứ thật
sự chặn trang chính là câu trả lời của NextDNS ở bước [1].

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

> Hai lab trong bảng trên nằm ở `tests/lab/`, chạy tự động dưới pytest. Máy này
> không có `tcpdump` cũng không có `nmap` — cài hai thứ đó vào chính máy đang kiểm
> rồi cũng không dám xoá, nên tôi tự viết.

## Cài đặt

### Bước 1 — Tạo profile NextDNS

Làm trước tiên, vì ID phải lấy ở đây.

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
> toàn làm loại "chạy trơn trên máy đã có sẵn, chết ngay trên máy trắng".
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

Cả hai nằm ngoài máy. `install.sh` đọc được cái thứ nhất chứ không bật được, vì
API key chỉ có quyền đọc.

**Bật cấu hình tầng 2 trên đám mây.** Script in ra tên profile, số mục chặn và cho
qua, và cảnh báo nếu `aiThreatDetection` hoặc `threatIntelligenceFeeds` đang tắt.
Bật thì bạn phải tự vào <https://my.nextdns.io>.

Ranh giới của việc kiểm nên nói rõ. `install.sh` bắt được đúng hai công tắc đó,
vì đó là thứ nó đọc được. Còn `test/t1-config.sh` thì chỉ kiểm **hình dạng** cấu
hình, không kiểm hành vi — ID sai, danh sách rỗng, hay NextDNS đổi ý bạn thì nó
vẫn báo đạt.

Muốn biết chắc tầng 2 có thật sự lọc không, hỏi một tên miền mà bạn biết chắc
profile của mình đang chặn:

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

`install.sh` tự làm phần này, bạn không cần gõ gì. Nhưng nên hiểu vì sao, để sau
này tự chỉnh không bỡ ngỡ.

Khi cáp và wifi cùng mở, Linux chọn đường bằng **metric** — đường nào có số nhỏ
hơn thì thắng. Installer đặt cáp `100`, wifi `50000`.

Nhưng con số bạn đặt chưa phải số thật. Wifi trên máy này là hotspot điện thoại,
mà NetworkManager liên tục thử xem mỗi kết nối có ra được Internet thật không:

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

Cáp hỏng thì route của cáp biến mất, wifi thành đường mặc định, không cần làm
gì thêm. Lúc đó metric `50000` cũng chẳng còn ý nghĩa — dù sao thì chỉ còn một
đường.

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
đếm xem profile đang có bao nhiêu mục chặn, bao nhiêu cho qua.

Không có key thì hệ thống vẫn chạy y hệt, chỉ mất phần kiểm — và script nói thẳng
là không kiểm được, chứ không im lặng coi như đã kiểm. Nói vậy là vì ID sai không
gây lỗi gì cả: NextDNS chỉ trả lời bằng profile mặc định của họ, nên máy vẫn thông
mạng mà không lọc gì.

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

## Cập nhật zapret2

```bash
sudo bash update.sh --check-only     # xem có bản mới không, không đụng gì
sudo bash update.sh                  # hỏi rồi cài nếu có
sudo bash update.sh --from master    # cài từ branch (code chưa phát hành)
```

Hỏi GitHub release mới nhất, nếu có thì build và cài. **`/opt/zapret2/config` và
hai danh sách user không bao giờ bị mất.**

Ba file đó nằm trong `.gitignore` của zapret2, nên git coi là rác — `git clean -xdf`
sẽ xoá sạch cả ba. Script này không dùng lệnh đó: nó backup trước, đối chiếu
SHA256 sau, và khôi phục nếu lệch. Build hỏng thì tự quay lui về đúng commit cũ.

Mỗi lần cài để lại backup ở `/var/backups/zapret2-dotfile/update-<giờ>/`, giữ 5
bản gần nhất.

> `install.sh` cài MỚI nên `rm -rf /opt/zapret2` rồi clone lại — làm vậy sẽ mất
> config. `update.sh` không `rm -rf`, chỉ `git checkout` sang tag mới.

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

Trong đó có hai lab dùng netns: một máy quét từ "bên ngoài", một DPI giả chặn
theo tên miền. Cả hai tự dựng và tự dọn trong `finally`. Cách dùng chi tiết ở
[`tests/README.md`](tests/README.md).

## Đọc thêm

| Tệp | Nội dung |
|---|---|
| [`docs/NETWORK-DESIGN.md`](docs/NETWORK-DESIGN.md) | Thiết kế chi tiết, kết quả đo, và những chỗ đã biết là chưa ổn |
| [`docs/CAI-ZAPRET2-GUI-WINDOWS.md`](docs/CAI-ZAPRET2-GUI-WINDOWS.md) | Cài Zapret 2 GUI trên Windows, từ tải tới khi site mở được |
| [`docs/NGUOI-SUA.md`](docs/NGUOI-SUA.md) | Bẫy cần tránh khi sửa script trong repo này |
| [`docs/tinh-chinh-trinh-duyet.md`](docs/tinh-chinh-trinh-duyet.md) | Ghim DoH cho Firefox và Chromium |
| [`tests/README.md`](tests/README.md) | Cách chạy khung kiểm thử |

### Tra cứu zapret2 (tổng hợp từ wiki.zapret.moe)

Tám tài liệu, toàn bộ 283 trang wiki.

| Tệp | Nội dung |
|---|---|
| [`docs/ZAPRET2-WIKI-TONG-HOP.md`](docs/ZAPRET2-WIKI-TONG-HOP.md) | Lõi `nfqws2`: kiến trúc, pipeline 10 chặng, hợp đồng Lua, profile, filter, fooling |
| [`docs/WIKI-ZAPRET2-CAU-HINH.md`](docs/WIKI-ZAPRET2-CAU-HINH.md) | Cú pháp thực hành: preset, profile thật, blob, orchestrator `circular` |
| [`docs/WIKI-DESYNC-PACKET-SO-DO.md`](docs/WIKI-DESYNC-PACKET-SO-DO.md) | Sơ đồ packet từng byte của cả 11 kỹ thuật desync |
| [`docs/WIKI-ZAPRET1-THAM-CHIEU.md`](docs/WIKI-ZAPRET1-THAM-CHIEU.md) | Zapret 1: cờ `nfqws`, hostlist/ipset/hosts, cài Linux, chẩn đoán |
| [`docs/WIKI-ZAPRET-NENH-TANG-GAME.md`](docs/WIKI-ZAPRET-NENH-TANG-GAME.md) | Router, Android, Steam, game, `wssize` |
| [`docs/WIKI-DPI-TSPU.md`](docs/WIKI-DPI-TSPU.md) | DPI и ТСПУ: phễu kiểm tra, bắt DNS 2026, vân tay JA4 |
| [`docs/WIKI-PROXY-VPN-CONG-CU.md`](docs/WIKI-PROXY-VPN-CONG-CU.md) | Proxy/VPN: xray, VLESS, REALITY, Clash, sing-box, Hysteria |
| [`docs/WIKI-VAN-DE-AN-TOAN.md`](docs/WIKI-VAN-DE-AN-TOAN.md) | Virus giả, chứng thư НУЦ, root Android, FIDO |
