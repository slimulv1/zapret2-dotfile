# Kỹ thuật desync — sơ đồ packet từng kỹ thuật

> **Nguồn:** `scripts/desync-anim.py` trong repo nguồn của wiki (Forgejo), 501 dòng.
> Đây là **đặc tả chuẩn packet-level** do chính tác giả wiki viết ra để sinh sơ đồ
> động — không phải bản tóm tắt của tôi.

Tài liệu này trả lời: **với MỖI kỹ thuật desync, chính xác những gói tin nào được
gửi, theo thứ tự nào, với `seq` nào, DPI thấy gì, và máy chủ xử lý ra sao.**

Trang [`ZAPRET2-WIKI-TONG-HOP.md`](ZAPRET2-WIKI-TONG-HOP.md) mục 15 mô tả kỹ thuật
ở mức **ý tưởng**. Tài liệu này là mức **byte**.

---

## 1. Cách đọc sơ đồ

Mọi kỹ thuật minh hoạ trên **cùng một ClientHello 26 byte**:

```
···········youtube.com····          (26 byte)
            ^^^^^^^^^^                  tên ở vị trí 11–22
            MIDSLD = 14 → you|tube     giữa tên
```

| Ký hiệu | Ý nghĩa |
|:--|:--|
| `─────` | byte thật của ClientHello |
| `X` hoặc `····` | **filler/fake** — dữ liệu giả |
| `seq=` | số thứ tự byte đầu tiên của gói trong luồng |
| `len=` | độ dài gói |
| **→ server: chấp nhận** | máy chủ nhận gói này vào bộ đệm |
| **→ server: chờ trong bộ đệm** | nhận nhưng **chưa** dùng — vì chưa đúng thứ tự seq |
| **→ server: bỏ (md5)** | bỏ vì chữ ký TCP MD5 sai |
| **→ server: bỏ (ack)** | bỏ vì số ACK sai |

**Quy tắc vàng:** máy chủ bảo vệ mình bằng **TCP/IP đúng chuẩn**. Mọi kỹ thuật
desync đều dựa trên điều đó — DPI không ghép lại luồng TCP, còn máy chủ thì có.

---

## 2. `fake` — gói giả trước gói thật

`blob=fake_default_tls` + `tcp_md5`

| # | Nhãn | seq | len | Nội dung | Máy chủ |
|--:|:--|:--|:--|:--|:--|
| 1 | **FAKE** | 0 | 26 | `···········www.w3.org·····` | **bỏ (md5)** |
| 2 | **ORIG** | 0 | 26 | `···········youtube.com····` | **chấp nhận** |

| | Hành vi |
|:--|:--|
| **DPI** | Đọc ClientHello `www.w3.org` **trước**. Nếu ra phán quyết đã được chốt theo nó, gói thật **không còn bị kiểm tra** |
| **Máy chủ** | Bỏ gói giả vì **chữ ký TCP MD5 sai** (`tcp_md5`), nhận gói thật |

Gói giả nằm ở **cùng vị trí luồng** (`seq=0`, `len=26`) với gói thật — nó làm "bẩn"
đúng chỗ DPI đang nhìn.

---

## 3. `multisplit` — ba segment theo thứ tự

`pos=1,midsld`

| # | Nhãn | seq | len | Máy chủ |
|--:|:--|:--|:--|:--|
| 1 | PART1 | 0 | 1 | chấp nhận |
| 2 | PART2 | 1 | 13 | chấp nhận |
| 3 | PART3 | 14 | 12 | chấp nhận |

| | Hành vi |
|:--|:--|
| **DPI** | Tên bị cắt **giữa #2 và #3**: chuỗi `youtube.com` **không nằm trọn trong gói nào** |
| **Máy chủ** | Cộng các segment theo `seq`, dựng lại đúng ClientHello gốc |

Đây là kỹ thuật nền — mọi kỹ thuật khác đều là biến thể của nó.

---

## 4. `multidisorder` — phần đi trước, phần đến sau

`pos=midsld`

| # | Nhãn | seq | len | Máy chủ |
|--:|:--|:--|:--|:--|
| 1 | PART2 | 14 | 12 | **chờ trong bộ đệm** |
| 2 | PART1 | 0 | 14 | chấp nhận |

| | Hành vi |
|:--|:--|
| **DPI** | **Cuối yêu cầu đến trước đầu yêu cầu.** Không tự ghép lại luồng thì không thấy tên trọn vẹn |
| **Máy chủ** | Giữ #1 trong bộ đệm, rồi đặt #2 **trước** nó theo `seq` |

So với `multisplit`: cùng lượt cắt, nhưng **đảo thứ tự gửi**.

---

## 5. `multidisorder_legacy` — đảo **trong từng gói**, không đảo cả luồng

`pos=200,600` — ClientHello **800 byte**, đến từ kernel **trong 2 gói**:
A (byte 0–499) và B (byte 500–799). Tên nằm ở byte 12–23.

