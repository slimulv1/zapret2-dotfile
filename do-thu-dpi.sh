#!/usr/bin/env bash
# do-thu-dpi.sh — đo xem NHÀ MẠNG đang có chặn SNI/DPI hay không.
#
#   bash do-thu-dpi.sh
#   bash do-thu-dpi.sh --chi-tiet   # in cả chi tiết từng bước
#
# CÁCH ĐO, VÌ SAO PHẢI NHƯ VẬY
#
#   Câu hỏi thật không phải "site có mở không" mà là:
#   "nếu BỎ QUA tầng DNS và nối thẳng vào IP, có lên không?"
#
#   Vì:
#     · Nếu DNS là tầng chặn → nối thẳng IP là mở, và zapret2 vô dụng
#     · Nếu có DPI chặn SNI   → nối thẳng IP vẫn hỏng, và zapret2 mới có
#                              ích (vì nó làm DPI không đọc được SNI)
#
#   Nên phép thử là: --resolve <tên>:<443>:<IP> — buộc dùng IP đó, giữ nguyên
#   SNI. Bỏ qua hoàn toàn DNS cục bộ. Kết quả mới trả lời được câu hỏi.
#
#   Vì sao lấy IP từ đâu? Phải hỏi MỘT DNS KHÁC — không phải DNS của máy, vì
#   nếu DNS của máy bị chặn thì lấy IP cũng thất bại, và ta sẽ tưởng nhầm là
#   "DPI chặn". Dùng DoH qua HTTPS nên bỏ qua cả tường chặn 53/853.
#
# KHÔNG tự ý kiến nghĩ gì thêm: script chỉ đo và in. Không đổi cấu hình.

set -uo pipefail

CHI_TIET=0
[ "${1:-}" = "--chi-tiet" ] && CHI_TIET=1

# Các tên miền thử. Gồm cả tên chắc chắn luôn mở (để có mốc so sánh) và
# những tên hay bị chặn ở Việt Nam (để tìm ra khác biệt nếu có).
DOMAINS="wikipedia.org github.com cloudflare.com viet69.be erothots.co facebook.com"

# Hàm lấy IP từ DoH. Thử Google trước, Cloudflare sau.
resolve_doh() {
  local d=$1 ip
  ip=$(curl -s --max-time 8 -H 'accept: application/dns-json' \
        "https://dns.google/resolve?name=$d&type=A" 2>/dev/null \
        | grep -oP '"type":1[^}]*?"data":"\K[^"]+' | head -1)
  [ -n "$ip" ] || ip=$(curl -s --max-time 8 -H 'accept: application/dns-json' \
        "https://cloudflare-dns.com/dns-query?name=$d&type=A" 2>/dev/null \
        | grep -oP '"type":1[^}]*?"data":"\K[^"]+' | head -1)
  printf '%s' "$ip"
}

# Nối thẳng IP, giữ SNI. Không dùng DNS máy.
#
# KHÔNG dùng `read -r a b < <(curl -w '%{http_code} %{time_total}')`.
# `read` đọc ĐÚNG giá trị rồi vẫn trả về 1, vì chuỗi `-w` không có newline
# cuối nên read gặp EOF. Bản đầu viết vậy rồi gắn `|| { báo lỗi; return; }`
# ⇒ MỌI lần đều đi nhánh lỗi, kể cả khi curl trả HTTP 200 thật. Nghĩa là
# script báo "không kết luận được" trên mọi nhà mạng và đẩy người dùng tin
# rằng đường của họ có DPI. Sai lệch theo hướng nguy hiểm nhất: nó tạo ra
# một bằng chứng giả theo đúng hướng dẫn người dùng đi sai.
probe() {
  local d=$1 ip=$2 out code time
  out=$(timeout 12 curl -s -o /dev/null --resolve "$d:443:$ip" --tlsv1.2 \
        -w '%{http_code} %{time_total}' "https://$d/" 2>/dev/null)
  code=${out%% *}
  time=${out##* }
  case "$code" in
    ''|000)
      printf '%-18s %-16s %s\n' "$d" "$ip" "KHÔNG TRẢ LỜI (timeout hoặc reset)"
      return 1 ;;
  esac
  printf '%-18s %-16s HTTP %-4s %ss\n' "$d" "$ip" "$code" "$time"
  return 0
}

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else G=""; R=""; Y=""; N=""; fi

