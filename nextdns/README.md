# Dữ liệu NextDNS — tầng 2 của hệ thống

Đây là **ảnh chụp cấu hình thật** của profile NextDNS, đọc từ
`GET https://api.nextdns.io/profiles/<ID>` ngày **2026-09-28**.

Tầng 2 là tầng **duy nhất quyết định chặn** trong hệ thống. Nhưng nó nằm trên
đám mây, nên `install.sh` **không** cài được — người dùng phải bật ở
<https://my.nextdns.io>. Thư mục này tồn tại để biết đúng phải bật gì, và để
đối chiếu sau này khi máy báo đột nhiên mất truy cập một trang.

## Các tệp

| Tệp | Nội dung | Số mục |
|---|---|---|
| `profile-id.json` | ID profile (6 ký tự hex) | 1 |
| `profile-name.json` | tên profile | 1 |
| `profile-fingerprint.json` | fingerprint DoT tự phục vụ | 1 |
| `profile-privacy.json` | **17 blocklist** + chống tracker + natives | 17 + 2 |
| `profile-security.json` | 23 công tắc bảo mật (threat-intel, AI, DGA, CSAM…) | 23 |
| `profile-parentalControl.json` | 25 dịch vụ + 7 chuyên mục | 6 khoá |
| `profile-setup.json` | máy chủ DoH/DoT/DoQ, DNSCrypt | 4 |
| `profile-settings.json` | log, blockPage, performance | 5 |
| `profile-denylist.json` | danh sách chặn thủ công | **83** |
| `profile-allowlist.json` | danh sách cho qua thủ công | **117** |
| `profile-rewrites.json` | (trống) | 0 |

## Hai cờ quyết định hầu hết kết quả

Trong `profile-security.json`:

```
aiThreatDetection        = true
threatIntelligenceFeeds  = true
```

Đây là hai công tắc **bật**. Chúng là lý do một số trang bị chặn dù không hề
có trong denylist.

Ví dụ đo được ngày 2026-09-28: `viet69.be` và `erothots.co` trả về
`Filtered: Blocked by NextDNS: ai-threat-detection` và
`threat-intelligence-feeds`. Cả hai trang **vẫn tồn tại và trả HTTP 200** khi
ép thẳng IP, giữ nguyên SNI — nghĩa là **không có chặn SNI/DPI**, chỉ có chặn
tầng DNS. Vì thế tầng 1 (zapret2) không có gì để can thiệp: không có kết nối
TCP nào được tạo ra.

## Cách dùng lại dữ liệu này

Muốn nạp denylist/allowlist về máy khác:

```bash
# xem trước
python3 -m json.tool nextdns/profile-denylist.json | head -20

# nạp vào NextDNS bằng API key (key để NGOÀI repo)
curl -X PATCH https://api.nextdns.io/profiles/$ND_ID/settings \
     -H "X-API-Key: $ND_API_KEY" -H 'Content-Type: application/json' \
     -d '{"denylist":'"$(cat nextdns/profile-denylist.json)"'}'
```

## Không có gì ở đây

**Không có API key.** Xem `.gitignore` để biết lý do. Key nằm ở
`/root/.config/nextdns/api.key` quyền 600.