| # | Nhãn | seq | len | byte | Máy chủ |
|--:|:--|:--|:--|:--|:--|
| 1 | **A2** | 200 | 300 | 200–500 | **chờ trong bộ đệm** |
| 2 | **A1** | 0 | 200 | 0–200 | chấp nhận |
| 3 | **B2** | 600 | 200 | 600–800 | **chờ trong bộ đệm** |
| 4 | **B1** | 500 | 100 | 500–600 | chấp nhận |

| | Hành vi |
|:--|:--|
| **DPI** | ClientHello gồm hai gói A và B. **Đảo thứ tự chỉ xảy ra BÊN TRONG từng gói** — gói A vẫn đến trước gói B |
| **Máy chủ** | Dựng lại 0–800 theo `seq` |

> **Khác biệt then chốt so với `multidisorder`:** `multidisorder` mới sẽ **đảo cả
> luồng** → thứ tự `600–800`, rồi `200–600`, rồi `0–200`. Bản `legacy` giữ **A trước
> B**, nên chỉ đảo bên trong.

---

## 6. `fakedsplit` — sáu segment: giả, thật, giả

`pos=midsld`

Sáu segment **theo đúng thứ tự gửi**:

```
#1 FAKE1   ┐
#2 REAL1   │ phần 1 (seq=0,  len=14)
#3 FAKE1   ┘
#4 FAKE2   ┐
#5 REAL2   │ phần 2 (seq=14, len=12)
#6 FAKE2   ┘
```

Gói giả nằm **đúng vị trí luồng** của phần thật tương ứng, đầy **byte rác `X`**.

| | Hành vi |
|:--|:--|
| **DPI** | **Ba segment `seq=0` và ba segment `seq=14`.** Segment nào là thật — **không phân biệt được từng gói** |
| **Máy chủ** | Bỏ gói giả vì **ACK sai** (`tcp_ack=-66000`), ghép `REAL1` + `REAL2` thành luồng gốc |

---

## 7. `fakeddisorder` — sáu segment, và phần 2 đến trước

`pos=midsld`

```
#1 FAKE2   ┐
#2 REAL2   │ phần 2 (seq=14) — ĐẾN TRƯỚC
#3 FAKE2   ┘
#4 FAKE1   ┐
#5 REAL1   │ phần 1 (seq=0)
#6 FAKE1   ┘
```

| | Hành vi |
|:--|:--|
| **DPI** | Mỗi phần có **ba bản sao**, và **cuối yêu cầu đến trước đầu yêu cầu** |
| **Máy chủ** | Bỏ giả vì ACK sai; giữ `REAL2` **trong bộ đệm cho tới khi** `REAL1` tới |

---

## 8. `hostfakesplit` — tên thật nằm giữa hai tên giả

Cắt đúng ranh giới tên: `host` = byte 11, `endhost` = byte 22. Dùng `tcp_md5`.

| # | Nhãn | seq | len | Nội dung | Máy chủ |
|--:|:--|:--|:--|:--|:--|
| 1 | **BEFORE** | 0 | 11 | phần đầu ClientHello | chấp nhận |
| 2 | **FAKE** | 11 | 11 | `u9a7bk2.org` | **bỏ (md5)** |
| 3 | **HOST** | 11 | 11 | `youtube.com` | chấp nhận |
| 4 | **FAKE** | 11 | 11 | `u9a7bk2.org` | **bỏ (md5)** |
| 5 | **AFTER** | 22 | 4 | phần đuôi ClientHello | chấp nhận |

| | Hành vi |
|:--|:--|
| **DPI** | **Đúng chỗ tên có ba segment cùng độ dài, cùng `seq`:** `u9a7bk2.org`, `youtube.com`, `u9a7bk2.org` |
| **Máy chủ** | Bỏ tên giả vì **chữ ký TCP MD5 sai** |

Đây là kỹ thuật **bám theo cấu trúc giao thức** — cắt đúng đường biên của tên
miền, thay vì cắt theo số byte.

---

## 9. `tcpseg` — dịch chuyển `seq`, không cắt

`pos=0,-1` + `seqovl=1`, kết hợp với instance `drop`

| # | Nhãn | seq | len | Máy chủ |
|--:|:--|:--|:--|:--|
| — | **ORIG** | 0 | 26 | **drop — không đi đâu cả** |
| 1 | **SEG** | **−1** | **27** | **cắt bỏ byte −1**, chấp nhận phần còn lại |

| | Hành vi |
|:--|:--|
| **DPI** | Luồng **bắt đầu sớm hơn một byte**, và byte đầu là **rác** → phân tích ClientHello có thể **sai lệch** |
| **Máy chủ** | Cắt bỏ byte **nằm bên trái cửa sổ nhận**, nhận phần còn lại. Gói gốc do instance `drop` bỏ |

**Khác `multisplit`:** ở đây ClientHello đi trong **một segment duy nhất**. Cơ chế
bảo vệ không phải "tên bị cắt" mà là "**luồng lệch vị trí**".

---

## 10. `oob` — chèn byte cờ URG giữa tên

`urp=midsld`. Luồng dài **27 byte**, byte OOB nằm **giữa tên**:

```
···········you·tube.com····          ← 27 byte
            ↑
         byte có cờ URG
```

