# Ghi chú nghiên cứu — nâng cấp tầng 1 (zapret2)

Ngày: 2026-09-29 · nhánh `test/opt-dpi`
Mục đích: xem tầng 1 có thể mạnh thêm được không, và mạnh thêm bằng cách nào.

Mọi khẳng định ở đây gắn với nguồn. Chỗ nào **chưa** kiểm chứng được trên máy
này thì ghi rõ, không đoán.

---

## 1. Cấu hình đang chạy

`config/z2d-zapret2-opt` → `/opt/zapret2/config`:

```
--filter-tcp=80  --filter-l7=http --payload=http_req
  --lua-desync=fake:blob=fake_default_http:tcp_md5
  --lua-desync=multisplit:pos=method+2

--filter-tcp=443 --filter-l7=tls  --payload=tls_client_hello
  --lua-desync=multisplit:pos=1
```

Đo được trên máy, những thứ **không** có trong cấu hình:

| thiếu | hệ quả |
|---|---|
| profile UDP/443 (QUIC) | HTTP/3 đi qua DPI không được xử lý |
| `ip_ttl` / `ip_autottl` | fake không có giới hạn hop, không né được DPI có giới hạn TTL |
| `repeats` | chỉ giả đúng 1 gói |
| `tls_mod` | ClientHello giả giống hệt thật, dễ bị so khớp |
| autohostlist | không tự phát hiện tên miền bị chặn |

`MODE_FILTER=hostlist` nhưng `z2d-hosts-user.txt` và `z2d-exclude.txt` **rỗng**.
Theo tài liệu zapret2: *"если есть фильтры по хостлистам, и есть хотя бы один домен в
любом хостлисте …, то профиль никогда не будет выбран при отсутствующем имени хоста"* —
không có miền nào trong bất kỳ hostlist nào thì **profile không bị loại**, nên
desync áp cho mọi kết nối. Điều này khớp với phép đo: mọi kết nối HTTPS đều ra
đoạn đầu 1 byte.

---

## 2. Dữ kiện quan trọng nhất: đường truyền này KHÔNG có DPI

Đo bằng cách **dừng hẳn zapret2** rồi thử trực tiếp:

| trang | zapret2 tắt |
|---|---|
| github.com | `200` |
| youtube.com | `301` |
| facebook.com | `301` |
| reddit.com | `301` |
| telegram.org | `200` |

Không trang nào chết. Tức là **không có gì để vượt**.

Hệ quả trung thực, nói thẳng:

- **Không thể chứng minh cấu hình nào "vượt DPI tốt hơn" trên đường này.** Phép
  đo đó không tồn tại, không phải là tôi chưa tìm ra cách đo.
- Cấu hình hiện tại đang tốn công trên **mọi** kết nối TLS mà không thu được gì.
- Đường dùng để đo phải là **đường có DPI**. Cách duy nhất tôi có ở đây là
  lab DPI giả (`tests/lab/dpi.py`) — nó đo được, nhưng nó là **mô hình**, không
  phải DPI của nhà mạng.

Vì vậy phần nâng cấp chia làm hai, tách bạch:

1. **Đo được** — chi phí, độ trễ, việc desync có thật sự bắn, và việc có làm hỏng
   trang nào không. Tất cả đo trên máy thật.
2. **Chỉ theo tài liệu** — chiến lược nào mạnh hơn về nguyên tắc. Đo bằng lab
   DPI, và ghi rõ lab là mô hình.

---

## 3. Tổng hợp từ tài liệu và cộng đồng

### 3.1 Các cờ `--lua-desync` (nguồn: `wiki.zapret.moe/Zapret2/desync`, `docs/manual.md`)

| hàm | làm gì | tham số riêng |
|---|---|---|
| `multisplit` | chia payload thành nhiều đoạn TCP | `pos=`, `seqovl=`, `seqovl_pattern=`, `blob=`, `nodrop` |
| `multidisorder` | chia, rồi gửi **ngược thứ tự** | như trên |
| `fake` | bơm gói giả trước dữ liệu thật | `blob=` (bắt buộc), `tls_mod=`, `repeats=` |
| `fakedsplit` | fake + chia dữ liệu thật | `pos=`, `nofake1..4`, `pattern=` |
| `hostfakesplit` | fake **chỉ phần host** + chia | `host=`, `midhost=` |

Về *fooling* — thứ quyết định gói giả có bị DPI xử lý hay không:

| tham số | nghĩa |
|---|---|
| `ip_ttl=N` / `ip6_ttl=N` | TTL của gói giả |
| `ip_autottl=delta,min-max` | **tự** dò TTL, không phải đoán |
| `tcp_md5[=hex]` | thêm tuỳ chọn MD5 vào TCP — nhiều DPI không xử lý được |
| `tcp_seq=N` / `tcp_ack=N` | dịch sequence/ack ⇒ server thật **loại**, DPI thì giữ |
| `badsum` | checksum L4 sai |

Ánh xạ từ nfqws1 sang nfqws2 (nguồn: wiki.zapret.moe): `md5sig` → `tcp_md5`,
`badseq` → `tcp_seq=-10000` (SYN) hoặc `tcp_ack=-66000` (dữ liệu), `datanoack` →
`tcp_flags_unset=ack`.

### 3.2 Công thức chuẩn của dự án

Trích nguyên văn `wiki.zapret.moe/Zapret2/desync/fake` — *"Типовая боевая связка
fake + multisplit"*:

```
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid,padencap \
  --lua-desync=multisplit:pos=1,midsld
```

Cùng trang đó cảnh báo điều **then chốt của cả tầng 1**:

> *«**fake без ограничителей на tcp = гарантированный слом соединения**»* —
> `fake` không có bộ giới hạn trên TCP thì **chắc chắn hỏng kết nối**.

Cơ chế: gói giả phải bị **server thật** loại mà **DPI không loại**. Không có
fooling thì server nhận nhầm gói giả là dữ liệu thật và luồng hỏng.

Cùng nguồn cũng nói rõ vai trò của từng mảnh:

| fooling | ai loại gói giả |
|---|---|
| `tcp_md5` | server Linux loại (MD5 chưa bật) — **phổ biến nhất** |
| `ip_ttl` | router loại — chỉ khi DPI **gần client hơn server** |
| `badsum` / `tcp_seq` | server loại do checksum / seq lệch |

Về vì sao `multisplit` trần là không đủ:

> *«разрез сам по себе не обманет — системы, умеющие реассемблирование, его не
> примут; поэтому `multisplit` обычно комбинируют с фейковыми пакетами»*

Cấu hình cũ của repo đúng là `multisplit:pos=1` trần — loại mà tài liệu nói
riêng là **không đủ**.

### 3.3 QUIC

Công thức riêng cho UDP, lấy từ cùng trang:

```
--payload=quic_initial --lua-desync=fake:blob=fake_default_quic:ip_ttl=1:ip6_ttl=1
```

Hai điểm bắt buộc phải biết trước khi dùng:

1. **Fooling của TCP vô nghĩa với UDP.** `tcp_md5` là *tuỳ chọn TCP*, đặt vào
   gói UDP nghĩa là không có tác dụng. Với UDP chỉ dùng được `ip_ttl`,
   `ip6_ttl`, `badsum`, `ipfrag`.
2. **Không tách (split) được trên UDP.** Mỗi datagram tự chứa trọn, cắt thành
   nhiều datagram là sai bản chất. Với QUIC chỉ dùng `fake` hoặc `ipfrag`.

Đáng chú ý: `config.default` của zapret2 mặc định **đã có** `NFQWS2_PORTS_UDP=443`,
nhưng cấu hình của repo không dựng profile UDP nào — nên cổng đó được mở ra rồi
để không.

### 3.4 autohostlist

`MODE_FILTER=autohostlist` tự thêm tên miền vào `/opt/zapret2/ipset/zapret-hosts-auto.txt`
khi phát hiện kết nối thất bại lặp lại (`AUTOHOSTLIST_RETRANS_THRESHOLD=3`,
`FAIL_THRESHOLD=3`, trong cửa sổ `FAIL_TIME=60`). Nguồn: `deepwiki.com/remittor/zapret-openwrt`,
`deepwiki.com/bol-van/zapret2`.

Đây là **thứ tự thích nghi tự động** — thay vì đoán trước danh sách tên miền
cần vượt, hệ thống tự phát hiện theo phản hồi thật của đường truyền.

Điểm phải cân: autohostlist **chỉ có tác dụng khi có DPI**. Trên đường không DPI
nó không bao giờ kích hoạt — tức miễn phí, nhưng cũng không thay đổi gì.

---

## 4. Phép đo — `tests/bench-dpi.py`

Ba phép đo tách rời, không suy ra nhau:

