#!/usr/bin/env bash
# t1-config.sh — kiểm cấu hình 3 tầng. CHỈ ĐỌC, không sửa gì.
#
# Độc lập với install.sh: cùng soát một trường nhưng dùng hàm riêng. Nếu dùng
# chung hàm thì installer sai thì bộ kiểm cũng sai theo, và hai bên cùng xác
# nhận lẫn nhau mà không ai bắt được lỗi.
#
#   sudo bash test/t1-config.sh
# Mã thoát: 0 = đạt hết, 1 = có LỆCH, 2 = thiếu điều kiện chạy.
set -uo pipefail

CONF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config" && pwd)"
ZAPRET_DIR=/opt/zapret2
Z2D_SYSCTL=/etc/ufw/z2d-sysctl.conf
ND_V4="45.90.28.0 45.90.30.0"
ND_V6="2a07:a8c0:: 2a07:a8c1::"
DNS_PORTS="53/udp 53/tcp 853/tcp 853/udp"

if [ -t 2 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else G=""; R=""; Y=""; N=""; fi
N_OK=0; N_BAD=0; N_SKIP=0

# BẪY: `grep -c ... || echo 0` — grep in "0" rồi trả về 1, nên `||` in thêm
# "0" nữa ⇒ giá trị "0\n0" và dòng báo LỆCH dù máy hoàn toàn đúng. Dùng `|| true`.
chk() {
  if [ "$2" = "$3" ]; then printf '  %sOK%s    %-36s %s\n' "$G" "$N" "$1" "$2"; N_OK=$((N_OK+1))
  else printf '  %sLỆCH%s  %-36s thực tế=[%s] mong đợi=[%s]\n' "$R" "$N" "$1" "$2" "$3"; N_BAD=$((N_BAD+1)); fi
}
skip() { printf '  %sBỎ%s    %-36s %s\n' "$Y" "$N" "$1" "$2"; N_SKIP=$((N_SKIP+1)); }

for c in nft systemctl ufw; do command -v "$c" >/dev/null || { echo "thiếu lệnh: $c"; exit 2; }; done
[ -d "$ZAPRET_DIR" ] || { echo "chưa có zapret2 ở $ZAPRET_DIR"; exit 2; }

# Đọc `ufw status` — xem giải thích 3 bố cục trong install.sh.
ufw_has() {
  local sel=$1 pp=$2 act=$3 dir=${4:-OUT}
  ufw status 2>/dev/null | awk -v sel="$sel" -v pp="$pp" -v act="$act" -v dir="$dir" '
    { i = ($1 ~ /^\[[0-9]+\]$/) ? 2 : 1
      f6 = 0; for (k = i; k <= NF; k++) if ($k == "(v6)") f6 = 1
      j = i; while (j <= NF && $j !~ /^[0-9]+(:[0-9]+)?\/[a-z]+$/) j++
      if (j > NF) next
      a = $(j+1); nxt = $(j+2)
      if (a == "(v6)") { a = $(j+2); nxt = $(j+3) }
      if ($(j) != pp || a != act) next
      if (tolower(nxt) ~ /^(in|out)$/) {
        ok_dir = (tolower(nxt) == tolower(dir)) ? 1 : 0; addr = (j > i) ? $(j-1) : "any"
      } else { ok_dir = (dir == "IN") ? 1 : 0; addr = nxt }
      if (!ok_dir) next
      if      (sel == "v6")  { if (f6) f = 1 }
      else if (sel == "any") { f = 1 }
      else if (addr == sel)  { f = 1 }
    }
    END { exit(f ? 0 : 1) }'
}

printf '\n%s── TẦNG 1 — zapret2 (desync, không quyết định chặn) ──%s\n' "$N" "$N"
chk "dịch vụ zapret2"          "$(systemctl is-active zapret2)" active
chk "đúng 1 tiến trình nfqws2" "$(pgrep -c nfqws2 || true)" 1
chk "MODE_FILTER"              "$(grep -oP '^MODE_FILTER=\K.*' "$ZAPRET_DIR/config" 2>/dev/null)" hostlist
chk "cổng TCP"                 "$(grep -oP '^NFQWS2_PORTS_TCP=\K.*' "$ZAPRET_DIR/config" 2>/dev/null)" "80,443"
chk "cổng UDP rỗng"            "$(grep -oP '^NFQWS2_PORTS_UDP=\K.*' "$ZAPRET_DIR/config" 2>/dev/null)" ""
chk "FWTYPE"                   "$(grep -oP '^FWTYPE=\K.*' "$ZAPRET_DIR/config" 2>/dev/null)" nftables
chk "danh sách user rỗng"      "$(grep -cvE '^[[:space:]]*(#|$)' "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" || true)" 0
chk "số dải loại trừ"          "$(grep -cvE '^[[:space:]]*(#|$)' "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt" || true)" 9
n_ref=$(sed 's/#.*//' "$CONF/z2d-exclude.txt" | tr -s ' \t' '\n' | grep -vE '^$' | wc -l)
chk "repo cũng có 9 dải"      "$n_ref" 9
if diff -q <(sed 's/#.*//' "$CONF/z2d-exclude.txt" | tr -s ' \t' '\n' | grep -vE '^$' | sort) \
           <(grep -vE '^[[:space:]]*(#|$)' "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt" | sort) >/dev/null 2>&1
then chk "9 dải khớp repo" khớp khớp; else chk "9 dải khớp repo" lệch khớp; fi
chk "nft: rule IPv4 dport"     "$(nft list table inet zapret2 2>/dev/null | grep -c 'meta nfproto ipv4 tcp dport')" 1
chk "nft: rule IPv6 dport"     "$(nft list table inet zapret2 2>/dev/null | grep -c 'meta nfproto ipv6 tcp dport')" 1
chk "nft: không lọc cổng DNS" "$(nft list table inet zapret2 2>/dev/null | grep -cE 'dport (53|853)\b')" 0

printf '\n%s── TẦNG 2 — NextDNS qua DoT (tầng quyết định chặn) ──%s\n' "$N" "$N"
chk "số nameserver đang dùng"  "$(grep -c '^nameserver' /run/systemd/resolve/resolv.conf 2>/dev/null)" 4
chk "DoT bật"                  "$(grep -c '^DNSOverTLS=yes' /etc/systemd/resolved.conf 2>/dev/null)" 1
chk "LLMNR tắt"                "$(grep -c '^LLMNR=no' /etc/systemd/resolved.conf 2>/dev/null)" 1
chk "mDNS tắt"                 "$(grep -c '^MulticastDNS=no' /etc/systemd/resolved.conf 2>/dev/null)" 1
chk "không còn Cloudflare/Google" "$(grep -cE '^DNS=.*\b(1\.1\.1\.1|8\.8\.8\.8|9\.9\.9\.9)\b' /etc/systemd/resolved.conf 2>/dev/null || true)" 0
chk "mọi DNS đều có #ID"       "$(grep -cE '^DNS=[^#]+#[0-9a-f]{6}\.dns\.nextdns\.io' /etc/systemd/resolved.conf 2>/dev/null || true)" 4
chk "không còn placeholder"    "$(grep -c '{{' /etc/systemd/resolved.conf 2>/dev/null || true)" 0
chk "resolv.conf → stub" "$([ "$(readlink -f /etc/resolv.conf 2>/dev/null)" = /run/systemd/resolve/stub-resolv.conf ] && echo ok || echo sai)" ok
# BỎ QUA device lo: profile loopback giả, không DHCP ⇒ không có DNS router.
n_auto=0; n_conn=0
while IFS= read -r c; do
  [ -n "$c" ] || continue; n_conn=$((n_conn+1))
  v=$(nmcli -g ipv4.ignore-auto-dns,ipv6.ignore-auto-dns con show "$c" 2>/dev/null | paste -sd/ -)
  [ "$v" = "yes/yes" ] || n_auto=$((n_auto+1))
done < <(nmcli -t -f NAME,DEVICE,STATE con show 2>/dev/null | awk -F: '$3=="activated" && $2!="lo" && length($1){print $1}')
if [ "$n_conn" -eq 0 ]; then skip "ignore-auto-dns" "không có profile nào đang kết nối"
else chk "ignore-auto-dns=yes/yes ($n_conn profile)" "$n_auto" 0; fi
chk "DNS hỏi được" "$(resolvectl query --cache=no github.com >/dev/null 2>&1 && echo ok || echo loi)" ok

# Đường mặc định: cáp phải thắng wifi. Cả 3 tầng chỉ được đo trên cáp, nên
# lưu lượng lặt qua wifi thì tầng 1 không bao giờ chạy và mọi số đo vô nghĩa.
# Dùng UUID vì `-t` tách bằng `:` nên tên profile chứa `:` sẽ vỡ.
n_w=0 n_f=0 n_rm=0
while IFS=: read -r cu ct; do
  [ -n "$cu" ] || continue
  m=$(nmcli -g ipv4.route-metric con show "$cu" 2>/dev/null)
  case "$ct" in
    802-3-ethernet)   n_w=$((n_w+1)); [ "$m" = 100 ]   || n_rm=$((n_rm+1)) ;;
    802-11-wireless)  n_f=$((n_f+1)); [ "$m" = 50000 ] || n_rm=$((n_rm+1)) ;;
  esac