printf '\n%s── ĐO DPI TRÊN ĐƯỜNG NÀY ──%s\n' "$N" "$N"

# Thông tin đường — để biết đang đo nhà mạng nào.
ASN=$(curl -s --max-time 8 https://ipinfo.io/json 2>/dev/null \
      | grep -oP '"(org|asn)":\s*"?\K[^",]*' | head -2 | paste -sd' · ')
printf '  nhà mạng   : %s\n' "${ASN:-không lấy được}"
printf '  zapret2    : %s\n' "$(systemctl is-active zapret2 2>/dev/null || echo 'không cài')"

if [ "$(id -u)" = 0 ] && [ -n "$(command -v ufw)" ]; then
  printf '  ufw        : %s\n' "$(ufw status 2>/dev/null | head -1)"
fi

printf '\n%s── Bước 1: lấy IP từ DoH (bỏ qua DNS máy) ──%s\n' "$N" "$N"

IPS=""
for d in $DOMAINS; do
  ip=$(resolve_doh "$d")
  if [ -z "$ip" ]; then
    printf '  %-18s %s\n' "$d" "DoH không trả lời — thử lại khi mạng ổn"
  else
    printf '  %-18s %s\n' "$d" "$ip"
    IPS="$IPS$d $ip
"
  fi
done

printf '\n%s── Bước 2: nối thẳng IP, GIỮ NGUYÊN SNI ──%s\n' "$N" "$N"
n_ok=0; n_bad=0
while read -r d ip; do
  [ -n "$d" ] || continue
  if probe "$d" "$ip"; then
    n_ok=$((n_ok+1))
  else
    n_bad=$((n_bad+1))
  fi
done <<< "$IPS"

printf '\n%s── KẾT LUẬN ──%s\n' "$N" "$N"
if [ "$n_ok" -gt 0 ] && [ "$n_bad" -eq 0 ]; then
  printf '  %sKHÔNG có chặn SNI/DPI trên đường này.%s\n' "$G" "$N"
  cat <<'EOF'

  Nối thẳng IP mà vẫn lên, kể cả những tên hay bị chặn. Nghĩa là nhà mạng
  này KHÔNG lọc nội dung gói tin — nó chỉ kiểm tra tên miền lúc phân giải.

  ⇒ zapret2 KHÔNG giúp ích ở đây. Nó sửa gói tin đang đi, mà không có gì
    cần sửa.

  ⇒ Cái cần là lớp DNS: NextDNS / DoH / DoT. Cái đó chạy được trên MỌI
    nhà mạng cùng lúc, không cần cấu hình riêng cho từng nhà.
EOF
elif [ "$n_ok" -gt 0 ]; then
  printf '  %sCÓ dấu hiệu chặn SNI: %s/%s tên không lên.%s\n' "$Y" "$n_bad" "$((n_ok+n_bad))" "$N"
  cat <<'EOF'

  Một số lên, một số không, dù đã ép IP và giữ SNI. Đây mới là hình dạng
  của chặn DPI.

  ⇒ zapret2 CÓ ích ở đây. Chạy lại lệnh dưới để biết tên nào hỏng, rồi
    đưa đúng tên đó vào hostlist.

    bash do-thu-dpi.sh --chi-tiet
EOF
else
  printf '  %sKHÔNG kết luận được: không tên nào lên.%s\n' "$R" "$N"
  cat <<'EOF'

  Có thể là mạng của bạn, không phải nhà mạng. Thử lại khi mạng ổn, hoặc
  thử trên điện thoại dùng 4G/5G để so sánh.
EOF
fi

if [ "$CHI_TIET" = 1 ]; then
  printf '\n%s── Chi tiết ──%s\n' "$N" "$N"
  printf '  DoH dùng    : dns.google, fallback cloudflare-dns\n'
  printf '  cờ curl     : --resolve (ép IP) + --tlsv1.2\n'
  printf '  zapret2      : %s\n' "$(systemctl is-active zapret2 2>/dev/null || echo 'không có')"
  printf '\n  %sĐể biết zapret2 có giúp không:%s\n' "$Y" "$N"
  cat <<'EOF'
  1. sudo bash do-thu-dpi.sh          # ghi kết quả
  2. sudo systemctl stop zapret2
  3. bash do-thu-dpi.sh              # chạy lại
  4. So hai kết quả. Giống nhau ở mọi hàng ⇒ zapret2 không làm được gì.
EOF
fi
exit 0