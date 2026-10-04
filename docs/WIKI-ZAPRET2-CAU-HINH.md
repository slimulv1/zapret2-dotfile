# Zapret 2 — cấu hình thực hành: preset, profile, blob, orchestrator

Bổ sung cho [`ZAPRET2-WIKI-TONG-HOP.md`](ZAPRET2-WIKI-TONG-HOP.md) — ở đó là **ý
tưởng**, ở đây là **cú pháp và ví dụ thật** lấy từ các trang
`preset`, `profile`, `blob`, `circular`, `add-profile`, `log-analyzer` và nhóm
công cụ `find-*`.

---

## 1. Blob — dữ liệu nhị phân

> **Blob** là biến Lua kiểu `string`, chứa khối **dữ liệu nhị phân** dài tuỳ ý
> (từ 1 byte đến hàng gigabyte). Dùng để lưu gói giả và dữ liệu nhị phân khác.

### Ba blob chuẩn khởi tạo sẵn

#### `fake_default_tls` — **680 byte**

TLS ClientHello với SNI **`www.microsoft.com`**:

| Thành phần | Giá trị |
|:--|:--|
| Phiên bản TLS | 1.2 / 1.3 |
| Cipher suites | cipher hiện đại |
| **SNI** | **`www.microsoft.com`** (mặc định) |
| Hỗ trợ | HTTP/2 |
| Extension | `supported_groups`, `signature_algorithms`, `key_share`… |

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls
```

#### `fake_default_http` — **227 byte**

```http
GET / HTTP/1.1
Host: www.iana.org
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/109.0
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8
Accept-Encoding: gzip, deflate, br
```

> **Lưu ý mâu thuẫn với sơ đồ:** blob chuẩn dùng SNI `www.microsoft.com` và
> `Host: www.iana.org`, còn sơ đồ packet trong
> [`WIKI-DESYNC-PACKET-SO-DO.md`](WIKI-DESYNC-PACKET-SO-DO.md) dùng `www.w3.org`.
> Sơ đồ là **ví dụ minh hoạ**, không phải giá trị mặc định thật.

#### `fake_default_quic` — **620 byte**

Gói QUIC Initial tối thiểu hợp lệ: byte đầu `0x40` (QUIC long header), phần còn lại
là **toàn số 0**.

### Năm sửa đổi `tls_mod`

Hàm `tls_mod(blob, modlist, payload)`.

| Sửa đổi | Tác dụng |
|:--|:--|
| **`rnd`** | Thay trường **random** 32 byte trong TLS handshake bằng dữ liệu ngẫu nhiên → mỗi gói giả **độc nhất** |
| **`rndsni`** | Sinh tên miền ngẫu nhiên, thay SNI. Ví dụ `www.microsoft.com` → `a7b3c.com` |
| **`sni=<domain>`** | Đặt SNI cụ thể. Ví dụ `sni=www.google.com` |
| **`dupsid`** | Chép **Session ID từ handshake thật** (trong `payload`) — cần tham số thứ ba. Làm giả **giống thật hơn** |
| **`padencap`** | Thêm padding vào extension TLS, tăng kích thước gói |
| `none` | Không sửa đổi |

### Dùng blob

```bash
# Sửa một lần lúc khởi động
--lua-init="fake_default_tls = tls_mod(fake_default_tls,'rnd,rndsni')"

# Sửa mỗi lần gửi
--lua-desync=fake:blob=fake_default_tls:tls_mod=rnd,dupsid,sni=www.google.com

# Tạo blob riêng
--blob=myblob:0x1603010000                          # từ chuỗi hex
--blob=custom_tls:@/path/to/tls_clienthello.bin     # từ tệp
--blob=custom_tls:+100@/path/to/file.bin            # từ tệp, có offset