done < <(nmcli -t -f UUID,TYPE con show 2>/dev/null)
if [ "$n_w" -eq 0 ] && [ "$n_f" -eq 0 ]; then
  skip "route-metric" "nmcli không trả về profile nào"
elif [ "$n_rm" -eq 0 ]; then
  chk "route-metric cáp 100 · wifi 50000 ($n_w cáp, $n_f wifi)" 0 0
else
  chk "route-metric đúng ($n_w cáp, $n_f wifi)" "$n_rm" 0
fi

printf '\n%s── TẦNG 2b + 3 — ufw (chặn theo cổng, không quyết định chặn) ──%s\n' "$N" "$N"
n_al=0; n_d4=0; n_d6=0
for ip in $ND_V4 $ND_V6; do
  for p in 53/udp 853/tcp; do ufw_has "$ip" "$p" ALLOW OUT && n_al=$((n_al+1)); done
done
for pp in $DNS_PORTS; do
  ufw_has any "$pp" DENY OUT && n_d4=$((n_d4+1))
  ufw_has v6  "$pp" DENY OUT && n_d6=$((n_d6+1))
done
chk "rule ALLOW cho NextDNS" "$n_al" 8
chk "rule DENY IPv4"          "$n_d4" 4
chk "rule DENY IPv6"          "$n_d6" 4
n_kde=0
for src in 192.168.0.0/16 fe80::/10; do
  for pr in tcp udp; do ufw_has "$src" "1714:1764/$pr" ALLOW IN && n_kde=$((n_kde+1)); done
