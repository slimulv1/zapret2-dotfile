# Zapret 2 (nfqws2) — tổng hợp từ wiki.zapret.moe

Tài liệu tham khảo tổng hợp toàn bộ nội dung **Zapret 2** của wiki
<https://wiki.zapret.moe/> (namespace `Zapret2/` — 42 trang, cộng giáo trình
`Zapret/manual/zapret2_*` và nền tảng `DPI/`).

### Tám tài liệu trong bộ

| Tài liệu | Phạm vi |
|:--|:--|
| **Tài liệu này** | `Zapret2/` (42 trang) — lõi `nfqws2`, Lua, profile, desync |
| [`WIKI-ZAPRET2-CAU-HINH.md`](WIKI-ZAPRET2-CAU-HINH.md) | `Zapret2/` — preset, profile thật, blob, orchestrator `circular`, log analyzer |
| [`WIKI-DESYNC-PACKET-SO-DO.md`](WIKI-DESYNC-PACKET-SO-DO.md) | `scripts/desync-anim.py` — **sơ đồ packet từng byte** của cả 11 kỹ thuật |
| [`WIKI-ZAPRET1-THAM-CHIEU.md`](WIKI-ZAPRET1-THAM-CHIEU.md) | `Zapret/` (86 trang) — cờ `nfqws`, hostlist/ipset/hosts, cài Linux, chẩn đoán |
| [`WIKI-ZAPRET-NENH-TANG-GAME.md`](WIKI-ZAPRET-NENH-TANG-GAME.md) | `Zapret/` — router, Android, Steam, game, bộ `.bat` sẵn, `wssize` |
| [`WIKI-DPI-TSPU.md`](WIKI-DPI-TSPU.md) | `DPI/` (30 trang) — phễu kiểm tra, bắt DNS, vân tay JA4, diễn biến 2026 |
| [`WIKI-PROXY-VPN-CONG-CU.md`](WIKI-PROXY-VPN-CONG-CU.md) | Proxy/VPN (97 trang) — xray, VLESS, REALITY, Clash, sing-box, Hysteria, MTProxy |
| [`WIKI-VAN-DE-AN-TOAN.md`](WIKI-VAN-DE-AN-TOAN.md) | Bảo mật (47 trang) — virus giả, chứng thư НУЦ, root Android, FIDO |

**Tổng: 283 trang markdown + 401 tệp đính kèm — toàn bộ wiki đã được cào.**

---

## 0. Nguồn và cách thu thập

