# Người sửa script trong repo này

Danh sách bẫy đã dính thật. Mỗi mục là một lỗi đã xảy ra, đã mất công tìm, và
đã được sửa trong code hiện tại. Đọc trước khi viết bộ kiểm mới.

## 1. Bốn điều về cấu hình

**`/opt/zapret2/config` là script shell, không phải tệp keyfile.**
Phải là `KEY=VALUE`. Viết `KEY = VALUE` thì bash hiểu thành lệnh `KEY` với hai
đối số, báo `command not found`, và zapret2 **không lên**. Ngược lại
`z2d-sysctl.conf` **là** keyfile nên có khoảng trắng quanh `=` là đúng. Hai kiểu
khác nhau — đừng lấy khuôn của cái này cho cái kia.

**`NFQWS2_OPT` là khối nhiều dòng.**

```
NFQWS2_OPT="
--filter-tcp=80 ...
--filter-tcp=443 ...
"
```

`sed 's|^NFQWS2_OPT=.*|...|'` chỉ thay **dòng đầu**, các dòng sau trôi thành lệnh
lạ và config hỏng. Phải xoá cả khối rồi chèn, bằng một lượt `awk`.

**Danh sách user phải RỖNG.** Rỗng = không còn mệnh đề lọc = desync mọi kết nối
80/443. Thêm một domain là chỉ còn desync domain đó, và phải restart mới có tác
dụng.

**Comment của rule ufw lưu dạng hex trong `user.rules`.**
`comment=7a3264206e657874646e73203533` giải mã ra `z2d nextdns 53`. Nên grep
chữ `z2d` trong tệp **luôn ra 0 dòng**, dù `ufw status` hiện đủ 20 rule. Mọi kiểm
phải đi qua `ufw status`, không đọc thẳng tệp.

## 1b. Sơ đồ trong README: sinh bằng script, đừng gõ tay

`python3 test/make-diagram.py` in ra sơ đồ đã căn, kèm tự kiểm.
`python3 test/check-diagram.py` kiểm README.md, exit 1 nếu lệch.

**Vì sao không gõ tay.** Dấu tiếng Việt là ký tự **tổ hợp** — `ề` gồm `e` +
dấu, và dấu chiếm **0 cột** hiển thị. Đo bằng `len()` thì mỗi dấu cộng thêm 1,
nên hai dòng nhìn giống nhau vẫn lệch nhau khi hiển thị. Sơ đồ cũ lệch 3 dòng
đúng vì lý do này.

Quy tắc kiểm: **mọi dòng trong khối sơ đồ phải cùng độ rộng hiển thị**, và các
ký tự khung phải ở cùng cột. Dòng có dấu hai chấm bị chừa ra thì tính cả
phần chừa, không phải chỉ phần khung.

## 2. Bẫy đo lười

| bẫy | biểu hiện | sửa |
|---|---|---|
| `grep -c … \|\| echo 0` | grep in `0` **rồi trả về 1**, nên `\|\|` in thêm `0` nữa → giá trị `"0\n0"`, dòng kiểm báo LỆCH dù máy hoàn toàn đúng | `\|\| true` |
| lookbehind biến thiên | `grep -oP '(?<=X\s*=\s*)'` → PCRE từ chối: *length of lookbehind assertion is not limited* | `^X=\K` |
| `$?` sau `\|` | lấy trạng thái lệnh cuối trong pipe, không phải của script | đo vào tệp, không pipe ra `grep`/`sed` |
| `grep -c 'LỆCH'` | khớp cả dòng tổng kết `0LỆCH` → mọi phép đo đều ≥ 1 | yêu cầu `^[[:space:]]+LỆCH[[:space:]]` |
| `exit 1` trong pipeline | `while` chạy ở subshell → lỗi bị nuốt, dòng "OK" vẫn in | gom vào mảng bằng `mapfile`, kiểm ngoài pipeline |
| đếm dòng thay vì kiểm rule | 4 rule giả cùng chú là đủ để "đạt" khi rule thật đã mất | kiểm từng rule theo ngữ nghĩa |
| phép thử rỗng | phép thử timeout dù đã mở tường ⇒ luôn báo "đã chặn", báo đạt giả | chọn phép thử đã đo là phân biệt được |

## 3. Bẫy khi đọc `ufw status`

ufw in **ba** bố cục khác nhau:

```
OUT, có địa chỉ đích : 45.90.28.0  53/udp  ALLOW OUT  Anywhere
                                            ↑địa chỉ ↑cổng  ↑act ↑hướng
OUT, "any"           : 53/udp  (v6)  DENY  OUT  Anywhere (v6)
IN                   : 1714:1764/tcp  ALLOW      192.168.0.0/16
                                           ↑cổng ↑act  ↑NGUỒN, KHÔNG in "IN"
```

Ba lỗi đã dính với hàm kiểm rule:

1. So `$3` với hướng → nhận đủ 16 rule tường DNS (rule OUT) mà **bỏ qua cả 4
   rule KDE Connect** (rule IN), vì dòng IN không có token hướng.
2. Nhầm "không có token hướng" với "có token hướng nhưng khác hướng" → hỏi hướng
   `IN` cho một rule `OUT` vẫn trả "có".
3. Regex cổng `^[0-9]+\/[a-z]+$` không khớp dải cổng `1714:1764/tcp`.

Địa chỉ cũng nằm khác chỗ: rule OUT đặt **trước** cổng, rule IN đặt **sau**
action.

## 4. Quy tắc khi viết

1. **Không in "HOÀN TẤT" khi chưa kiểm chứng.** Sai một chỗ thì dừng. Bản đầu
   còn in "HOÀN TẤT" ở chế độ `--dry` — tức thành công giả.
2. **Không tin mã lỗi của lệnh** — luôn đọc lại trạng thái sau khi ghi.
3. **Không nuốt lỗi trong backup.** `cp … 2>/dev/null` từng làm mất im lặng đúng
   tệp `opt/zapret2/config` — thứ duy nhất để quay lại.
4. **Số phải bốc từ tệp, không ghi cứng.** Thông báo ghi "15 khoá" trong khi tệp
   có 18 là kiểu lỗi tự sai theo thay đổi cấu hình.
5. **`--dry` không được sửa gì và không được in "HOÀN TẤT".**
6. **Chỉ MỘT bản sao lưu**, tên cố định `/var/backups/zapret2-dotfile/`.

## 5. Nguyên tắc chung

**Mọi phép đo phải được thử bằng cách tiêm một lỗi thật.** Chạy một lần thấy
"đạt" là bằng không — phép đo có thể luôn in "đạt" vì kiểm nhầm thứ không liên
quan, hoặc vì điều kiện của nó không bao giờ chạy.

Cách kiểm: sửa đúng một thứ, chạy lại bộ kiểm, đòi nó phải báo LỆCH. Nếu không
báo thì dòng đó **không kiểm được gì**.

Khi tiêm nhiều lỗi liên tiếp, phải **khôi phục đầy đủ sau mỗi lỗi** — nếu không
thì các lỗi sau chạy trên nền đã hỏng và không phân biệt được mình vừa bắt lỗi
mới hay chỉ thấy lại lỗi cũ. Và phải kiểm nền sạch **trước** khi bắt đầu, vì
kết luận trên nền hỏng thì vô nghĩa.