1. **Có DPI không** — dừng hẳn zapret2, thử 5 trang.
2. **Desync có ẩn tên miền không** — bắt gói thẳng trên dây (tắt offload), rồi
   **tách SNI trong đoạn đầu** bằng đúng bộ tách của lab DPI.
3. **Tốn bao nhiêu** — độ trễ tới byte đầu, thời gian CPU của `nfqws2`, và cả
   HTTP/3 (`curl --http3`) đo tách riêng.

### 4.1 Bẫy của chính bộ đo — đã dính, đã sửa

Bản đầu đo bằng **kích thước đoạn đầu** rồi kết luận "desync có chạy". Chạy thử
lộ ngay: ứng viên có `fake` cho đoạn đầu **680 byte**, không phải 1 byte — vì đo
đúng **gói giả**, không phải đoạn tách.

Số đo đúng cho "desync có chạy" nhưng **sai** cho câu hỏi quan trọng hơn: *desync
có ẩn tên miền không?* Đã đổi sang đọc SNI. Sửa xong mới thấy được điều cốt
lõi ở mục 4.3.

### 4.2 Kết quả

Đo ngày 2026-09-29, `enp8s0`, 5 lượt × 5 trang, curl có HTTP3.

| ứng viên | TCP | HTTP/3 | SNI ẩn | trễ TB | CPU |
|---|---|---|---|---|---|
| `baseline` (đang chạy) | 5/5 | 5/5 | ✓ | 244.6 ms | 0.01 s |
| **`canonical`** | 5/5 | 5/5 | ✓ | 237.4 ms | 0.00 s |
| **`canonical+quic`** | 5/5 | 5/5 | ✓ | 237.3 ms | 0.01 s |
| `fakeddisorder` | 5/5 | 5/5 | ✓ | **281.0 ms** | 0.00 s |
| `nofool-fake` | **0/5** | **3/5** | ✗ | — | — |

Cột trễ giữa ba ứng viên an toàn (237–245 ms) là **nhiễu đo**, không phải khác
biệt thật. Chỉ `fakeddisorder` nổi hẳn: **+15%** so với `canonical`.

### 4.3 Cảnh báo của bol-van được tái tạo bằng phép thử

Ứng viên `nofool-fake` — `fake` **không** kèm fooling — làm **hỏng cả 5 trang
TCP** và 2/5 trang HTTP/3. Và đoạn đầu của nó mang:

```
SNI = www.microsoft.com
```

Đó là tên miền của **gói giả**, không phải trang thật. Nên nó vừa chứng minh
cơ chế (DPI thấy nhầm tên), vừa chứng minh hậu quả (server thật không loại gói
giả nên luồng chết).

Đây không phải chuyện "tôi tin tài liệu" — đây là lỗi thật, tái hiện được,
và giờ đã có `tests/test_config.py` chặn nó.

### 4.4 TTL thật của máy

Đo bằng `ping` để chọn khoảng cho `ip_autottl` — tham số này là **"delta từ TTL
của server"**, khoảng mẫu trong tài liệu là `40-64`, **không phải** `3-20` như
tôi đoán ban đầu.

| đích | TTL về tới | suy ra TTL xuất phát |
|---|---|---|
| 1.1.1.1 | 52 | ~56 |
| 8.8.8.8 | 111 | ~115 |

Không dùng `ip_autottl` — xem mục 5.

---

## 5. Quyết định, từng thứ một

| ý tưởng | đo được không ở đây | quyết định |
|---|---|---|
| `fake` + `tcp_md5` + `tls_mod` cho 443 | lợi ích **không**; chi phí **có** | **làm** — chuẩn của dự án, đo ra chi phí ~0 |
| profile QUIC/443 | lợi ích **không**; hỏng HTTP/3 **có** | **làm** — đo 5/5 nguyên vẹn, CPU +0.01 s |
| `fakeddisorder` | chi phí **có** | **không** — đo ra +15% độ trễ, lợi ích không chứng minh được |
| `ip_autottl` | **không** có gì | **không** — tài liệu nói `ip_ttl` chỉ dụng được khi DPI **gần client hơn server**; ở đây không có DPI nên không có cách biết DPI ở đâu. Dùng `tcp_md5` để **server** tự loại gói giả, không phải đoán vị trí DPI |
| thêm cổng Discord (1080, 2053…) | **không** | **không** — tầng 2 đã chặn Discord theo tên miền; thêm cổng chỉ tăng CPU |
| bật `MODE_FILTER=autohostlist` | lợi ích **không**; tiết kiệm CPU **không đáng kể** | **không** — xem mục 6 |