| Mục | Giá trị |
|:--|:--|
| Nguồn nội dung | `https://wiki.zapret.moe/` (wiki.js) |
| Nguồn markdown gốc | `https://git.zapret.moe/zapretdiscordyoutube/todo` (Forgejo) |
| Sitemap | `https://wiki.zapret.moe/sitemap.xml` — tổng **282** trang |
| Repo nguồn | **283** file `.md` |
| Đối chiếu sitemap ↔ repo | **282/282 trang khớp**; 1 trang chỉ có trên wiki không có trong repo (`nuc/nuc-root-browsers`) → đã lấy trực tiếp |
| Tác giả phần mềm | [bol-van](https://github.com/bol-van/zapret2) |
| Tài liệu chính thức | `docs/manual.md` trong repo `bol-van/zapret2` |
| Ngày thu thập | 2026-10-04 |

**Cách lấy nhanh toàn bộ wiki dạng markdown gốc** (trang wiki tự trỏ link tới
repo nguồn ở cuối mỗi bài):

```bash
git clone --depth 1 https://git.zapret.moe/zapretdiscordyoutube/todo.git
```

> **Lưu ý về nội dung.** Wiki được viết chủ yếu cho **Zapret GUI trên Windows**
> (`winws2.exe`). Phần lõi `nfqws2` trên Linux là cùng một chương trình nên mọi
> thứ về Lua, profile, filter, desync, verdict trong tài liệu này **áp dụng nguyên
> vẹn**. Riêng mục `--wf-*` (WinDivert) là của Windows, không có trên Linux —
> trên Linux vai trò tương đương do nftables/iptables đảm nhiệm.
>
> Trang cũng tự khai báo mọi bài viết mở để dùng cho AI:
> *«При желании вы можете натренировать ИИ на наших статьях»*.

---

## 1. Zapret 2 là gì

> **Định nghĩa của tác giả (bol-van):**
> *«zapret2 là một bộ thao túng gói tin, nhiệm vụ chính là thực hiện các cuộc tấn
> công tự trị nhắm vào DPI theo thời gian thực nhằm vượt qua các hạn chế (chặn
> truy cập) của tài nguyên hoặc giao thức mạng. Tuy nhiên khả năng của zapret2
> không giới hạn ở đó. Kiến trúc cho phép thực hiện các loại thao túng gói tin
> khác…»*

Bốn mảnh của định nghĩa:

1. **Bộ thao túng gói tin.** Nền tảng không phải "phép thuật vượt chặn" mà là
   khả năng phổ quát: bắt gói tin lúc bay, sửa / thay / cắt / nhân bản / phát
   gói tin tự chế. Mọi thứ khác chỉ là lớp trên đó.
2. **Tấn công tự trị, thời gian thực.** "Tấn công" ở đây là các thao tác *desync*
   (đánh lừa): gói tin được tạo sao cho DPI ghép được bức tranh sai hoặc thiếu
   chữ ký, còn máy chủ nhận việc tái dựng đúng theo chuẩn TCP/IP. "Tự trị" —
   chạy ngay trên máy người dùng, không cần máy chủ trung gian, không sửa ứng
   dụng. **Không phải VPN, không phải proxy.**
3. **Vượt hạn chế ở mức tài nguyên lẫn giao thức.** Không chỉ mở một trang web,
   mà cả khi DPI bóp/đứt QUIC, WireGuard hay nhắn tin dựa trên chữ ký.
4. **Không giới hạn ở vượt chặn.** Cùng kiến trúc dùng được cho **hai chiều
   (client + server) obfuscation** — ngụy trang giao thức để DPI không nhận ra
   đang chạy gì, khác với desync (giao thức vẫn thấy được, chỉ là phân tích bị đánh lừa).

### DPI là gì

DPI (*Deep Packet Inspection*) là thiết bị đọc nội dung gói tin và theo chữ ký
(domain trong SNI của TLS, header `Host:` của HTTP) quyết định cho qua hay chặn.
Ở Nga, hệ thống đó gọi là **ТСПУ** (*Технические средства противодействия
угрозам*). Wiki có mục riêng: [`DPI/DPI`](https://wiki.zapret.moe/DPI/DPI).

---

## 2. Khác biệt với Zapret 1 (`winws`, `nfqws`)

| | Zapret 1 | Zapret 2 |
|:--|:--|:--|
| Nơi chứa logic thuật toán | Hardcode trong C | Tách ra **Lua** |
| Sửa thuật toán | Sửa C + biên dịch lại | Sửa file `.lua` text, xong chạy |
| Thời gian phản ứng khi TСПУ đổi | Chờ tác giả phát hành bản mới | Tự sửa và thử ngay |
| Chia sẻ cách vượt chặn | Khó (phải biên dịch) | Gửi file Lua / file txt preset |
| Rủi ro "bus factor" | Cao | Thấp |

Zapret 1: công cụ làm đúng những gì tác giả nhồi lúc build.
Zapret 2: **bộ khung**, cách vượt chặn được ghép, đổi và tinh chỉnh khi có
chặn mới.

---

## 3. Kiến trúc dự án

### TL;DR

- **`nfqws2`** (Linux) / `winws2` (Windows) / `dvtws2` (BSD) — **lõi C**.
  Bắt gói tin, lọc, nhận diện giao thức, quản lý danh sách — nhưng **không tự
  "đánh lừa"**.
- **Lua** — toàn bộ logic vượt DPI.
- **Bắt gói tin từ kernel**: Linux — `iptables`/`nftables`; FreeBSD — `ipfw`;
  OpenBSD — `pf`; Windows — driver WinDivert ngay trong `winws2`.
- **Lõi tối thiểu** = bắt gói từ kernel + `nfqws2` + Lua. Mọi thứ khác
  (script khởi chạy, `blockcheck2`, `mdig`, `ip2net`) là phụ, tuỳ chọn.
- **macOS không hỗ trợ** — không có cơ chế bắt gói phù hợp.

### Lõi C `nfqws2`

Chọn C vì tốc độ: xử lý từng gói tin thời gian thực, ngôn ngữ chậm không dùng
được. `nfqws2` gánh:

- bắt gói tin từ network stack OS
- lọc cơ bản (cổng, giao thức) — xem `filter`
- nhận diện giao thức và loại payload (TLS ClientHello, HTTP request, QUIC Initial…)
- hỗ trợ hostlist / ipset
- **hostlist tự động**: tự phát hiện tên miền bị đứt kết nối rồi thêm vào danh sách
- hệ thống nhiều profile
- gửi **raw packet** — nền tảng cho `fake` và cắt đoạn
- các chức năng dịch vụ khác

> **Điểm mấu chốt:** trong `nfqws2` **không có logic tác động lên lưu lượng**.
> Nó bắt, nhận diện, gửi được — nhưng *làm sao để đánh lừa DPI* thì quyết
> định ở Lua. Đây chính là ý tưởng cốt lõi của Zapret 2.

### Các tệp Lua

| Tệp | Vai trò |
|:--|:--|
| `zapret-lib.lua` | Thư viện hàm nền: xử lý blob, cắt/gửi segment, kiểm tra hướng… Mọi script khác dựa vào đây |
| `zapret-antidpi.lua` | **Thư viện các thao tác tấn công DPI** — các hàm desync (`fake`, `multisplit`, `syndata`…), gọi qua `--lua-desync` |
| `zapret-auto.lua` | Quyết định động (orchestration): chọn thao tác theo hành vi mạng |

Ngoài bắt buộc:

| Tệp | Vai trò |
|:--|:--|
| `zapret-tests.lua` | Test các hàm C (nhận diện giao thức, phân giải vị trí cắt…) |
| `zapret-obfs.lua` | Obfuscation giao thức (khác với vượt chặn) |
| `zapret-pcap.lua` | Ghi pcap để mở bằng Wireshark |

**Yêu cầu:** LuaJIT 2.1+ hoặc PUC Lua 5.3+. Bản cũ hơn không tương thích, không
hỗ trợ.

### Thành phần phụ

- **Script khởi chạy (Linux)**: `init.d`, `common`, `ipset`, `install_easy.sh`,
  `uninstall_easy.sh`, `blockcheck2` (tự động dò chiến lược).
- **`mdig`** — resolver hostlist đa luồng, không giới hạn số lượng.
- **`ip2net`** — gom các IP lẻ thành subnet để danh sách gọn và nhanh.

> **Tệp `config` chỉ dành cho script khởi chạy.**
> Mọi cấu hình của script khởi chạy nằm ở tệp `config` ở gốc dự án. `nfqws2`
> **không biết và không đọc** tệp này — tham số được truyền thẳng qua cờ.

### Nền tảng

Script cài đặt nhắm: Linux **systemd** hoặc **OpenRC**; firmware **OpenWrt**.

---

## 4. Pipeline xử lý một gói tin

Tóm tắt một dòng:

```
Kernel OS → bắt gói + lọc sớm → dissect → conntrack → payload type & stream proto
→ (nếu cần) reasm/decrypt → chọn profile theo filter
→ chuỗi Lua instance + verdict → verdict tổng hợp
→ gửi / sửa / drop → chờ gói sau
```

### Các chặng

**Chặng 0 — Vì sao phải chuyển gói sang user space.**
`nfqws2` chạy ở **user space**, không phải kernel. Chuyển gói qua lại giữa kernel
và user space tốn kém (context switch cho mỗi gói). Nên quy tắc: **càng loại sớm
càng tốt**.

**Chặng 1 — Dissect (phân rã).** Rải "cuộn băng byte" ra thành cấu trúc: header
`ip`/`ipv6`, `tcp`/`udp`, và trường dữ liệu. Kết quả gọi là **disset** (`dis`).

**Chặng 2 — conntrack.** Gắn gói vào **luồng** (flow). Mỗi luồng lưu: hướng logic
của từng gói, đếm số gói/byte hai chiều, theo dõi sequence number TCP, và dùng
để ghép tin nhắn nhiều gói.

**Chặng 3 — Loại payload và giao thức luồng.** Xem `payload`.

**Chặng 4 — Reconstruct (reasm / decrypt).** Đôi khi một tin nhắn logic không vừa
một gói — ví dụ **TLS ClientHello lớn với khoá post-quantum**. Khi biết loại
payload + giao thức cần ghép, `nfqws2` sẽ: gom gói vào bản ghi conntrack →
**chặn không cho gửi ngay** → ghép lại (`reasm`), và nếu cần thì giải mã
(`decrypt`).

> Nếu không ghép, domain trong SNI có thể bị vứt vãi giữa các gói và không tìm
> hay cắt được.

**Chặng 5 — Chọn profile.** Profile quét **đúng thứ tự**, khớp lần đầu thì chọn và
**dừng**. Không profile nào khớp → profile mặc định ẩn `no_action` (không làm
gì).

> **Kết quả được cache trong conntrack.** Tìm lại chỉ khi dữ liệu nguồn đổi, mà
> chỉ có **hai** sự kiện như vậy: nhận diện được L7 protocol, và phát hiện tên
> host. Nên **tối đa hai lần đổi profile trong đời một luồng**.

**Chặng 6 — Chuỗi Lua instance.** Mỗi cờ `--lua-desync=...` là một **instance**.
Chạy **đúng thứ tự** — "gửi fake trước rồi cắt" khác "cắt trước rồi gửi fake".

**Chặng 7 — Bên trong instance.** Xem mục 5.

**Chặng 8 — Verdict và tổng hợp.**

| Verdict | Ý nghĩa |
|:--|:--|
| `VERDICT_PASS` | Không làm gì với gói, gửi nguyên trạng |
| `VERDICT_MODIFY` | Cuối chuỗi, gửi nội dung **đã sửa** |
| `VERDICT_DROP` | **Vứt** gói gốc |
| *(không return)* | Không can thiệp |
| `VERDICT_PRESERVE_NEXT` | Giữ trường "next protocol" của IPv6 |

**Quy tắc ưu tiên khi tổng hợp:** `MODIFY` đè `PASS`; `DROP` đè cả `PASS` lẫn
`MODIFY`. Đủ một instance trả `DROP` là gói gốc bị vứt, bất kể instance khác trả
gì.

> **Vì sao `DROP` mạnh nhất:** các thao tác cắt đoạn đã tự gửi dữ liệu bằng các
> gói riêng. Nếu không vứt gói gốc, máy chủ sẽ nhận dữ liệu **hai lần**.

**Chặng 9 — Cutoff và orchestrator.**

| Cơ chế | Tác dụng |
|:--|:--|
| **instance cutoff** | Instance tự tắt khỏi các gói sau của luồng theo hướng in/out |
| **lua cutoff** | Tắt hẳn một hướng của luồng khỏi **toàn bộ** xử lý Lua |
| **huỷ chuỗi còn lại** | Instance yêu cầu dừng mọi lời gọi Lua còn lại |

Instance làm việc này trở thành **orchestrator** (điều phối viên): C đưa cho nó
toàn bộ filter của profile và tham số của các instance còn lại, nó tự quyết
định khi nào gọi, có gọi không, hay đổi tham số.

> **Dấu hiệu "lua cutoff" như tối ưu:** nếu mọi instance của profile đã cutoff với
> luồng hiện tại (hoặc vị trí đã vượt ngưừng trên của range-filter), C đánh dấu
> luồng đó — kiểm tra nhanh nhất, **không cần gọi Lua lần nào**.

---

## 5. Hợp đồng của hàm Lua desync

### Chữ ký

```lua
function fake(ctx, desync)   -- ví dụ
```

- **`ctx`** — cầu nối mờ tới C. Bản thân nó không mang thông tin gì để đọc; nó
  được truyền ngược lại cho hàm C (gửi gói, cutoff) để chúng biết lời gọi thuộc
  gói/hàng đợi nào. Đại khái: **"đường dây điện thoại về kernel"**.
- **`desync`** — bảng Lua lớn chứa **mọi dữ liệu** gói đang xử lý và luồng của nó.
  Đây là đầu vào chính.

### Bên trong, hàm làm được

- **đọc** trường gói và luồng (dissect, loại payload, bộ đếm conntrack, reasm đã ghép)
- **tạo bản sao** dissect hiện tại, sửa trường (sequence number, TTL, cờ, payload),
  hoặc **tự sinh** dissect riêng (ví dụ ClientHello giả)
- **gửi** các dissect đó bằng **raw packet** thẳng ra mạng qua hàm C `rawsend_*` —
  diễn ra **ngay lập tức**, trước khi hàm return verdict
- **lưu trạng thái**: trong chính bảng `desync` (để truyền dữ liệu cho instance
  sau của gói này); trong `desync.track.lua_state` (dữ liệu sống **giữa các gói**
  của một luồng — C trả lại **cùng một bảng** cho mọi gói của luồng)

### Hai kiểu "đầu ra"

1. **Tác dụng phụ** — các gói đã gửi. Phần chính của fake/cắt đoạn **không** đi
   qua `return` mà qua lời gọi `rawsend_*`. Tới lúc `return`, gói giả đã bay.
2. **Giá trị trả về** — verdict cho gói gốc (bảng ở mục 4).

### Quan hệ C ↔ Lua

- **C → Lua:** bảng `desync` — dissect, conntrack, loại payload, tham số instance,
  thông tin replay. C đã làm hết việc nặng (bắt, phân tích, theo dõi luồng).
- **Lua → C:** lệnh qua `ctx` (gửi raw packet, hỏng checksum, đặt cutoff) + verdict
  qua `return`.

---

## 6. Vòng đời của một hàm desync (8 chặng)

Mọi hàm desync có **cùng một bộ xương**, thân hàm đi qua tám chặng cố định:

| Chặng | Tên | Nội dung |
|:--|:--|:--|
| 1 | Sàng lọc vận tải + `instance_cutoff` | Không phải TCP/UDP thì bỏ; thỏa điều kiện thì **vĩnh viễn tắt khỏi luồng** để khỏi phí CPU |
| 2 | Cắt hướng đối diện | `direction_cutoff_opposite` |
| 3 | Kiểm tra tham số sớm | Thiếu blob bắt buộc thì chết ngay |
| 4 | **Chọn dữ liệu** | Chuỗi `blob → reasm → payload` của gói hiện tại. Mọi thứ sau đó áp dụng lên nguồn thắng |
| 5 | Ba cái cổng | `#data>0`, hướng, loại giao thức |
| 6 | Rẽ nhánh replay | Yêu cầu nhiều gói được xử lý **một lần** ở phần đầu, các phần sau thì drop |
| 7 | **Kỹ thuật** | Phân giải marker, tạo phần/fake, gửi raw packet ngoài hàng đợi |
| 8 | Verdict + tổng hợp | `DROP` / `PASS` / `MODIFY` / không gì |

> Khác biệt giữa các hàm chỉ nằm ở **ba** điều: loại bỏ gì ở chặng 1, làm gì ở
> chặng 7, và phát gói ra mạng bằng cách nào. Phần còn lại là chung.

### Bốn cách phát gói ra mạng

1. **Sửa dissect hiện tại, trả `VERDICT_MODIFY`.** Hàm không tự gửi; nó sửa
   `desync.dis`, C ghép lại rồi gửi thay gói gốc. Dùng cho mọi modifier HTTP,
   `udplen`, `dht_dn`, `wsize`, `wssize`, `pktmod`.
   *Giới hạn: gói không được to ra, vì dùng chung bộ đệm.*
2. **`rawsend_dissect_ipfrag(dis, opts)`** — gửi dissect hoàn chỉnh. Dùng cho fake
   trên gói SYN, `rst`, `send`, `syndata`, `synack`, `synack_split`. Không cắt theo
   MSS.
3. **`rawsend_payload_segmented(desync, payload, seq, opts)`** — thay payload của
   bản sao dissect. **Cách phổ biến nhất** với kỹ thuật cắt đoạn. Nếu khối dữ liệu
   không vừa MSS thì tự động cắt tiếp với sequence đúng.
4. **`rawsend_dissect_segmented(desync, dis, mss, opts)`** — mức thấp hơn; dùng khi
   cần gửi dissect có **header đã sửa** — ví dụ `oob` bật cờ URG và đặt `th_urp`.

> **Chi tiết ảnh hưởng kết quả:** **fooling** áp **một lần lên dissect gốc**, nên
> mọi sub-segment nhận cùng giá trị; còn chính sách `ip_id` áp **riêng cho từng
> sub-segment**.

### Ba nhóm hàm

| Nhóm | Đặc điểm | Thành viên |
|:--|:--|:--|
| **Modifier** | Sửa gói hiện tại, trả `MODIFY`, không tự gửi | `http_domcase`, `http_hostcase`, `http_methodeol`, `http_unixeol`, `udplen`, `dht_dn`, `wsize`, `wssize`, `pktmod`, nhánh in của `oob` |
| **Bộ phát** | Phát một hay nhiều raw packet và quyết định số phận gói gốc | `fake`, `multisplit`, `multidisorder`, `multidisorder_legacy`, `fakedsplit`, `fakeddisorder`, `hostfakesplit`, `tcpseg`, `syndata`, `rst`, `send`, `synack`, `synack_split` |
| **Bộ lọc / phụ trợ** | Không gửi, không sửa; chỉ ra verdict hoặc chuẩn bị dữ liệu | `drop`, `tls_client_hello_clone`, `pass`, `pktdebug`, `argdebug`, `posdebug`, `luaexec` |

> Dùng khi debug: modifier không chạy → xem filter và nhận diện giao thức. Bộ phát
> không chạy → xem thêm marker, conntrack, replay.

---

## 7. Bản đồ khác biệt của từng hàm

### Kỹ thuật cắt đoạn TCP

| Hàm | Chặng 1 loại bỏ | `dir` | Nguồn dữ liệu (chặng 4) | replay | Cách phát | Verdict |
|:--|:--|:--|:--|:--|:--|:--|
| `multisplit` | không phải TCP | out | blob → reasm → payload | có | payload_segmented | DROP |
| `multidisorder` | không phải TCP | out | blob → reasm → payload | có | payload_segmented | DROP |
| `multidisorder_legacy` | không phải TCP | out | payload (reasm chỉ cho marker) | **không** | payload_segmented | DROP |
| `tcpseg` | không phải TCP | out | blob → reasm → payload | có | payload_segmented | **không** (`nil`) |
| `oob` | không TCP, thiếu conntrack, khởi đầu không phải SYN | — | reasm → payload | **đặc biệt** | dissect_segmented | DROP / MODIFY |

### Kỹ thuật có segment giả

| Hàm | Chặng 1 loại bỏ | `dir` | Nguồn dữ liệu | replay | Cách phát | Verdict |
|:--|:--|:--|:--|:--|:--|:--|
| `fakedsplit` | không phải TCP | out | blob → reasm → payload | có | payload_segmented, hai bộ option | DROP |
| `fakeddisorder` | không phải TCP | out | blob → reasm → payload | có | payload_segmented, hai bộ option | DROP |
| `hostfakesplit` | không phải TCP | out | blob → reasm → payload | có | payload_segmented, hai bộ option | DROP |
| `fake` | không TCP **và** không UDP (không cutoff) | out | **chỉ blob riêng** | có | payload_segmented | không (`nil`) |

### Giai đoạn bắt tay

| Hàm | Chặng 1 loại bỏ | Nguồn dữ liệu | Cách phát | Verdict |
|:--|:--|:--|:--|:--|
| `syndata` | không TCP, không phải SYN ("mission complete") | blob (mặc định 16 số 0) | dissect_ipfrag | DROP |
| `synack` | không TCP, không phải SYN | — | dissect_ipfrag | không |
| `synack_split` | không TCP, không SYN+ACK | — | dissect_ipfrag | DROP |
| `wsize` | không TCP, không SYN+ACK | — | — | MODIFY |
| `wssize` | không TCP; ép cutoff sau payload rỗng | — | — | MODIFY |

### Sửa đổi HTTP

| Hàm | Tác dụng |
|:--|:--|
| `http_domcase` | Đổi hoa thường phần domain (`HoSt`) |
| `http_hostcase` | Đổi hoa thường header `Host` |
| `http_methodeol` | Sửa ký tự cuối dòng của method |
| `http_unixeol` | Đổi kiểu kết thúc dòng |

---

## 8. Profile

> **TL;DR:** Profile = tập **bộ lọc** (gói nào thuộc về nó) + **hành động**
> (`--lua-desync`). Các profile ngăn cách bằng cờ `--new`. Gói được kiểm theo
> profile **đúng thứ tự từ trên xuống**; khớp lần đầu là chọn và **dừng tìm**.
> Không khớp profile nào → profile ẩn `no_action` (số 0) do engine tự thêm vào
> cuối. Trong một profile, các bộ lọc ghép bằng logic **AND**; nhiều giá trị trong
> **một** bộ lọc ghép bằng **OR**.

### Ba điều profile trả lời

1. Xử lý **traffic nào** → bộ lọc
2. Vào **thời điểm nào** của kết nối → ràng buộc theo loại dữ liệu và số thứ tự gói
3. **Làm gì** với gói → lời gọi kỹ thuật

### Profile và preset

| | Profile | Preset |
|:--|:--|:--|
| Là gì | Một khối: bộ lọc + hành động | Tệp text chứa **toàn bộ** cấu hình: bộ lọc + blob + profile |
| Phạm vi | Một nhóm quy tắc | Toàn bộ chương trình |
| Phân tách | `--new` | — |
| Chia sẻ | — | Tệp `.txt`, dễ trao đổi |

### Thứ tự profile là quan trọng

First-match-wins. **Profile hẹp hơn phải đặt trên profile rộng hơn.** Các profile
không kế thừa bộ lọc của nhau.

---

## 9. Bộ lọc profile

> **Không nhầm với bộ lọc bắt gói của WinDivert/nftables.**
> Tầng 1: bộ lọc bắt gói (`--wf-*` trên Windows, rule nftables/iptables trên
> Linux) quyết định gói nào được "gói" từ kernel vào `nfqws2` — **cái sỏ thô để
> tiết kiệm**. Tầng 2 (mục này) chọn profile nào xử lý gói đã bắt. Gói không qua
> tầng 1 thì không bao giờ tới tầng 2.

| Bộ lọc | Chọn theo | Cú pháp |
|:--|:--|:--|
| `--filter-l3` | phiên bản IP | `ipv4` \| `ipv6` (hoặc cả hai, phân tách dấu phẩy) |
| `--filter-tcp` | cổng TCP | `[~]port[-port]` hoặc `*`, phân tách dấu phẩy |
| `--filter-udp` | cổng UDP | như trên |
| `--filter-icmp` | type và code ICMP | `type[:code]` hoặc `*` |
| `--filter-ipp` | số IP-protocol (raw) | `proto` hoặc `*` |
| `--filter-l7` | giao thức luồng | `proto[,proto,…]` |
| `--filter-ssid` | tên mạng Wi-Fi | `ssid[,ssid,…]` |

Gần như tất cả nhận **nhiều giá trị phân tách dấu phẩy**; `~` nghĩa là phủ định
("tất cả trừ"); `*` là bất kỳ.

> **Lưu ý quan trọng — TCP và UDP loại trừ lẫn nhau.**
> Nếu profile có `--filter-tcp` mà **không** có `--filter-udp`, thì UDP **không
> được profile đó xử lý** (và ngược lại). Muốn profile chạy cả hai thì phải khai
> cả hai.

`--filter-l7` nhận: `http`, `tls`, `quic`, `wireguard`, `mtproto`, `dns`, `stun`,
`discord`, `dht`, `xmpp`, `dtls`, `bt`, `utp_bt`; cộng `all` (bất kỳ), `known`
(mọi thứ đã nhận diện), `unknown` (chưa nhận diện).

### Bộ lọc trong phạm vi profile

Ngoài bộ lọc chọn profile, có bộ lọc **siết từng instance**:

| Bộ lọc | Ý nghĩa |
|:--|:--|
| `dir` | Hướng gói: `in` \| `out` \| `any` (mặc định `out`) |
| `payload` | Danh sách loại payload được phép (`all`/`known`, phủ định `~`) |
| `--in-range` / `--out-range` | Vị trí gói trong luồng |

Sau khi định nghĩa, áp cho **mọi instance phía sau** cho tới khi bị định nghĩa lại.
Mục đích: **cắt bớt lời gọi Lua chậm**, giải quyết tối đa ở phía C nhanh.

### Danh sách IP và tên miền

Ngoài bộ lọc header, profile còn lọc theo **ipset** (danh sách IP) và
**hostlist** (danh sách tên miền), mỗi loại có biến thể loại trừ
(`--hostlist-exclude`, `--ipset-exclude`). Nhiều tệp được phép; tệp có thể nén
gzip. **Tên miền con trong hostlist được bao gồm tự động.**

---

## 10. Payload type và nhận diện giao thức

> **TL;DR:** *Loại payload* (`l7payload`) là nội dung đã nhận diện của **một
> gói**: `tls_client_hello`, `http_req`, `quic_initial`… Gói rỗng là `empty`, gói
> không nhận diện được là `unknown`. *Giao thức luồng* (`l7proto`) là nhãn dán cho
> **cả kết nối**; đặt khi gặp payload đã biết đầu tiên và giữ tới hết, kể cả khi
> về sau là `unknown`. Bộ lọc `--payload` giới hạn instance `--lua-desync` sau
> đó áp cho loại payload nào; mặc định là `known` (mọi thứ trừ `empty` và
> `unknown`).

Hai loại luôn tồn tại: **`empty`** (gói không dữ liệu ứng dụng, ví dụ ACK rỗng)
và **`unknown`** (có dữ liệu nhưng không nhận diện được — giữa kết nối đã mã hoá).

### Bảng đầy đủ

| Giao thức luồng | L4 | Loại payload bên trong |
|:--|:--|:--|
| `http` | TCP | `http_req`, `http_reply` |
| `tls` | TCP | `tls_client_hello`, `tls_server_hello` |
| `xmpp` | TCP | `xmpp_stream`, `xmpp_starttls`, `xmpp_proceed`, `xmpp_features` |
| `mtproto` | TCP | `mtproto_initial` |
| `bt` | TCP | `bt_handshake` |
| `quic` | UDP | `quic_initial` |
| `wireguard` | UDP | `wireguard_initiation`, `wireguard_response`, `wireguard_cookie`, `wireguard_keepalive` |
| `dht` | UDP | `dht` |
| `utp_bt` | UDP | `utp_bt_handshake` |
| `discord` | UDP | `discord_ip_discovery` |
| `stun` | UDP | `stun` |
| `dns` | UDP | `dns_query`, `dns_response` |
| `dtls` | UDP | `dtls_client_hello`, `dtls_server_hello` |
| *(bất kỳ)* | ICMP | `ipv4`, `ipv6`, `icmp` |

Nhận diện là **theo chữ ký** và nằm ở phía C. Có thể tự đặt loại riêng bằng
Lua-detector (`detect_payload_str`), **nhưng** loại đó không nhìn thấy được với
bộ lọc C `--payload` — chỉ bộ lọc payload bên trong chính hàm desync thấy.

---

## 11. `--in-range` / `--out-range`

```
--out-range=[(n|a|d|s|b|x)<int>](-|<)[(n|a|d|s|b|x)<int>]
              ───────────────────────────  FROM
                                          ─────  DẢI
                                                TO
```

| Tiền tố | Nghĩa | Đếm cái gì |
|:--|:--|:--|
| `n` | packet **n**umber | Thứ tự gói bị bắt (theo hướng đã chọn) |
| `d` | **d**ata packet | Chỉ gói có payload |
| `s` | **s**equence | TCP sequence number tương đối |
| `b` | **b**yte count | Số byte đã truyền |
| `a` | **a**lways | Luôn (không kèm số) |
| `x` | ne**x**t/never | Không bao giờ (không kèm số) |

> **Mọi bộ đếm chỉ tính trên những gói thực sự đi qua engine** (đã bị bắt bởi
> NFQUEUE/WinDivert và chưa bị lọc bỏ ở tầng trước).

### Hai cạm bẫy thường gặp

**Cạm bẫy 1 — tưởng `n` đếm "toàn bộ gói của kết nối".**
Thực tế `--out-range` chỉ đếm **gói đi ra**, `--in-range` chỉ đếm **gói đi vào**.
Cố tính `n` "toàn cục theo kết nối" và cộng cả SYN-ACK là sai.

**Cạm bẫy 2 — Windows/`winws2`: `--wf-tcp-empty=0` làm `n` nhảy.**
`winws2` **mặc định** bật `--wf-tcp-empty=0` — không bắt ACK rỗng để tiết kiệm CPU.
Hệ quả: gói TCP thứ hai đi ra (handshake ACK) thường **không vào engine**, `n`
"nhảy", và điều kiện `n2<n3` có thể trúng vào **ClientHello** thay vì ACK.

Cách xử lý:

- cần đúng ACK rỗng → bật `--wf-tcp-empty=1`
- cần nhắm "gói dữ liệu đầu tiên" → dùng tiền tố **`d`**, ổn định hơn khi ACK rỗng
  bị lọc bỏ

### Ví dụ thực hành

```bash
--out-range=d1-d3 --lua-desync=my_func
```

→ `my_func` chỉ được gọi cho gói dữ liệu đi ra thứ **1, 2, 3** của kết nối.

---

## 12. Blob — dữ liệu mẫu cho gói giả

Blob là dữ liệu dựng sẵn để nhét vào gói giả.

| Blob | Dùng cho |
|:--|:--|
| `fake_default_tls` | ClientHello TLS giả (kỹ thuật `fake`) |
| `fake_default_http` | HTTP request giả |
| `fake_default_quic` | QUIC Initial giả |
| Nhóm `tls_mod` | Biến thể của TLS blob: `rnd` (ngẫu nhiên hoá), `sni=`, `dupsid`, `padencap` |

Tải blob riêng của bạn qua cờ `--blob`.

> Với `syndata`, các sửa đổi `dupsid` và `padencap` **bị bỏ qua âm thầm** — không
> hoạt động với kỹ thuật đó.

---

## 13. Fooling (đánh lừa) — bảng đầy đủ

> **TL;DR: fake PHẢI chết trước khi tới máy chủ.** Nếu không, máy chủ nhận
> ClientHello/HTTP rác và kết nối tốt vỡ. *Fooling* là hỏng **có kiểm soát** fake
> để stack TCP/IP của máy chủ vứt nó, còn DPI kịp đọc và rút ra kết luận sai.
> Mỗi fooling có **"tầng chết"** riêng (checksum, seq, ack, timestamp, TTL,
> header IPv6) và chỗ riêng nó chết (NAT, router, máy chủ).

### IP/IPv4

| Tham số | Tác dụng |
|:--|:--|
| `ip_ttl=N` | Đặt TTL trong header IPv4 |
| `ip_autottl=delta,min-max` | Tự tính TTL từ gói vào (ví dụ `-1,3-20`) |

### IPv6

| Tham số | Tác dụng |
|:--|:--|
| `ip6_ttl=N` | Hop Limit của IPv6 (tương đương TTL) |
| `ip6_autottl=delta,min-max` | Tự tính Hop Limit |
| `ip6_hopbyhop[=hex]` | Thêm header Hop-by-Hop (kích thước 6+N×8 byte) |
| `ip6_hopbyhop2[=hex]` | Hop-by-Hop thứ hai |
| `ip6_destopt[=hex]` | Destination Options (unfragmentable part) |
| `ip6_destopt2[=hex]` | Destination Options thứ hai (fragmentable part) |
| `ip6_routing[=hex]` | Routing header |
| `ip6_ah[=hex]` | Authentication Header bị cắt cụt (6+N×4 byte) |

### TCP

| Tham số | Tác dụng |
|:--|:--|
| `tcp_seq=N` | Cộng N vào TCP sequence number (→ `badseq`) |
| `tcp_ack=N` | Cộng N vào TCP acknowledgment number (→ `badack`, thường âm) |
| `tcp_ts=N` | Cộng N vào giá trị TCP timestamp |
| `tcp_md5[=hex]` | Thêm tuỳ chọn TCP MD5 (RFC 2385), 16 byte; mặc định ngẫu nhiên |
| `tcp_flags_set=<list>` | Bật cờ TCP: `FIN,SYN,RST,PSH,ACK,URG,ECE,CWR` |
| `tcp_flags_unset=<list>` | Bỏ cờ TCP (→ `datanoack` với `ACK`) |
| `tcp_ts_up` | Chuyển tuỳ chọn timestamp lên đầu — workaround Linux: cho phép loại gói `badack` mà **không** cần `badseq` |
| `badsum` | Làm checksum L4 không hợp lệ |
| `fool=<func>` | Gọi hàm fooling do người dùng định nghĩa: `fool_func(dis, fooling_options)` |

### Ánh xạ từ nfqws1

| nfqws1 | zapret2 |
|:--|:--|
| `md5sig` | `tcp_md5` |
| `badseq` | `tcp_seq=-10000` (cho SYN) hoặc `tcp_ack=-66000` (gói thường) |
| `badack` | `tcp_ack=-66000` |
| `datanoack` | `tcp_flags_unset=ACK` |

Tất cả được áp bằng `apply_fooling()` trong `zapret-lib.lua`.

### Vì sao `ts` nguy hiểm

`ts` dịch **lùi** `TSval` của timestamp thật để máy chủ cho là fake "quá cũ". Chỉ
chạy được nếu timestamp đã được thỏa thuận từ đầu phiên TCP.

> **Nền tảng quyết định tất cả.** Windows mặc định **không** có timestamp; sau
> NAT ở nhà, `badsum`/`datanoack` chết; đặt trên chính router thì ngược lại có
> thể sống. Cùng một fooling ở chỗ này rất tốt, ở chỗ kia vô dụng.

### Ví dụ

```bash
--lua-desync=fake:ip_ttl=5
--lua-desync=fake:ip_autottl=-1,3-20
--lua-desync=fake:tcp_md5
--lua-desync=fakedsplit:tcp_seq=-10000:tcp_ack=-66000:tcp_ts_up
--lua-desync=fake:ip6_hopbyhop:ip6_destopt
--lua-desync=fake:tcp_flags_unset=ACK
--lua-desync=fake:ip_ttl=1:tcp_md5:tcp_ack=-66000
```

---

## 14. Thứ tự tham số

> **TL;DR:** Thứ tự giữa `--hostlist` và `--payload` **không quan trọng**. Nhưng
> thứ tự của `--payload` so với `--lua-desync` **có quan trọng**.

Ba ví dụ sau **tương đương nhau**:

```bash
--hostlist=list.txt --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls
--payload=tls_client_hello --hostlist=list.txt --lua-desync=fake:blob=fake_default_tls
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls --hostlist=list.txt
```

Ngược lại, cờ sai chỗ **không có tác dụng**:

```bash
# ✅ ĐÚNG
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls
# ❌ SAI — payload đặt sau thì không áp cho hàm này
--lua-desync=fake:blob=fake_default_tls --payload=tls_client_hello
```

| Tham số | Phạm vi | Thứ tự có quan trọng? |
|:--|:--|:--|
| `--filter-tcp/udp` | Cả profile | Không |
| `--filter-l7` | Cả profile | Không |
| `--hostlist` | Cả profile | Không |
| `--ipset` | Cả profile | Không |
| `--payload` | Tới `--payload` kế tiếp | **Có, trước `--lua-desync`** |
| `--out-range` | Tới `--out-range` kế tiếp | **Có, trước `--lua-desync`** |
| `--in-range` | Tới `--in-range` kế tiếp | **Có, trước `--lua-desync`** |
| `--lua-desync` | Lời gọi cụ thể | Có (thứ tự các lời gọi) |

**Kiểu viết khuyến nghị** cho dễ đọc: bộ lọc profile trước, rồi nhóm
`--payload` + `--lua-desync`.

---

## 15. Các kỹ thuật desync (chi tiết)

Cú pháp chung:

```bash
--lua-desync=<hàm>[:p1=v1[:p2=v2]]
```

Mỗi cờ `--lua-desync` là một **instance**, chạy đúng thứ tự. Viết `param` không
kèm giá trị = `true`.

### `fake` — gói giả đặt trước gói thật

Gửi gói giả **trước** gói thật. DPI đọc gói giả; máy chủ vứt nó.

```bash
--lua-desync=fake:blob=fake_default_tls
--lua-desync=fake:blob=fake_default_tls:tcp_md5:ip_ttl=3:repeats=5
```

Tham số riêng: `blob=<blob>` (**bắt buộc**),
`tls_mod=<list>` (`rnd`, `rndsni`, `sni=`, `dupsid`, `padencap`).
Verdict: **không** (`nil`) — gói thật vẫn đi bình thường.
Nguồn dữ liệu: **chỉ blob riêng** (không đụng reasm/payload).

### `multisplit` — cắt TCP tuần tự

> Cắt dữ liệu ứng dụng (HTTP request, TLS ClientHello) thành **nhiều segment TCP**,
> gửi **đúng thứ tự**, rồi **vứt** gói gốc. Máy chủ ghép lại bằng cơ chế TCP
> chuẩn — với nó không có gì đổi.

Ý nghĩa: DPI tìm tên site (`Host:` trong HTTP, SNI trong TLS) bằng **chữ ký** —
một chuỗi biết trước nằm trọn trong **một** gói. Nếu tên bị cắt bởi ranh giới
segment, mà DPI không ghép lại luồng TCP, thì không tìm thấy chữ ký.

Tham số riêng: `pos=<list>` (mặc định `"2"`), `seqovl=N`, `seqovl_pattern=<blob>`,
`blob=<blob>`, `nodrop`.

**Ba loại marker vị trí:**

| Loại | Mô tả | Ví dụ |
|:--|:--|:--|
| **Tuyệt đối dương** | Lệch từ đầu payload, đếm từ 0. `pos=N` → N byte đầu tách riêng | `1`, `5`, `100` |
| **Tuyệt đối âm** | Lệch từ **cuối** payload. `-1` = byte cuối | `-1`, `-10`, `-50` |
| **Tương đối** | Vị trí logic trong payload đã nhận diện, gắn với cấu trúc giao thức — engine tự tìm | `midsld`, `host`, `sniext` |

> Marker tương đối chỉ chạy **khi engine đã nhận diện được giao thức**.

**`seqovl=N`** — dán thêm N byte giả vào **trái** segment đầu và lùi sequence
number: máy chủ vứt các byte đó như nằm ngoài cửa sổ nhận, còn DPI đọc và có
thể tưởng đó là đầu request. Wiki đánh giá `seqovl` **tốt hơn fooling thường**
trong nhiều trường hợp.

Biến thể: `--payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld` —
tương đương trực tiếp với `--dpi-desync=multisplit --dpi-desync-split-pos=1,midsld`
của zapret1.

### `multidisorder` — cắt, phần đi **ngược** thứ tự

Giống `multisplit` nhưng các phần gửi **đảo thứ tự**. Tham số giống hệt.
`multidisorder_legacy` là bản hành xử theo kiểu gói từng gói, tương thích đầy đủ
với `nfqws1`.

### `fakedsplit` / `fakeddisorder` — cắt có lẫn segment giả

Cắt payload TCP rồi lẫn thêm phần giả — theo thứ tự thuận (`fakedsplit`) hoặc
ngược (`fakeddisorder`). Tham số: `pos=<marker>` (mặc định `"2"`), `nofake1`..
`nofake4`, `pattern=<blob>`, `seqovl=N`, `seqovl_pattern=<blob>`, `blob=<blob>`,
`nodrop`.

### `hostfakesplit` — cắt đúng ranh giới tên host

Cắt segment **đúng tại đường biên của tên host**, bọc quanh bằng các tên giả.
Tham số: `host=<str>` (mẫu host), `midhost=<marker>`, `nofake1`, `nofake2`,
`disorder_after=<marker>`, `blob=<blob>`, `nodrop`.

### `tcpseg` — gửi segment lấy từ một khoảng

Gửi một đoạn dữ liệu ra thành segment riêng, **kể cả có chồng lấn** (`seqovl`).

- `pos` gồm **hai** vị trí → điểm đầu và điểm cuối
- Dùng `resolve_range` (thay vì `resolve_multi_pos` như `multisplit`)
- Verdict: **không** (`nil`) — kết hợp với hàm `drop` để chặn gói gốc
- Áp dụng khi không muốn cắt gói thành nhiều phần

### `oob` — chèn byte Out-of-Band

Chèn một byte **dữ liệu khẩn** với cờ `URG` và con trỏ `th_urp` vào luồng, phá
vỡ chữ ký mà DPI đang dò.

Ba pha: bắt SYN → chèn byte OOB → cutoff. Xử lý gói vào bằng `urp=e`.

Chế độ `th_urp`:

| Chế độ | Nghĩa |
|:--|:--|
| `urp=b` | đầu (mặc định) |
| `urp=e` | cuối |
| `urp=<marker>` | vị trí tuỳ ý |

Verdict: `DROP` / `MODIFY`.

> `oob` là kỹ thuật **duy nhất** tự quyết định lúc can thiệp dựa trên **vị trí
> trong luồng** (nó bám SYN), chứ không lọc theo `dir` như phần lớn các hàm còn
> lại.

### `syndata` — dữ liệu ngay trong gói SYN

Gửi SYN **có kèm payload**.

- Blob mặc định: **16 số 0**
- Dùng `rawsend_dissect_ipfrag`, verdict `DROP`
- Nguồn dữ liệu: **chỉ blob**, không dùng replay
- `tls_mod` chỉ một phần hoạt động; **`dupsid` và `padencap` bị bỏ qua âm thầm**
- Khác `fake`: `fake` đặt giả **trước** gói thật trong luồng đã có; `syndata`
  gắn dữ liệu vào chính gói mở đầu kết nối.

### `synack` / `synack_split` — thao tác trên SYN/ACK

Làm việc với SYN/ACK và tách nó.

### `wsize` / `wssize` — window size

Đổi window size trên SYN/ACK (`wsize`) hoặc trên **mọi** gói (`wssize`).

### `rst`, `udplen`, `dht_dn`

| Hàm | Tác dụng |
|:--|:--|
| `rst` | Gửi RST |
| `udplen` | Đổi độ dài UDP |
| `dht_dn` | Chèn tên miền DHT |

### Hàm từ `zapret-lib.lua` (tiện ích)

| Hàm | Tác dụng |
|:--|:--|
| `pass` | Không làm gì (dùng để loại trừ) |
| `pktdebug` | In nội dung `desync` ra log |
| `argdebug` | In tham số ra log |
| `posdebug` | In vị trí conntrack |
| `luaexec` | Chạy mã Lua tuỳ ý |

---

## 16. Nhận diện MTProto

> Nhận diện MTProto là **AES-detect trên gói dữ liệu đầu tiên**. Hệ quả trực
> tiếp: **chỉ chạy trên gói đầu tiên có dữ liệu** của kết nối.

| Cách viết | Chạy ở đâu |
|:--|:--|
| `--payload=mtproto_initial` | Chỉ gói đầu tiên có dữ liệu |
| `--filter-l7=mtproto` | **Mọi** gói của kết nối MTProto (kể cả `unknown`) |
| Bỏ filter payload | Mặc định `known` — `mtproto_initial` đã nằm trong đó |

Khuyến nghị: dùng `--filter-l7=mtproto` vì nó bám theo luồng, không phụ thuộc
riêng gói đầu. Còn `payload=mtproto_initial` chỉ bắt đúng gói đầu.

---

## 17. Loại trừ (exclusions)

> **TL;DR:** **Không hề tồn tại** trường "Exclusions" toàn cục cho cả preset —
> không có trong GUI, không có trong định dạng preset. Chỉ có **điều kiện chọn
> traffic** (bao gồm cả loại trừ) và profile có chiến lược.

Hai cơ chế:

1. **Profile riêng với chiến lược `pass`** ("không làm gì").
2. **Danh sách loại trừ** `--hostlist-exclude` / `--ipset-exclude` bên trong profile.

Logic khác nhau, nhưng kết quả trong preset điển hình thì **giống nhau**: gói của
tài nguyên đó đi thẳng, không bị đánh lừa.

> Loại trừ **không phải một thực thể đặc biệt** mà là profile thường (hoặc một
> điều kiện trong profile). Nó chịu luôn quy tắc chung: thứ tự "trên = quan
> trọng hơn", first-match-wins, xung đột danh sách.

**Công thức thực hành:** tạo profile mới → chọn chiến lược
`pass (không làm gì)` → thêm domain/IP cần loại → **đặt profile lên trên** các
profile khác.

---

## 18. Profile có ảnh hưởng lẫn nhau không

> **TL;DR:** Chiến lược **không trộn** — một kết nối do **một** profile xử lý. Nhưng
> các profile **cạnh tranh** với nhau để giành kết nối.

- **Một kết nối — một profile.** Profile được cache trong conntrack.
- **Ngoại lệ:** profile **có thể đổi giữa chừng kết nối** — tối đa 2 lần (khi
  nhận diện L7, khi phát hiện tên host).
- **Một trang web ≠ một kết nối.** Trang web là hàng chục kết nối tới nhiều host
  khác nhau.

> **Cách phổ biến gây hỏng:** bật loại trừ → profile `pass` đứng trên → chiếm mất
> một kết nối mà vốn cần profile có chiến lược thật → YouTube hỏng.

Cách tìm profile nào đang chiếm một trang web: xem debug-log hoặc log analyzer.

---

## 19. Khi không hoạt động — chẩn đoán

> **TL;DR:** Zapret 2 là **bộ thao túng traffic**; nó **không thể "tự hỏng"** — hoặc
> đang chạy và áp dụng profile, hoặc không. "Hết chạy" gần như luôn nghĩa là
> **ISP đã cập nhật DPI**, khiến chiến lược của một-hai profile cũ. Cách sửa duy
> nhất: chỉnh lại **profile của site cụ thể** — **không** mù quáng đổi preset.
>
> **"Không hỏng" ≠ "không gây hại".** Zapret hoàn toàn có thể **làm hỏng** một
> trang vốn vẫn chạy được. Nếu tài nguyên **không** bị chặn, các gói giả đó vẫn
> tới máy chủ thật, máy chủ coi là rác (hoặc giống DDoS) và reset. Nên bước chẩn
> đoán đầu tiên: **kiểm tra trang đó có chạy được không khi không có Zapret**.

### Hai bẫy làm hỏng phép kiểm

**Bẫy 1 — bộ tự chọn kiểm bằng `curl`, còn bạn xem bằng trình duyệt.**
`curl` và trình duyệt khác nhau: HTTP/3, fingerprint TLS, cookie, header, cache.
Bộ tự chọn báo "chạy được" dựa trên `curl` — nghĩa là **bằng chứng yếu hơn thứ
bạn thật sự làm**.

**Bẫy 2 — F5 không tạo kết nối mới.**
TСПУ giữ lại kết nối cũ, bấm F5 chỉ dùng lại nó. Chiến lược mới không bao giờ
chạy.

### Checklist kiểm tra trung thực

1. Đóng hẳn trình duyệt, mở lại (hoặc dùng cửa sổ ẩn danh mới).
2. **Một kết nối mới** — không phải F5, không phải refresh.
3. Kiểm bằng **đúng thứ bạn dùng thật** (trình duyệt), không chỉ `curl`.
4. Nếu vẫn lỗi: tắt Zapret, xem trang có chạy không. Nếu chạy → cần **loại trừ**
   (`pass`), không cần đánh lừa.

### Vì sao đổi preset là ngõ cụt

Đổi hết bộ preset là đi mù trên các bộ chiến lược **hardcode**. Nếu không preset
nào khớp trọn vẹn, nghĩa là **cho DPI của bạn chưa có chiến lược nào trong các
preset có sẵn**. Bước đúng tiếp theo là **chỉnh profile thủ công**, không phải
preset thứ năm mươi.

### Tại sao không có "chiến lược tốt nhất"

Phụ thuộc ISP, vùng, phiên bản ТСПУ, và xung đột cục bộ (antivirus, VPN khác,
DNS). Cùng một chiến lược cho kết quả khác nhau ngay trong cùng thành phố.

---

## 20. Công cụ thực hành

### Tìm domain qua DevTools (F12)

1. Mở panel nhà phát triển → tab **Network**.
2. Đọc bảng request.
3. Xác định status nào nghĩa là bị chặn bởi DPI (timeout, connection reset —
   **khác** với lỗi trình duyệt như CORS hay lỗi chứng thư).
4. Gom danh sách domain vào hostlist.
5. **Kiểm lại trong chính tab đó.**

> Bắt đầu từ **subdomain nhỏ** trước.

### Tìm CDN của một domain

Nhận diện CDN (Akamai, Cloudflare, Amazon) để biết profile nào trong preset áp
dụng. Wiki dùng tiện ích trình duyệt `ipvfoobarbaz` + tra IP trên `ipinfo.io`.
Sau khi biết CDN, chọn profile có subnet tương ứng — hoặc dùng **subnet thay vì
domain** cho profile đó.

### Chiến lược cho game

1. Gom IP của game bằng **TCPView**.
2. Tạo profile game, đưa IP đã gom vào `ipset`.
3. **Giờ** mới đổi chiến lược — lúc này việc thử mới trung thực.
4. **UDP**: traffic thời gian thực cần profile UDP riêng với `payload=all`.

> Wiki còn chỉ ra giá trị thực tế: **TCPView không hiện địa chỉ đích của UDP** —
> đây là lý do log analyzer tồn tại, để thay thế cả Wireshark/TCPView.

### Steam

Server kết nối của Valve; cửa hàng và cộng đồng dùng trình duyệt nhúng và CDN
khác. Trong hostlist nên ghi **domain cha** thay vì từng CDN. Có **hai kiểu chữ
ký TLS khác nhau** trong cùng ứng dụng.

### Log analyzer

Bật log debug bằng dòng `--debug=@logs/<tên_preset>_debug.log` trong text preset.

- Trang phân tích gộp hàng nghìn dòng log thành bảng **connections**: host, IP,
  cổng, giao thức, profile đã khớp, bộ đếm gói và verdict, danh sách khớp.
- Nếu profile có **tên**, analyzer tự lấy từ log — thấy `7 (youtube.com QUIC)`
  thay vì `7` trần trụi.
- Click một connection mở bảng **từng gói**: hướng, cờ TCP, loại payload, **hàm
  Lua nào thực sự đã desync**, và verdict.
- **`drop` màu đỏ trên SYN hoặc ClientHello gửi đi thường là bình thường** —
  nghĩa là chiến lược đã thay thế gói gốc bằng gói giả, không phải lỗi.

---

## 21. Bộ lọc WinDivert (`--wf-*`) — CHỈ WINDOWS

> Trên Linux, vai trò này do nftables/iptables đảm nhiệm.

| Tham số | Chọn theo |
|:--|:--|
| `--wf-iface` | Giao diện mạng |
| `--wf-l3` | Giao thức L3 |
| `--wf-tcp-in` / `--wf-tcp-out` | Cổng TCP vào / ra |
| `--wf-udp-in` / `--wf-udp-out` | Cổng UDP vào / ra |
| `--wf-tcp-empty` | Có xử lý gói TCP rỗng không (xem cảnh báo ở mục 11) |
| `--wf-raw-part` | Raw filter một phần |
| `--wf-filter-lan` | Lọc mạng nội bộ |
| `--wf-raw` | Raw filter đầy đủ |
| `--wf-save` | Lưu filter rồi thoát |

### Chế độ lọc (mức độ "aggressive")

| Chế độ | Phủ | Ưu | Nhược | Khi nào dùng |
|:--|:--|:--|:--|:--|
| 💚 **Rất cẩn thận**<br>`windivert-discord-media-stun-sites` | Chỉ media Discord, STUN và danh sách site | Can thiệp tối thiểu, không làm hỏng ứng dụng | Có thể không ăn với chặn phức tạp | Chỉ cần vượt cho cuộc gọi / vài site |
| 💚 **Cẩn thận (cơ bản)**<br>`wf-l3` | TCP 80,443 · UDP 443, 50000–50100 | Cân bằng tốc độ và ổn định, phủ site và gọi | Không bắt cổng lạ hiếm | **Bước đầu được khuyến nghị** |
| 💯 **Thông minh (mọi cổng)**<br>`windivert_all` | Mọi kết nối TCP/UDP | Gần như chắc chắn ăn, chạy nhanh | Có thể gây vướng game và ứng dụng | Khi chế độ cơ bản không ăn |
| 💥 **Hung hăng (mọi cổng)**<br>`wf-l3-all` | Mọi cổng TCP/UDP (100%) | Hiệu quả tối đa, vượt được cả DPI tinh vi | Tải hệ thống nặng, nguy cơ lag | "Chốt chốt cuối" khi không gì khác ăn |
| 🚫 **None** | Không | Không can thiệp | Không vượt gì | Test / tạm tắt |

Thứ tự khuyến nghị: cẩn thận (cơ bản) → thông minh → hung hăng.

---

## 22. Giáo trình và lộ trình học

### Giáo trình 7 chương

| Chương | Chủ đề |
|:--|:--|
| 01 | Network stack L2–L7 bằng lời đơn giản — DPI hoạt động ở tầng nào |
| 02 | TCP: seq, ack, cửa sổ, MSS — nền cho fooling và `seqovl` |
| 03 | Bắt gói (NFQUEUE/WinDivert) và **verdict** |
| 04 | Dissect, reconstruct và đối tượng `desync` |
| 05 | Payload types, reasm, replay và **marker** |
| 06 | Lua pipeline: instance, tham số, debug |
| 07 | Start, cutoff và bộ đếm gói trong `--out-range` |

### Sáu cấp độ trong roadmap

| Cấp | Nội dung |
|:--|:--|
| **A** | Nền TCP/IP — không có cái này thì mọi thứ còn lại "lơ lửng trong không khí" |
| **B** | Bắt gói: zapret "nằm" ở đâu |
| **C** | Dissect / Reconstruct: "gói tin như một cấu trúc" |
| **D** | Nhận diện giao thức và payload |
| **E** | reasm / replay: "vì sao đôi khi cần một mảnh của tương lai" |
| **F** | Lua pipeline: `--lua-desync` là gì |
| **G** | Chiến lược (bằng ngón tay + theo code) |

Bốn phòng thí nghiệm được gợi ý: xem `desync` sống; xem tham số instance; xem bộ
đếm conntrack và reasm/replay; làm "thí nghiệm nhỏ" qua `luaexec`.

---

## 23. Nền tảng: DPI và ТСПУ

Mục `DPI/` của wiki có 30 trang. Những trang có ảnh hưởng trực tiếp tới lựa chọn
chiến lược:

| Chủ đề | Vì sao quan trọng |
|:--|:--|
| `DPI/DPI` | Cách cơ chế kiểm tra hoạt động + chương sự kiện chặn 2026 |
| `dpi-analysis-pipeline` | Quy trình phân tích DPI |
| `tspu-disable-quic-chrome` | Vì sao tắt QUIC trong Chrome là đầu mối |
| `tspu-dns-nsdi-dnat-august-2026` | DNS + NSDI + DNAT |
| `tspu-false-blocks-june-2026` | Chặn nhầm — giải thích vì sao trang chậm/đứng |
| `tspu-http2-tls12-fix` | Sửa lỗi HTTP/2 ↔ TLS 1.2 |
| `tspu-h2-h3-fingerprint-hypothesis` | Giả thuyết vân tay H2/H3 |
| `tspu-3xui-scmininterval-trap` | Bẫy `scmininterval` của 3x-ui |
| `tspu-whitelist-cloudflare-june-2026` | Cloudflare bị đưa vào whitelist |
| `ru-network-blocklists` | Danh sách chặn mạng Nga |
| `google-dns-8888-block-july-2026` | 8.8.8.8 bị chặn |
| `economic-filter-foreign-channels-2026` | Lọc kinh tế kênh nước ngoài |
| `rkn-vpn-2030-roadmap` | Lộ trình chặn VPN tới 2030 |
| `vpn-blocking-wave-forecast-summer-2026` | Dự báo đợt chặn VPN |
| `curl-impersonate`, `browser-ja4-fingerprint-block` | Vân tay TLS (JA4) và giả lập client |

---

## 24. Tra cứu nhanh

### Cấu trúc một lệnh

```bash
nfqws2 \
  --filter-l3=ipv4 \
  --filter-tcp=443 \
  --filter-l7=tls \
  --hostlist=/etc/zapret2/domains.txt \
  --payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:ip_ttl=3 \
  --lua-desync=multisplit:pos=1,midsld \
  --new \
  --filter-tcp=443 \
  --filter-l7=tls \
  --hostlist-exclude=/etc/zapret2/exclude.txt \
  --lua-desync=pass \
  --new \
  --filter-udp=443 \
  --filter-l7=quic \
  --lua-desync=fake:blob=fake_default_quic:repeats=6
```

### Năm bẫy hay gặp nhất

1. **Chỉ khai `--filter-tcp`** mà quên `--filter-udp` → UDP không bao giờ được xử lý.
2. **`--payload` đặt sau `--lua-desync`** → không áp dụng cho hàm đó.
3. **Profile `pass` đặt quá cao** → chiếm mất connection của profile thật.
4. **Profile rộng đặt trên profile hẹp** → first-match-wins nuốt mất profile hẹp.
5. **Tưởng `n` trong `--out-range` đếm toàn bộ gói của kết nối** → nó chỉ đếm gói
   **đi ra**; và trên Windows, `--wf-tcp-empty=0` làm `n` nhảy qua ACK rỗng.

### Bảng điều kiện để đổi chiến lược

| Tình huống | Nghĩa | Hướng xử lý |
|:--|:--|:--|
| Fake + md5sig đã bị chặn | DPI đã học được | Chuyển sang cắt đoạn |
| Multisplit thấy chưa bị chặn | Chữ ký vẫn nằm trọn gói | Giữ, chuyển dần sang phức tạp hơn |
| Một trang hỏng, trang khác OK | Chỉ **một profile** hỏng | Sửa profile đó, không đổi cả preset |
| Trang **vốn chạy được** giờ hỏng | Không cần đánh lừa | Loại trừ bằng chiến lược `pass` |
| Đổi hết preset vẫn hỏng | Chưa có chiến lược đúng cho DPI của bạn | Chỉnh profile thủ công |
| Tự chọn báo OK nhưng trang không mở | Kiểm bằng `curl`, bạn xem bằng trình duyệt | Kiểm lại bằng đúng thứ bạn dùng |

---

## 25. Liên kết

- Wiki: <https://wiki.zapret.moe/>
- Nguồn markdown: `https://git.zapret.moe/zapretdiscordyoutube/todo`
- Repo tác giả: <https://github.com/bol-van/zapret2>
- Tài liệu chính thức: `docs/manual.md` trong repo trên
- Sitemap: <https://wiki.zapret.moe/sitemap.xml> (282 trang)

### Các trang Zapret 2 trong wiki

| Nhóm | Trang |
|:--|:--|
| **Bắt đầu** | `Zapret2` · `guide` · `preset` · `profile` · `add-profile` · `find-site-domains` · `exclusions` |
| **Kiến trúc** | `структура проекта` · `схема обработки трафика` · `структура desync и диссекта` · `жизненный цикл desync-функции` · `roadmap обучения` |
| **Cấu hình** | `filter` · `payload` · `out-range` · `desync` · `blob` · `основные флаги` · `последовательность аргументов` · `profile-independence` |
| **Kỹ thuật** | `desync/fake` · `desync/multisplit` · `desync/multidisorder` · `desync/multidisorder_legacy` · `desync/fakedsplit` · `desync/fakeddisorder` · `desync/hostfakesplit` · `desync/tcpseg` · `desync/oob` · `desync/syndata` |
| **Orchestration** | `circular` · `оркестратор` |
| **Chẩn đoán** | `symptom-not-cause` · `verify-strategy` · `log-analyzer` · `find-domain-owner` · `find-game-strategy` · `steam` |
| **Chuyên biệt** | `распознавание mtproto` · `ts-and-fooling` · `windivert` · `wf` · `всякий мусор` |
| **Giáo trình** | `Zapret/manual/zapret2_01` … `zapret2_06` · `zapret2_start_cutoff` |