| # | Nhãn | Mô tả | Máy chủ |
|--:|:--|:--|:--|
| 1 | **SYN** | `seq−1` — "SYN với số nhỏ hơn một: **chỗ cho byte thừa**" | chấp nhận |
| 2 | **DATA** | `URG`, len=27 | **rút byte URG ra**, chấp nhận phần còn lại |

| | Hành vi |
|:--|:--|
| **DPI** | Tên có **thừa một byte**: `you·tube.com` **≠** `youtube.com` |
| **Máy chủ** | **Lấy byte cờ URG ra khỏi luồng** như dữ liệu khẩn cấp → **tên khép lại** |

Kỹ thuật tinh vi nhất: nó không cắt, không giả — nó **chèn thêm byte** rồi để
stack TCP của máy chủ tự **bỏ byte đó đi**.

---

## 11. `syndata` — dữ liệu giả dính vào gói SYN

`blob=fake_default_tls`

| # | Nhãn | Nội dung | Máy chủ |
|--:|:--|:--|:--|
| 1 | **SYN+DATA** | `···········www.w3.org·····` | **chấp nhận SYN** |
| 2 | **SYN-ACK** | ← từ server | "dữ liệu trong SYN **không** được xác nhận" |
| 3 | **ORIG** | `···········youtube.com····` seq=0 len=26 | chấp nhận |

| | Hành vi |
|:--|:--|
| **DPI** | **Dữ liệu luồng đầu tiên đến trong gói SYN.** Nếu DPI coi đó là ClientHello, gói thật có thể không bị kiểm tra |
| **Máy chủ** | **Hầu hết stack TCP bỏ qua dữ liệu trong SYN** và chờ nhận lại sau bắt tay |

Giống `fake` ở chỗ "DPI đọc nhầm tên `www.w3.org` trước", nhưng ở **tầng thấp hơn** —
ngay trong gói mở kết nối.

---

## 12. Bảng so sánh

| Kỹ thuật | Số gói | Cơ chế bảo vệ máy chủ | Cái DPI không thấy |
|:--|--:|:--|:--|
| `fake` | 2 | MD5 sai | Tên thật — đã đọc `www.w3.org` |
| `multisplit` | 3 | Chuẩn TCP | Tên trọn trong **một** gói |
| `multidisorder` | 2 | Chuẩn TCP | Thứ tự bình thường trong luồng |
| `multidisorder_legacy` | 4 | Chuẩn TCP | Quan hệ A/B giữa hai gói |
| `fakedsplit` | 6 | ACK sai | Bản nào là thật giữa 3 bản |
| `fakeddisorder` | 6 | ACK sai | Cả bản sao **và** thứ tự |
| `hostfakesplit` | 5 | MD5 sai | Tên thật, giữa hai tên giả |
| `tcpseg` | 1 + drop | Cửa sổ nhận | Vị trí bắt đầu luồng |
| `oob` | 2 | Stack tự rút byte URG | Tên nguyên vẹn |
| `syndata` | 1 + 2 | Stack bỏ dữ liệu trong SYN | Dữ liệu đầu tiên của luồng |

### Fooling dùng trong mỗi kỹ thuật

| Kỹ thuật | Fooling |
|:--|:--|
| `fake`, `hostfakesplit` | `tcp_md5` |
| `fakedsplit`, `fakeddisorder` | `tcp_ack=-66000` |
| `multisplit`, `multidisorder`, `multidisorder_legacy`, `tcpseg`, `oob`, `syndata` | **không cần** — chỉ dựa vào chuẩn TCP |

> **Điều này giải thích `ts-and-fooling.md`:** kỹ thuật chia đoạn không cần fooling
> vì máy chủ vốn phải ghép lại. Fooling chỉ **bắt buộc** khi bạn **chèn thêm gói giả**
> vào luồng — lúc đó phải bảo đảm máy chủ vứt nó.

---

## 13. Sinh lại sơ đồ

Script sinh SVG cho cả 11 kỹ thuật:

```bash
python3 scripts/desync-anim.py                     # tất cả → Zapret2/desync/attachments/
python3 scripts/desync-anim.py /tmp/out fake oob   # chỉ hai kỹ thuật, ra thư mục tuỳ ý
```

Kiểu bản vẽ: dòng = một gói theo thứ tự gửi, trục ngang = vị trí byte trong luồng
TCP, ô = từng byte (giả thì vẽ `X`), và **dưới sơ đồ là bộ đệm máy chủ** với các
mảnh đã nhận đặt đúng chỗ. SVG có biến theme nên nhúng vào wiki là đổi màu theo
giao diện.

## 14. File đính kèm

| Vị trí | Nội dung |
|:--|:--|
| `Zapret2/desync/attachments/` | 44 tệp — ảnh minh hoạ + SVG sinh từ script trên |
| `virus/attachments/` | 63 ảnh — bằng chứng hình ảnh cho các ca nhiễm |
| `Zapret/attachments/` | 153 ảnh — ảnh chụp GUI, preset, hostlist |
| `DPI/attachments/` | 56 ảnh — kết quả đo DPI, sơ đồ phễu |

Toàn bộ wiki có **401 tệp đính kèm** (chủ yếu PNG/WebP), ngoài 283 tệp markdown.