done
chk "rule KDE Connect"        "$n_kde" 4
chk "policy incoming"         "$(ufw status verbose 2>/dev/null | sed -n 's/^Default: \([a-z]*\) (incoming).*/\1/p')" deny
chk "ufw đang chạy"           "$(systemctl is-active ufw)" active

printf '\n%s── SYSCTL ──%s\n' "$N" "$N"
if [ -f "$Z2D_SYSCTL" ]; then
  chk "IPT_SYSCTL trỏ đúng tệp" "$(grep -oP '(?<=^IPT_SYSCTL=).*' /etc/default/ufw 2>/dev/null)" "$Z2D_SYSCTL"
  chk "symlink cho đường boot" "$([ -L /etc/sysctl.d/60-z2d-hardening.conf ] && echo co || echo khong)" co
  chk "drop-in ufw.service.d"  "$([ -f /etc/systemd/system/ufw.service.d/z2d-reapply-sysctl.conf ] && echo co || echo khong)" co
  chk "hook pacman"            "$([ -f /etc/pacman.d/hooks/z2d-pacman-ufw.hook ] && echo co || echo khong)" co
  chk "helper"                 "$([ -x /usr/local/bin/z2d-sysctl-apply ] && echo co || echo khong)" co
  # So với TỆP trong repo, không dùng con số ghi cứng.
  n_ref=$(grep -cE '^(net|fs)\.' "$CONF/z2d-sysctl.conf")
  n_ok=0; n_no=0
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    k=${line%%=*}; k=$(printf '%s' "$k" | tr -d ' ' | tr '/' '.')
    v=${line#*=};  v=$(printf '%s' "$v" | sed 's/^ *//;s/ *$//')
    if [ "$(sysctl -n "$k" 2>/dev/null)" = "$v" ]; then n_ok=$((n_ok+1)); else n_no=$((n_no+1)); fi
  done < "$CONF/z2d-sysctl.conf"
  chk "khoá sysctl đúng" "$n_ok" "$n_ref"
  # Hai khoá ufw hay ghi đè nhất — kiểm riêng cho dễ đọc.
  chk "rp_filter"       "$(sysctl -n net.ipv4.conf.default.rp_filter 2>/dev/null)" 2
  chk "log_martians"   "$(sysctl -n net.ipv4.conf.all.log_martians 2>/dev/null)" 1
else
  skip "sysctl" "chưa có $Z2D_SYSCTL — chạy install.sh trước"
fi

printf '\n──────────────────────────────────────────────\n'
printf '  đạt %s · LỆCH %s' "$N_OK" "$N_BAD"
[ "$N_SKIP" -gt 0 ] && printf ' · bỏ %s' "$N_SKIP"
printf '\n'
[ "$N_BAD" -eq 0 ] || exit 1
exit 0
