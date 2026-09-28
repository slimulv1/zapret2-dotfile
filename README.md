# zapret2-dotfile

Hệ thống mạng 3 tầng cho CachyOS / Arch. Đây là **dotfile** — một nguồn sự
thật duy nhất để dựng lại máy hoặc máy khác.

```
tầng   làm gì                                    quyết định chặn?
1      zapret2 desync gói để không bị DPI chặn    không — không chặn gì
2      NextDNS qua DoT                            CÓ — tầng duy nhất
2b     ufw tường DNS: chỉ cho hỏi NextDNS          không
3      ufw INPUT deny, trừ KDE Connect            không
```

Chỉ tầng 2 quyết định trang nào bị chặn. Tầng 1 là lưới an toàn cho những gì
tầng 2 chưa chặn tới.

## Cài

```bash
git clone <repo> && cd zapret2-dotfile
sudo bash install.sh --nd-id ABC123 --dry     # xem trước, không sửa gì
sudo bash install.sh --nd-id ABC123           # cài thật
```

`--nd-id` là ID profile NextDNS, 6 ký tự hex, lấy ở
<https://my.nextdns.io> → Settings → General.

Trên máy trống (chưa có zapret2) thì `install.sh` tự cài luôn.

### Bước bắt buộc mà script không làm được

Cấu hình tầng 2 nằm trên **đám mây**, không phải trong máy. Nếu bỏ qua thì
tầng 2 không chặn gì và mọi kiểm vẫn báo đạt. Xem
[`nextdns/README.md`](nextdns/README.md) — có ảnh chụp cấu hình thật để đối
chiếu: **17 blocklist**, **83** mục denylist, **117** mục allowlist.

### Kiểm

```bash
sudo bash test/t1-config.sh      # 37 mục, chỉ đọc — không sửa gì
```

Mất mạng thì:

```bash
sudo bash install.sh --uninstall   # phục hồi từ backup chuẩn
```

## Cấu trúc

```
install.sh                  9 bước · --dry · --uninstall
config/
  z2d-zapret2.keys          10 khoá zapret2
  z2d-zapret2-opt           chiến lược desync (khối nhiều dòng)
  z2d-hosts-user.txt        RỔNG — điều kiện của việc bypass mọi 80/443
  z2d-exclude.txt           9 dải IP miễn trừ
  z2d-resolved.conf.template  {{ND_ID}} được thay lúc cài
  z2d-sysctl.conf           18 khoá — nguồn sysctl DUY NHẤT
  z2d-ufw-reapply-sysctl.conf  drop-in systemd
  z2d-pacman-ufw.hook       hook pacman
  z2d-sysctl-apply          helper 3 dòng
nextdns/                    ảnh chụp profile NextDNS từ API
docs/NETWORK-DESIGN.md      thiết kế + kết quả đo + bẫy đã dính
test/t1-config.sh           37 mục kiểm chứng
```

## Bốn điều cần biết trước khi sửa gì

**1. `/opt/zapret2/config` là script shell, không phải tệp keyfile.**
Phải là `KEY=VALUE`. Viết `KEY = VALUE` thì bash hiểu thành lệnh `KEY`, zapret2
không lên. Ngược lại `z2d-sysctl.conf` **là** keyfile nên có khoảng trắng là
đúng. Hai kiểu khác nhau — đừng lấy khuôn của cái này cho cái kia.

**2. `NFQWS2_OPT` là khối nhiều dòng.** `sed` chỉ thay dòng đầu sẽ làm các
dòng sau trôi thành lệnh lạ. Phải xoá cả khối rồi chèn.

**3. Danh sách user phải RỖNG.** Rỗng = không có mệnh đề lọc = desync mọi
kết nối 80/443. Thêm một domain là chỉ còn desync domain đó.

**4. Comment của rule ufw lưu dạng hex trong `user.rules`.**
`comment=7a3264206e657874646e73203533` là `z2d nextdns 53`. Nên grep chữ `z2d`
trong tệp **luôn ra 0 dòng** dù `ufw status` hiện đủ 20 rule. Mọi kiểm phải đi
qua `ufw status`.

## Quy tắc khi viết hoặc sửa script trong đây

1. **Không in "HOÀN TẤT" khi chưa kiểm chứng.** Sai một chỗ thì dừng.
2. **Không tin mã lỗi của lệnh** — đọc lại trạng thái sau khi ghi.
3. **Không đếm số dòng để kết luận.** Kiểm từng rule, cả IPv4 lẫn IPv6.
4. **Không nuốt lỗi trong backup.** `2>/dev/null` ở chỗ sao lưu đã từng làm
   mất im lặng đúng tệp cần để quay lại.
5. **Chỉ MỘT bản sao lưu**, tên cố định `/var/backups/zapret2-dotfile/`,
   ghi đè. Không sinh bản thứ hai.
6. **`--dry` không được sửa gì và không được in "HOÀN TẤT".**
7. **Mọi phép đo phải được thử bằng cách tiêm lỗi thật.** Chạy một lần thấy
   "đạt" là bằng không.

`docs/NETWORK-DESIGN.md` §9 liệt kê 13 bẫy đo đã dính — đọc trước khi viết
bộ kiểm mới, phần lớn là do lỗi bộ đo chứ không phải lỗi hệ thống.

## Ngoài phạm vi script

- **Đường mặc định.** Thiết kế chỉ đo trên cáp. NetworkManager mặc định ưu
  tiên wifi, nên phải tự đặt `ipv4.route-metric` cho từng profile.
  Hạ metric của cáp một mình là vô dụng — NetworkManager cộng thêm 20000 vào
  metric của profile có `autoconnect-priority` thấp hơn.
- **Trình duyệt.** Tường DNS chặn cổng 53 và 853, nhưng DoH chạy trên cổng
  **443** — không quy tắc nào chặn được nó mà không chặn cả web. Trình duyệt tự
  bật DoH sẽ đi vòng qua NextDNS. Phải ghim URI DoH của NextDNS thủ công.
  Với Firefox dùng `user.js` (đọc mỗi lần khởi động, không bị `prefs.js` ghi
  đè) và `trr.mode=2` — **không** dùng `3` (bắt buộc DoT, hỏng là mất DNS) và
  **không** dùng `5` (mặc định: có fallback nhưng không ghim provider).
  Trên CachyOS `~/.config` chạy qua back-ovfs nên profile có **hai** lớp bền:
  `<tên>-back-ovfs` và `<tên>-backup` — chỉ ghi một lớp thì mất sau reboot.