Nguyên tắc dẫn đường: **cái nào không đo được lợi ích thì chỉ thêm khi tài liệu
nói rõ là chuẩn VÀ chi phí đo được là không đáng kể.** `fakeddisorder` rơi vào
ngược lại: chi phí đo ra rõ ràng, lợi ích thì không.

---

## 6. Đề xuất chưa áp dụng — `autohostlist`

Không bật, và đây là lý do để bàn thay vì giấu:

- **Lợi ích duy nhất đo được ở đây là CPU — và nó nằm trong nhiễu** (0.00 s vs
  0.01 s). Nên lý do "tiết kiệm hiệu năng" không đứng được.
- Lợi ích thật của nó là **tự thích nghi khi có DPI** — không đo được ở đây.
- Nó đổi **ngữ nghĩa tầng 1**: hiện tại desync áp cho mọi kết nối TLS (vô hại
  nhưng tốn công); bật autohostlist thì chỉ áp cho tên miền bị nghi chặn. Với
  tầng 1 đóng vai "lưới an toàn", đó là đổi cấu trúc, không phải tinh chỉnh.
- Nó **ghi đè** `/opt/zapret2/ipset/zapret-hosts-auto.txt` — trạng thái động
  nằm ngoài repo, khó truy vết.

Cách dùng đúng, nếu muốn: bật khi **biết chắc đang ở trên đường có DPI** (4G,
điểm công cộng, nước khác), tắt lại khi về nhà. Và phải đo lại — `bench-dpi.py`
tự phát hiện có DPI không trước khi đo, nên chỉ cần chạy lại nó ở chỗ mới.

---

## 7. Giới hạn của việc kiểm này

- **Không có DPI thật trên đường này.** `blockcheck2.sh` — công cụ thử DPI của
  chính zapret2 — xác nhận: `rutracker.org` (tên miền mặc định của nó, bị chặn
  nặng ở Nga) `working without bypass` trên cả IPv4 lẫn IPv6, HTTP/1.1, TLS 1.2
  và HTTP/3. Không phải tôi không tìm ra cách đo — **không có gì để vượt**.
- Vì vậy cột "SNI ẩn" nói về **nguyên lý** của chiến lược trên dây, **không**
  phải bằng chứng vượt được DPI. Lab DPI trong `tests/lab/dpi.py` là **mô hình**
  DPI chỉ-soi-đoạn-đầu, không phải DPI của nhà mạng Việt Nam.
- **`curl` và trình duyệt có vân tay TLS khác nhau.** Chính
  `wiki.zapret.moe/Zapret2/verify-strategy` cảnh báo: autotun kiểm bằng `curl`
  còn người dùng ngồi trong trình duyệt thì "chiến lược chạy" mà trang vẫn
  không mở, và ngược lại. Muốn kết luận thật thì phải thử trong trình duyệt,
  **kết nối mới** (F5 thường nói dối vì tái dùng kết nối cũ, mà desync chỉ có
  tác dụng lúc thiết lập kết nối).
- **Không có nguồn nào** mô tả DPI của VNPT, FPT hay Viettel ở mức đủ để chỉ
  định cờ. Tài liệu Việt Nam tìm được chỉ dừng ở mức dùng lại cấu hình của
  người Nga. Nên "chọn cờ nào cho nhà mạng Việt Nam" **không có căn cứ để trả
  lời chắc**, và tôi không bịa.

---

## 8. Nguồn

- `github.com/bol-van/zapret2` — README và `docs/manual.md`
- `wiki.zapret.moe/Zapret2/desync` — bảng tham số đầy đủ
- `wiki.zapret.moe/Zapret2/desync/fake` — công thức chuẩn, cảnh báo fooling
- `wiki.zapret.moe/Zapret2/desync/fakeddisorder` — chiến lược đảo thứ tự
- `wiki.zapret.moe/Zapret2/verify-strategy` — bẫy của cách kiểm
- `github.com/bol-van/zapret/discussions/1500` — cấu hình theo nhà mạng Nga
- `deepwiki.com/bol-van/zapret2` — kỹ thuật anti-DPI và autohostlist
- `deepwiki.com/Flowseal/zapret-discord-youtube` — phân tích bộ kỹ thuật DPI
- `deepwiki.com/remittor/zapret-openwrt` — cơ chế autohostlist
- `/opt/zapret2/config.default` và `/opt/zapret2/blockcheck2.sh` trên máy