# Cấu hình thực tế cho YouTube
--payload=tls_client_hello \
--lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11:tls_mod=rnd,dupsid,sni=www.google.com
```

---

## 2. Preset — ba phần

### 1. Header và siêu dữ liệu

```bash
# Preset: 1
# ActivePreset: 1
# Modified: 2026-01-22T16:09:12.572985
```

Thông tin cho GUI: preset số mấy, có đang active không, sửa lúc nào.

### 2. Cấu hình toàn cục

```bash
--lua-init=@lua/zapret-lib.lua        # thư viện helper
--lua-init=@lua/zapret-antidpi.lua    # thư viện kỹ thuật vượt DPI
--lua-init=@lua/zapret-auto.lua       # tự động hoá + orchestration
--lua-init=@lua/custom_funcs.lua      # hàm của người dùng
--lua-init=@lua/custom_diag.lua       # chẩn đoán

--ctrack-disable=0        # BẬT conntrack
--ipcache-lifetime=8400   # cache IP sống 8400 giây (~2,3 giờ)
--ipcache-hostname=1      # cache hostname → IP
```

> **Không có dòng `--lua-init` thì không gì chạy được.** Đó là lý do các kỹ thuật
> `fake`, `multisplit`, `multidisorder` dùng được ngay — chúng đã nằm sẵn trong
> `zapret-antidpi.lua`.

**Bộ lọc bắt gói toàn cục** (ngôn ngữ Zapret2, có hướng `-in` / `-out`; mặc định
chỉ cần `-out`):

```bash
--wf-tcp-out=80,443,1080,2053,2083,2087,2096,8443
--wf-udp-out=80,443
--wf-raw-part=@windivert.filter/...
```

| Cổng | Ý nghĩa |
|:--|:--|
| `80` | HTTP |
| `443` | HTTPS / QUIC |
| `1080` | SOCKS — **Discord hay dùng** |
| `2053, 2083, 2087, 2096, 8443` | **Cổng thay thế của Discord** để tải media |

### 3. Blob

```bash
--blob=tls_google:@bin/tls_clienthello_www_google_com.bin
--blob=tls7:@bin/tls_clienthello_7.bin
--blob=fake_tls:@bin/fake_tls_1.bin
--blob=fake_default_udp:0x00000000000000000000000000000000
```

Preset thật của wiki liệt kê **hàng chục** blob: `tls1`…`tls18`, `tls_sber`,
`tls_vk`, `tls_vk_kyber`, `tls_deepseek`, `tls_max`, `tls_iana`, `tls_4pda`,
`tls_gosuslugi`, `syndata3`, `syn_packet`, `dtls_w3`, `quic_google`, `quic_vk`…

> Wiki ghi rõ: liệt kê hết blob trong preset là **không bắt buộc**.

---

## 3. Profile — giải phẫu thật

| Khái niệm | Là gì | Ví dụ |
|:--|:--|:--|
| **Preset** | Một tệp `.txt`: header chung + tập profile | `Default v1 (game filter)` |
| **Profile** | Một khối trong preset, tới trước `--new` | `youtube.com (giao diện)`, `Telegram`, `Cloudflare UDP` |

### Ví dụ thật — preset `Default v1` (bản 2.40, 08/2026)

```bash
--name=youtube.com (giao diện)
--filter-tcp=80,443
--hostlist=lists/youtube.txt
--out-range=-d8
--payload=tls_client_hello
--lua-desync=multisplit:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2:seqovl=1
```

**Đọc thành văn:** profile `youtube.com (giao diện)` nhặt kết nối TCP cổng 80 và
443 tới các domain trong `youtube.txt`. Trong các kết nối đó, **trong tám gói có
dữ liệu đầu tiên**, khi gặp TLS ClientHello thì chạy `multisplit`: cắt message ở
**nhiều chỗ quanh tên site**, và **dán thêm 1 byte chồng lấn** (`seqovl=1`) vào phần
đầu.

> **Chú ý phép tính vị trí tương đối:** `pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2`
> — nhiều marker, mỗi cái kèm độ lệch. Đây là cách cắt **nhiều chỗ** quanh tên
> miền, khác `multisplit` tối giản `pos=1,midsld`.

### Ba vai trò của cờ — đừng nhầm

| Cờ | Kiểm tra | Ví dụ |
|:--|:--|:--|
| **Lọc profile** | `--filter-tcp/udp`, `--filter-l7`, `--hostlist`, `--ipset` | TCP `80,443` + domain `youtube.txt` |
| **Lọc trong profile** | `--payload`, `--in-range`, `--out-range`, `dir` | `--out-range=-d8`, `--payload=tls_client_hello` |
| **Chiến lược** | `--lua-desync=...` | `multisplit:pos=...:seqovl=1` |

### Vì sao chỉnh **profile**, không đổi **preset**

Preset có sẵn, mỗi profile một chiến lược — nhưng những chiến lược đó **được chọn
dưới bầu trời nhà mạng của ai đó**, và DPI mỗi nhà mạnh mỗi vùng lại khác nhau.

Hệ quả điển hình: preset A mở được YouTube nhưng hỏng Discord, preset B thì ngược
lại. **Đổi preset cả bộ là vô ích** — mỗi lần lại đổi chiến lược **ở mọi profile**,
sửa site này lại hỏng site kia.

**Thứ tự đúng:**

1. Lấy preset làm nền, nơi **nhiều thứ nhất bạn cần vẫn chạy nhất**
2. Tìm profile mà site hỏng rơi vào (xem mục 6)
3. Chỉ đổi chiến lược **trong profile đó**
4. Kiểm từng chiến lược bằng **kết nối mới** (xem mục 7)

Bộ lọc và danh sách domain đã được gom sẵn và còn tốt — thường **không cần** đụng
tới. Từ nhà mạng này sang nhà mạng khác, cái đổi chủ yếu là **chiến lược nào lừa
được DPI của họ**.

> ⚠️ **Tên "Прямой запуск" gây hiểu nhầm.** Đó **không phải** một cách vượt đặc biệt,
> chỉ là khả năng chỉnh profile **một cái một cái**.

---

## 4. `circular` — orchestrator tự đổi chiến lược

Lua-orchestrator **tự chuyển** chiến lược desync khi phát hiện thất bại (RST,
retransmission, HTTP redirect của DPI).

> **Bắt buộc:** phải bắt traffic **đi vào** (`--in-range`) để phát hiện RST và
> HTTP response.

```bash
--lua-desync=circular[:param=val[:...]]
--lua-desync=<func>:strategy=1[:final]
--lua-desync=<func>:strategy=2
...
```

Mỗi instance phụ **bắt buộc** có `strategy=N`, N bắt đầu từ 1 **không bỏ số**.

### Tham số của `circular`

| Tham số | Ý nghĩa | Mặc định |
|:--|:--|:--|
| `fails=N` | Ngưỡng thất bại để đổi chiến lược | `3` |
| `time=N` | Xoá bộ đếm nếu lần thất bại gần nhất cách > N giây | `60` |
| `failure_detector=func` | Hàm Lua detector thất bại tuỳ biến | `standard_failure_detector` |
| `success_detector=func` | Hàm Lua detector thành công tuỳ biến | `standard_success_detector` |
| `hostkey=func` | Hàm sinh khoá host tuỳ biến | `standard_hostkey` |
| `key=string` | Tên bảng trong `autostate` để **tách trạng thái** giữa nhiều `circular` | tự động |
| `nld=N` | Cắt hostname còn N tầng (`static.a.google.com` → `google.com` khi `nld=2`) | không cắt |
| `reqhost` | Không chạy nếu hostname không rõ (chỉ có IP) | tắt |

### Detector thất bại — tham số TCP

| Tham số | Ý nghĩa | Mặc định |
|:--|:--|:--|
| `retrans=N` | Số retransmission = thất bại | `3` |
| `maxseq=N` | Chỉ tính retransmission trước relative sequence này | `32768` |
| `reset` | **Gửi RST cho bên retransmit** (đẩy nhanh việc đứt kết nối treo) | tắt |
| `inseq=N` | RST đi vào chỉ tính là thất bại trước rseq này | `4096` |
| `no_rst` | Tắt kích hoạt theo RST đi vào | tắt |
| `no_http_redirect` | Tắt kích hoạt theo HTTP redirect của DPI | tắt |

**UDP:** `udp_out=N` — thất bại nếu gói đi ra ≥ N (mặc định `4`);
`udp_in=N` — thất bại nếu gói đi vào ≤ N (mặc định `1`).

**Detector thành công:** `maxseq=32768`, `inseq=4096`, `udp_in=1`.

### Ví dụ đầy đủ

```bash
--in-range=-s5556
--out-range=-d1000
--lua-desync=circular:fails=1:time=300:retrans=3:nld=2
--lua-desync=multisplit:pos=2:strategy=1
--lua-desync=fake:blob=fake_default_http:strategy=2
--lua-desync=multidisorder:pos=host:strategy=3:final
```

| Tham số | Nghĩa |
|:--|:--|
| `fails=1` | Đổi chiến lược sau **1** lần thất bại |
| `time=300` | Xoá bộ đếm nếu lần thất bại gần nhất cách > **5 phút** |
| `retrans=3` | Thất bại = **3** retransmission |
| `nld=2` | Khoá host = domain 2 tầng (`google.com`) |
| `final` ở chiến lược 3 | Dừng xoay vòng tại đây |

### Chiến lược nhiều pha

Một chiến lược có thể gồm **nhiều instance cùng `strategy=N`** — `circular` chạy
tất cả theo thứ tự:

```bash
--lua-desync=circular:fails=1:time=300
--lua-desync=fake:blob=fake_default_http:repeats=4:strategy=1   # pha 1
--lua-desync=multisplit:pos=2:seqovl=211:strategy=1             # pha 2
--lua-desync=multidisorder:pos=host:strategy=2:final
```

Với `strategy=1` sẽ chạy `fake` → `multisplit`.

### Cách viết trong tệp `config`

Tham số trong `NFQWS2_OPT="..."` **được xuống dòng và thụt lề** — shell đọc chúng
như khoảng trắng thông thường:

```bash
NFQWS2_OPT="
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello
--out-range=-d1000
--in-range=-s5556
--lua-desync=circular:fails=1:time=300:retrans=3:nld=2
  --lua-desync=fake:blob=fake_default_http:repeats=4:strategy=1
  --lua-desync=multisplit:pos=2:seqovl=211:strategy=1
  --lua-desync=multidisorder:pos=host:strategy=2:final
