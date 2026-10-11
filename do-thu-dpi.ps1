<#
.SYNOPSIS
  Đo xem nhà mạng của bạn có chặn SNI/DPI hay không.

.DESCRIPTION
  Câu hỏi thật không phải "site có mở không" mà là:
      "nếu BỎ QUA tầng DNS và nối thẳng vào IP, có lên không?"

  Vì:
    · Nếu DNS là tầng chặn → nối thẳng IP là mở, và zapret2 vô dụng
    · Nếu có DPI chặn SNI   → nối thẳng IP vẫn hỏng, và zapret2 mới có ích

  Nên phép thử là: curl.exe --resolve <tên>:443:<IP> — buộc dùng IP đó,
  giữ nguyên SNI. Bỏ qua hoàn toàn DNS của máy.

  Vì sao lấy IP từ đâu? Phải hỏi MỘT DNS KHÁC qua HTTPS (DoH), không phải
  DNS của máy — nếu DNS của máy bị chặn thì lấy IP cũng thất bại, và ta sẽ
  tưởng nhầm là "DPI chặn".

  Script chỉ đo và in. Không đổi cấu hình gì.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File do-thu-dpi.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File do-thu-dpi.ps1 -ChiTiet
#>

param([switch]$ChiTiet)

$ErrorActionPreference = 'Continue'

$Domains = @(
  'wikipedia.org', 'github.com', 'cloudflare.com',
  'viet69.be', 'erothots.co', 'facebook.com'
)