--new
"
```

> Đây đúng là mẫu mà tệp `/opt/zapret2/config` của dự án `zapret2-dotfile` đang
> dùng.

### Cách hoạt động

1. Gói tin đi vào `circular` cùng `ctx`
2. `circular` lấy **kế hoạch** (toàn bộ instance phụ) và **huỷ vòng lặp C bình thường**
3. Kiểm tra detector thất bại/thành công cho kết nối hiện tại
4. Nếu số thất bại ≥ `fails` → chuyển sang chiến lược kế tiếp `(N % total) + 1`
5. Nếu tới chiến lược `final` → **dừng xoay**
6. Chỉ chạy các instance có `strategy=` chiến lược hiện tại

> **Trạng thái** (số chiến lược, bộ đếm thất bại) lưu **theo từng host** trong bảng
> toàn cục `autostate` và **sống sót qua các kết nối riêng**.

---

## 5. Thêm profile của riêng bạn

`add-profile` là hướng dẫn **copy một preset** rồi thêm profile mới:

1. Sao chép preset làm nền
2. Tạo profile mới
3. Đưa domain vào `hostlist` của profile
4. Chọn chiến lược
5. **Đặt profile đúng thứ tự**
6. Kiểm tra trung thực (xem mục 7)

---

## 6. Tìm profile của một site

### Qua DevTools (F12)

`find-site-domains`:

1. Mở panel nhà phát triển → tab **Network**
2. Đọc bảng request
3. **Phân biệt status nghĩa là bị chặn bởi DPI** với lỗi trình duyệt (CORS, chứng
   thư)
4. Gom domain vào hostlist
5. **Kiểm lại trong chính tab đó**

> Bắt đầu từ **subdomain nhỏ** trước.

### Qua CDN

`find-domain-owner`: nhận diện CDN (Akamai, Cloudflare, Amazon) để biết profile
nào trong preset áp dụng. Công cụ: tiện ích trình duyệt `ipvfoobarbaz` + tra IP ở
`ipinfo.io`.

Sau khi biết CDN, chọn profile có subnet tương ứng — hoặc dùng **subnet thay vì
domain** cho profile đó.

### Qua log

`log-analyzer` cho phép thấy **profile nào thực sự chiếm** một kết nối.

---

## 7. Kiểm tra trung thực

`verify-strategy` — **hai bẫy**, xem lại ở
[`ZAPRET2-WIKI-TONG-HOP.md`](ZAPRET2-WIKI-TONG-HOP.md) mục 19.

Checklist rút gọn:

1. Đóng hẳn trình duyệt, mở lại (hoặc cửa sổ ẩn danh mới)
2. **Kết nối MỚI** — không phải F5
3. Kiểm bằng **đúng thứ bạn dùng thật**
4. Chưa được thì tắt Zapret xem site có chạy không; nếu chạy → cần `pass`, không
   cần đánh lừa

---

## 8. Đọc log

`log-analyzer`:

- Bật: `--debug=@logs/<tên_preset>_debug.log`
- Bảng **connections**: host, IP, cổng, giao thức, profile khớp, bộ đếm, danh sách
- Nếu profile **có tên**, analyzer tự lấy từ log → thấy `7 (youtube.com QUIC)` thay
  vì `7`
- Click một connection → bảng **từng gói**: hướng, cờ TCP, loại payload, **hàm Lua
  nào thực sự đã desync**, verdict
- **`drop` màu đỏ trên SYN hoặc ClientHello gửi đi thường là bình thường**

---

## 9. `wssize` — khi nào dùng, khi nào không

> Wiki nhấn mạnh: `--wssize` chỉ nên là **phương án cuối**. Lý do:
>
> - **Không** dùng được với bộ lọc hostlist và l7
> - **Làm chậm mọi kết nối** trên các cổng bị lọc
>
> Vì vậy blockcheck đặt chiến lược `wssize` **ở cuối log**:
> - chế độ **standard**: chỉ thử `wssize` cho TLS 1.2, và **chỉ khi** toàn bộ phần thử
>   không `wssize` mà không tìm được gì
> - chế độ **force**: chạy lại toàn bộ danh sách kèm `wssize`
>
> **Nếu log có chiến lược chạy được mà không kèm `wssize`, hãy lấy cái đó.**

Trong Zapret 2: `--wssize` → `--lua-desync=wssize`; `--wsize` → `--lua-desync=wsize`.

---

## 10. Index

| Trang | Nội dung |
|:--|:--|
| `preset` | Ba phần của preset, ví dụ đầy đủ, cùng preset dạng `.bat` |
| `profile` | Giải phẫu profile thật từ `Default v1`, ba vai trò cờ |
| `blob` | Ba blob chuẩn (kích thước + nội dung), năm `tls_mod`, tạo blob riêng |
| `circular` | Orchestrator: bảng tham số đầy đủ, detector, chiến lược nhiều pha |
| `add-profile` | Thêm profile của riêng bạn, 6 bước |
| `log-analyzer` | Bật debug log, bảng connections và packets |
| `find-site-domains` | Tìm domain qua F12 |
| `find-domain-owner` | Tìm CDN, tìm profile theo subnet |
| `find-game-strategy` | Gom IP game bằng TCPView, profile riêng, UDP `payload=all` |
| `verify-strategy` | Hai bẫy kiểm tra |
| `ts-and-fooling` | Vì sao fake phải "chết"; nền tảng quyết định |
| `steam` | Domain, cổng, CDN của Steam |
| `profile-independence` | Một kết nối — một profile |
| `roadmap обучения` | Lộ trình học 7 cấp, 4 phòng thí nghiệm |
| `всякий мусор` *(bản nháp)* | Chiến lược `tcpseg` thử nghiệm: seqovl không cắt, dup, sinh SNI động |