# ---- lấy IPv4 từ DoH. Thử Cloudflare trước, Google sau. ----
function Get-DohIp([string]$d) {
  $urls = @(
    "https://cloudflare-dns.com/dns-query?name=$d&type=A",
    "https://dns.google/resolve?name=$d&type=A"
  )
  foreach ($u in $urls) {
    try {
      $r = Invoke-RestMethod -Uri $u -Headers @{ accept = 'application/dns-json' } `
                            -TimeoutSec 8 -ErrorAction Stop
      $a = $r.Answer | Where-Object { $_.type -eq 1 } | Select-Object -First 1
      if ($a) { return $a.data }
    } catch { }
  }
  return $null
}

# ---- nối thẳng IP, giữ nguyên SNI ----
function Test-Sni([string]$d, [string]$ip) {
  # curl.exe trả mã 000 khi không kết nối được (timeout / reset).
  # --resolve ép IP và giữ SNI; --tlsv1.2 để không phụ thuộc TLS1.3 của máy.
  $out = & curl.exe -s -o NUL --resolve "$d`:443:$ip" --tlsv1.2 `
                     -w '%{http_code}' --max-time 12 "https://$d/" 2>$null
  $code = if ($out) { "$out".Trim() } else { '000' }
  return @{ Code = $code; Ok = ($code -ne '000' -and $code -ne '') }
}

Write-Host ''
Write-Host '── ĐO DPI TRÊN ĐƯỜNG NÀY ──' -ForegroundColor Cyan
Write-Host ''

# Nhà mạng: đọc từ một dịch vụ công khai, không cần cài gì thêm.
try {
  $info = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 8 -ErrorAction Stop
  Write-Host ("  nhà mạng   : {0} · {1}" -f $info.org, $info.ip)
} catch {
  Write-Host "  nhà mạng   : không lấy được (không quan trọng, đo tiếp vẫn được)"
}

Write-Host ("  curl.exe   : {0}" -f $(if (Get-Command curl.exe -EA SilentlyContinue) { 'có' } else { 'KHÔNG CÓ — cần Windows 10 1803 trở lên' }))

Write-Host ''
Write-Host '── Bước 1: lấy IP từ DoH (bỏ qua DNS máy) ──' -ForegroundColor Cyan
Write-Host ''

$targets = @()
foreach ($d in $Domains) {
  $ip = Get-DohIp $d
  if ($ip) {
    Write-Host ("  {0,-18} {1}" -f $d, $ip)
    $targets += [pscustomobject]@{ Domain = $d; Ip = $ip }
  } else {
    Write-Host ("  {0,-18} {1}" -f $d, 'DoH không trả lời — thử lại khi mạng ổn') -ForegroundColor DarkYellow
  }
}

Write-Host ''
Write-Host '── Bước 2: nối thẳng IP, GIỮ NGUYÊN SNI ──' -ForegroundColor Cyan
Write-Host ''

$nOk = 0; $nBad = 0
foreach ($t in $targets) {
  $r = Test-Sni $t.Domain $t.Ip
  if ($r.Ok) {
    Write-Host ("  {0,-18} {1,-16} HTTP {2}" -f $t.Domain, $t.Ip, $r.Code) -ForegroundColor DarkGreen
    $nOk++
  } else {
    Write-Host ("  {0,-18} {1,-16} KHÔNG TRẢ LỜI (timeout hoặc reset)" -f $t.Domain, $t.Ip) -ForegroundColor DarkYellow
    $nBad++
  }
}

Write-Host ''
Write-Host '── KẾT LUẬN ──' -ForegroundColor Cyan
Write-Host ''

if ($nOk -gt 0 -and $nBad -eq 0) {
  Write-Host '  KHÔNG có chặn SNI/DPI trên đường này.' -ForegroundColor Green
  Write-Host ''
  Write-Host '  Nối thẳng IP mà vẫn lên, kể cả những tên hay bị chặn. Nghĩa là'
  Write-Host '  nhà mạng này KHÔNG lọc nội dung gói tin — nó chỉ kiểm tra tên'
  Write-Host '  miền lúc phân giải.'
  Write-Host ''
  Write-Host '  ⇒ zapret2 KHÔNG giúp ích ở đây. Nó sửa gói tin đang đi, mà không'
  Write-Host '    có gì cần sửa.'
  Write-Host ''
  Write-Host '  ⇒ Cái cần là lớp DNS: NextDNS / AdGuard / Quad9 qua DoH. Cái đó'
  Write-Host '    chạy được trên MỌI nhà mạng cùng lúc, không cần cấu hình riêng.'
  Write-Host '    Xem docs/BAO-VE-3-NHA-MANG.md mục 3.'
} elseif ($nOk -gt 0) {
  Write-Host ("  CÓ dấu hiệu chặn SNI: {0}/{1} tên không lên." -f $nBad, ($nOk + $nBad)) -ForegroundColor Yellow
  Write-Host ''
  Write-Host '  Một số lên, một số không, dù đã ép IP và giữ SNI. Đây mới là hình'
  Write-Host '  dạng của chặn DPI — và zapret2 CÓ ích ở đây.'
  Write-Host ''
  Write-Host '  ⇒ Chạy lại với -ChiTiet để biết tên nào hỏng, rồi đưa đúng tên'
  Write-Host '    đó vào hostlist. Xem docs/BAO-VE-3-NHA-MANG.md mục 4.'
} else {
  Write-Host '  KHÔNG kết luận được: không tên nào lên.' -ForegroundColor Red
  Write-Host ''
  Write-Host '  Có thể là mạng của bạn, không phải nhà mạng. Thử lại khi mạng ổn,'
  Write-Host '  hoặc dùng 4G/5G trên điện thoại để so sánh.'
}

if ($ChiTiet) {
  Write-Host ''
  Write-Host '── Chi tiết ──' -ForegroundColor Cyan
  Write-Host "  DoH dùng    : cloudflare-dns, fallback dns.google"
  Write-Host "  cờ curl     : --resolve (ép IP) + --tlsv1.2"
  Write-Host ''
  Write-Host '  Để biết zapret2 có giúp không — chạy 2 lần và so kết quả:' -ForegroundColor Yellow
  Write-Host '    1. zapret2 đang chạy   → powershell -File do-thu-dpi.ps1'
  Write-Host '    2. tắt zapret2         → Stop-Service zapret2'
  Write-Host '                            powershell -File do-thu-dpi.ps1'
  Write-Host '    Giống nhau ở mọi hàng ⇒ zapret2 không làm được gì ở đây.'
}
Write-Host ''
exit 0