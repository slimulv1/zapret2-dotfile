#!/usr/bin/env bash
# =============================================================================
#  install.sh — hệ thống mạng 3 tầng cho CachyOS / Arch
#
#  Tầng 1   zapret2 / nfqws2   desync gói — để không bị DPI chặn
#  Tầng 2   NextDNS qua DoT     quyết định domain nào bị chặn  ← TẦNG DUY NHẤT
#  Tầng 2b  ufw (tường DNS)     chỉ cho hỏi NextDNS, chặn DNS nơi khác
#  Tầng 3   ufw (INPUT deny)    chặn vào máy, trừ KDE Connect
#  Harden   sysctl              18 khoá, qua 3 lớp phòng thủ
#
#  sudo bash install.sh --nd-id ABC123 --dry     xem trước, không sửa gì
#  sudo bash install.sh --nd-id ABC123           cài thật
#  sudo bash install.sh --uninstall              gỡ, phục hồi từ backup
# =============================================================================
set -uo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF="$REPO_DIR/config"
BACKUP=/var/backups/zapret2-dotfile
Z2D_SYSCTL=/etc/ufw/z2d-sysctl.conf
ZAPRET_DIR=/opt/zapret2
ZAPRET_REPO=https://github.com/bol-van/zapret

ND_ID=""; DRY=0; ACTION=install
ND_KEY=""                       # rỗng = tự dò. Xem nd_key_path.

# 4 địa chỉ NextDNS: 2 IPv4 + 2 IPv6. Ghi đủ 4 để hỏng một vẫn còn ba.
ND_V4="45.90.28.0 45.90.30.0"
ND_V6="2a07:a8c0:: 2a07:a8c1::"
DNS_PORTS="53/udp 53/tcp 853/tcp 853/udp"

if [ -t 2 ]; then C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else C_R=""; C_G=""; C_Y=""; C_B=""; C_0=""; fi
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s▸ %s%s\n' "$C_B" "$*" "$C_0"; }
ok()   { printf '  %sOK%s    %s\n'   "$C_G" "$C_0" "$*"; }
warn() { printf '  %sCẢNH BÁO%s %s\n' "$C_Y" "$C_0" "$*"; }
bad()  { printf '  %sLỖI%s    %s\n'   "$C_R" "$C_0" "$*" >&2; }
die()  { bad "$*"; exit 1; }

# run <mô tả> <lệnh...> — khi --dry chỉ in mô tả.
# Bắt buộc có mô tả: nếu không, --dry in "[dry] true" — vô nghĩa và che mất
# việc người đọc tưởng script đã làm gì đó.
run() {
  if [ "$DRY" = 1 ]; then printf '    [dry] %s\n' "$1"; return 0; fi
  shift; "$@"
}

usage() { cat <<'USAGE'
install.sh — hệ thống mạng 3 tầng (zapret2 + NextDNS + ufw)

  sudo bash install.sh --nd-id <ID> [--dry]   cài, hoặc xem trước nếu --dry
  sudo bash install.sh --uninstall            gỡ, phục hồi từ backup chuẩn
  bash install.sh --help                      màn này, không làm gì

Tùy chọn
  --nd-id ID     ID profile NextDNS, 6 ký tự hex (0-9a-f).
                 Lấy ở https://my.nextdns.io → Settings → General
  --nd-key PATH  API key NextDNS, để kiểm ID có thật không.
                 Mặc định tự dò ở /root/.config/nextdns/api.key
  --dry          in ra sẽ làm gì, không sửa bất cứ thứ gì
  --uninstall    gỡ 3 tầng, phục hồi từ /var/backups/zapret2-dotfile

Về --nd-key
  Không có key thì script vẫn chạy, nhưng KHÔNG kiểm được ID có thật hay
  không. ID sai không gây lỗi nào — NextDNS chỉ trả lời bằng profile mặc
  định của họ, nên máy vẫn thông mạng, tầng 2 lọc rất ít, tầng 1 không có
  gì để sửa, và bộ kiểm vẫn báo đạt. Key nằm NGOÀI repo, quyền 600.
  Đặt key ở /root/.config/nextdns/api.key, hoặc chỉ định --nd-key.

Cần sudo. Mất mạng thì chạy lại đúng dòng này:
  sudo bash install.sh --uninstall
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --nd-id)     [ $# -ge 2 ] || die "--nd-id cần một giá trị"; ND_ID=$2; shift 2 ;;
    --nd-key)    [ $# -ge 2 ] || die "--nd-key cần một đường dẫn"; ND_KEY=$2; shift 2 ;;
    --dry)       DRY=1; shift ;;
    --uninstall) ACTION=uninstall; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "không hiểu '$1' — xem --help" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "phải chạy bằng sudo"
[ -d "$CONF" ] || die "không thấy config/ cạnh script: $CONF"

# =============================================================================
#  Đọc `ufw status` — BA bố cục khác nhau
#
#   OUT, có địa chỉ đích : 45.90.28.0  53/udp  ALLOW OUT  Anywhere
#                                           ↑địa chỉ ↑cổng  ↑act ↑hướng
#   OUT, "any"           : 53/udp  (v6)  DENY  OUT  Anywhere (v6)
#   IN                   : 1714:1764/tcp  ALLOW      192.168.0.0/16
#                                          ↑cổng ↑act  ↑NGUỒN, KHÔNG in "IN"
#
#  Đây là nơi bộ kiểm sai nhiều nhất: bản đầu so `$3` với hướng nên nhận đủ
#  16 rule tường DNS (rule OUT) mà bỏ qua cả 4 rule KDE Connect (rule IN);
#  rồi lại nhầm "không có token hướng" với "có token hướng nhưng khác", nên
#  hỏi hướng IN cho một rule OUT vẫn trả "có".
# =============================================================================
ufw_has() { # ufw_has <any|ip|v6> <port/proto> <ALLOW|DENY> [IN|OUT]
  local sel=$1 pp=$2 act=$3 dir=${4:-OUT}
  ufw status 2>/dev/null | awk -v sel="$sel" -v pp="$pp" -v act="$act" -v dir="$dir" '
    { i = ($1 ~ /^\[[0-9]+\]$/) ? 2 : 1
      f6 = 0
      for (k = i; k <= NF; k++) if ($k == "(v6)") f6 = 1
      j = i
      while (j <= NF && $j !~ /^[0-9]+(:[0-9]+)?\/[a-z]+$/) j++
      if (j > NF) next
      a = $(j + 1); nxt = $(j + 2)
      if (a == "(v6)") { a = $(j + 2); nxt = $(j + 3) }
      if ($(j) != pp || a != act) next
      if (tolower(nxt) ~ /^(in|out)$/) {
        ok_dir = (tolower(nxt) == tolower(dir)) ? 1 : 0
        addr = (j > i) ? $(j - 1) : "any"
      } else {
        ok_dir = (dir == "IN") ? 1 : 0
        addr = nxt
      }
      if (!ok_dir) next
      if      (sel == "v6")  { if (f6) f = 1 }
      else if (sel == "any") { f = 1 }
      else if (addr == sel)  { f = 1 }
    }
    END { exit(f ? 0 : 1) }'
}

wall_complete() {
  local ok_=1 ip pp
  for ip in $ND_V4 $ND_V6; do
    ufw_has "$ip" 53/udp  ALLOW OUT || ok_=0
    ufw_has "$ip" 853/tcp ALLOW OUT || ok_=0
  done
  for pp in $DNS_PORTS; do
    ufw_has any "$pp" DENY OUT || ok_=0
    ufw_has v6  "$pp" DENY OUT || ok_=0
  done
  return $((1 - ok_))
}

kde_complete() {
  local ok_=1 src pr
  for src in 192.168.0.0/16 fe80::/10; do
    for pr in tcp udp; do ufw_has "$src" "1714:1764/$pr" ALLOW IN || ok_=0; done
  done
  return $((1 - ok_))
}

# 9 dải loại trừ — nguồn duy nhất là config/z2d-exclude.txt.
# Cắt chú thích CUỐI DÒNG: chỉ lọc dòng bắt đầu bằng '#' thì đếm ra 57 "dải".
read_exclude() {
  sed 's/#.*//' "$CONF/z2d-exclude.txt" | tr -s ' \t' '\n' | grep -vE '^$' | tr '\n' ' '
}

# =============================================================================
#  nd_check — hỏi NextDNS xem profile trong --nd-id có thật không
#
#  VÌ SAO CẦN
#    --nd-id chỉ kiểm đúng 6 ký tự hex. ID sai vẫn chạy êm: NextDNS trả lời
#    bình thường bằng profile mặc định của họ. Đo được 29/09 — cùng IP, chỉ
#    đổi SNI:
#        785fad.dns.nextdns.io  -> CHAN  (mask.icloud.com, có trong denylist)
#        aaaaaa.dns.nextdns.io  -> cho qua
#        000000 / ffffff        -> cho qua
#    Nghĩa là ID sai ⇒ tầng 2 lọc rất ít, tầng 1 cũng không có gì để sửa, mà
#    KHÔNG có lỗi nào hiện ra. Đây là kiểu hỏng nguy hiểm nhất: máy vẫn chạy.
#
#  API CÓ PHÂN BIỆT ĐƯỢC KHÔNG — có, nhưng cần key
#    GET https://api.nextdns.io/profiles/<ID>  với  X-API-Key:
#        ID thật  -> 200, ~17 KB
#        ID sai   -> 404 {"errors":[{"code":"notFound"}]}
#    KHÔNG có key -> 403 authRequired cho MỌI ID, kể cả ID thật. Nên khi không
#    kiểm được thì phải nói rõ là không kiểm — im lặng coi như đã kiểm thì
#    lại trở lại đúng cái lỗi trên.
#
#  KHÔNG lấy IP NextDNS từ API — giữ 4 địa chỉ đang có
#    API trả ipv4: [] và linkedIp 45.90.28.134, KHÔNG phải 4 địa chỉ anycast
#    trong template. Bốn địa chỉ đó đã đo thật: cả 4 nhận DoT 853 và định
#    tuyến đúng theo ID. Đổi sang IP từ API là đổi cấu hình đang chạy tốt
#    sang cấu hình chưa từng đo. API chỉ dùng để kiểm ID và báo tình trạng.
#
#  API key KHÔNG nằm trong repo — nó ở ngoài, người dùng tự đặt.
# =============================================================================

# nd_key_path — in đường dẫn key đầu tiên tìm thấy, hoặc rỗng.
# Dò cả /root (HOME khi chạy sudo) và nhà của người gọi sudo, vì đặt key ở
# ~/.config của người dùng là chỗ tự nhiên nhất.
nd_key_path() {
  local p
  for p in "$ND_KEY" /root/.config/nextdns/api.key; do
    [ -n "$p" ] && [ -r "$p" ] && { printf '%s' "$p"; return 0; }
  done
  if [ -n "${SUDO_USER:-}" ]; then
    p=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
    [ -n "$p" ] && [ -r "$p/.config/nextdns/api.key" ] && { printf '%s' "$p/.config/nextdns/api.key"; return 0; }
  fi
  return 1
}

# nd_json <tệp> <biểu thức python> — đọc 1 trường JSON, không có python3 thì
# bỏ trống. Chỉ dùng cho phần BÁO TÌNH TRẠNG; phần quyết định (404 hay không)
# chỉ cần HTTP code nên không phụ thuộc trình đọc JSON.
nd_json() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null || true
import json, sys
d = json.load(open(sys.argv[1])).get('data') or {}
try: v = eval(sys.argv[2], {'d': d, 'len': len})
except Exception: v = ''
print('' if v is None else v)
PY
}

# nd_check — gọi sau khi đã kiểm định dạng ID. Chết (die) nếu ID sai; mọi
# trường hợp không kiểm được thì chỉ cảnh báo, không chặn cài.
nd_check() {
  local kf body code name dn al bl sec

  command -v curl >/dev/null 2>&1 || {
    warn "không có curl — BỎ QUA kiểm ID NextDNS. Nếu ID sai, mọi tầng vẫn chạy nhưng không lọc."
    return 0
  }

  if ! kf=$(nd_key_path); then
    warn "không tìm thấy API key NextDNS — BỎ QUA kiểm ID."
    warn "ID sai sẽ không báo lỗi, chỉ chạy nhưng không lọc."
    warn "Đặt key ở $HOME/.config/nextdns/api.key (quyền 600), hoặc dùng --nd-key /đường/dẫn,"
    warn "rồi chạy lại để có kiểm. Kiểm tay:  dig +short <một tên miền profile của bạn chặn>"
    return 0
  fi

  body=$(mktemp) || { warn "không tạo được file tạm — BỎ QUA kiểm ID."; return 0; }
  # -o ghi thân, -w in HTTP code ra stdout. Tách 2 thứ này là chỗ dễ lẫn:
  # gộp chung rồi lấy $? thì $? là của echo, không phải của curl.
  code=$(curl -s -m 20 -o "$body" -w '%{http_code}' \
           -H "X-API-Key: $(tr -d '[:space:]' < "$kf")" \
           "https://api.nextdns.io/profiles/$ND_ID" 2>/dev/null) || code=""

  # Chỉ nhánh 200 được đi tiếp xuống phần báo tình trạng. Mọi nhánh còn lại phải
  # return ngay — bản đầu thiếu return nên 403 và mất mạng rơi xuống dưới, in ra
  # "OK profile NextDNS: ?" tức báo ĐẠT trong khi phép kiểm đã hỏng. Báo OK giả
  # tệ hơn không báo gì.
  case "$code" in
    200) : ;;
    404) rm -f "$body"
        die "NextDNS không có profile '$ND_ID' (API trả 404 notFound).
       Định dạng đúng nhưng profile không tồn tại — nếu cài tiếp thì máy vẫn chạy
       nhưng KHÔNG lọc gì, và tầng 1 cũng không có gì để sửa.
       Lấy đúng ID ở https://my.nextdns.io → Settings → General.
       Nếu đây là profile của người khác thì key của bạn không nhìn thấy nó —
       dùng API key của chính profile đó." ;;
    403) rm -f "$body"
        warn "API key trong $kf bị NextDNS từ chối (403) — BỎ QUA kiểm ID."
        warn "Kiểm tay:  dig +short <một tên miền profile của bạn chặn>"; return 0 ;;
    "")  rm -f "$body"
        warn "không gọi được api.nextdns.io (mất mạng, hoặc bị chặn) — BỎ QUA kiểm ID."
        warn "Cài xong nhớ kiểm tay:  dig +short <một tên miền profile của bạn chặn>"; return 0 ;;
    *)   rm -f "$body"
        warn "API trả HTTP $code lạ (thường là 429 quá nhiều request) — BỎ QUA kiểm ID."
        warn "Kiểm tay:  dig +short <một tên miền profile của bạn chặn>"; return 0 ;;
  esac

  # Tới đây là ID thật. Báo tình trạng — đây là thứ mà bản cũ thiếu hẳn:
  # người dùng không có cách nào biết tầng 2 có thật sự lọc không.
  name=$(nd_json "$body" 'd.get("name","")')
  dn=$(nd_json "$body" 'len(d.get("denylist",[]))')
  al=$(nd_json "$body" 'len(d.get("allowlist",[]))')
  bl=$(nd_json "$body" 'len(d.get("privacy",{}).get("blocklists",[]))')
  ok "profile NextDNS: ${name:-?} (ID $ND_ID)"
  ok "trên đám mây: $bl blocklist · $dn mục chặn · $al mục cho qua"

  # Hai công tắc này quyết định gần như hết kết quả. Tắt thì tầng 2 vẫn
  # "chạy" nhưng phần lớn chặn biến mất — và đó cũng là kiểu hỏng im lặng.
  #
  # nd_json trả "tắt" KHI công tắc tắt, rỗng khi công tắc bật. Phải cảnh báo
  # lúc CHUỖI CÓ NỘI DUNG. Bản đầu viết [ -z ... ] — tức cảnh báo đúng lúc
  # mọi thứ ổn và im lặng đúng lúc hỏng. Đảo điều kiện là cảnh báo hỏng nhất,
  # vì nó dạy người đọc bỏ qua cảnh báo.
  for sw in aiThreatDetection threatIntelligenceFeeds; do
    sec=$(nd_json "$body" '"tắt" if not d.get("security",{}).get("'"$sw"'") else ""')
    [ -n "$sec" ] && warn "công tắc $sw đang TẮT — nhiều trang sẽ không bị chặn"
  done
  rm -f "$body"
  return 0
}

# =============================================================================
step "1/9 · KIỂM TRA MÁY"
if [ "$ACTION" = install ]; then
  miss=()
  for c in bash nft systemctl ufw nmcli sysctl; do
    command -v "$c" >/dev/null 2>&1 || miss+=("$c")
  done
  [ ${#miss[@]} -eq 0 ] || die "thiếu lệnh: ${miss[*]} — sudo pacman -S --needed nftables ufw networkmanager"
  ok "đủ lệnh cần thiết"
  printf '%s' "$ND_ID" | grep -qE '^[0-9a-f]{6}$' \
    || die "--nd-id phải 6 ký tự hex (0-9a-f), bạn đưa '${ND_ID:-<rỗng>}' — lấy ở my.nextdns.io"
  ok "ID NextDNS: $ND_ID"
  nd_check
fi

# =============================================================================
step "2/9 · SAO LƯU VÀO $BACKUP"
# KHÔNG nuốt lỗi: bản đầu có `2>/dev/null` và mất im lặng 41 tệp, trong đó mất
# cả opt/zapret2/config — đúng thứ cần để quay lại.
if [ "$DRY" = 1 ]; then
  ok "[dry] sẽ ghi đè $BACKUP"
else
  st=$(mktemp -d /var/backups/.z2d.XXXXXX)
  mkdir -p "$st/etc/systemd/system/ufw.service.d" "$st/etc/sysctl.d" \
           "$st/etc/ufw" "$st/etc/default" "$st/etc/pacman.d/hooks" "$st/opt/zapret2"
  for f in /etc/systemd/resolved.conf /etc/sysctl.d/60-z2d-hardening.conf \
           /etc/ufw/sysctl.conf /etc/ufw/z2d-sysctl.conf /etc/default/ufw \
           /etc/nftables.conf /etc/pacman.d/hooks/z2d-pacman-ufw.hook; do
    [ -e "$f" ] && cp -a --parents "$f" "$st/" 2>/dev/null || true
  done
  cp -a /etc/systemd/system/ufw.service.d/*.conf "$st/etc/systemd/system/ufw.service.d/" 2>/dev/null || true
  if [ -d "$ZAPRET_DIR" ]; then
    cp -a "$ZAPRET_DIR/config" "$st/opt/zapret2/" || die "sao lưu config zapret2 thất bại"
    cp -a "$ZAPRET_DIR/ipset"  "$st/opt/zapret2/" || die "sao lưu ipset zapret2 thất bại"
    tar -C / -czf "$st/opt-zapret2.tar.gz" opt/zapret2 || die "nén /opt/zapret2 thất bại"
    tar -tzf "$st/opt-zapret2.tar.gz" >/dev/null 2>&1 || die "file nén hỏng — dừng"
  fi
  ufw status numbered > "$st/ufw-numbered.txt" 2>/dev/null || true
  nft list ruleset   > "$st/nft-ruleset.txt"   2>/dev/null || true
  { echo "Sao lưu chuẩn — $(date -Is)"
    echo "Phục hồi:  sudo bash install.sh --uninstall"; } > "$st/BAO-GHI.txt"
  rm -rf "$BACKUP"; mkdir -p "$(dirname "$BACKUP")"; mv "$st" "$BACKUP"
  ok "đã ghi $BACKUP ($(find "$BACKUP" -type f | wc -l) file)"
fi

# =============================================================================
step "3/9 · TẦNG 1 — zapret2"
if [ -x "$ZAPRET_DIR/nfq2/nfqws2" ]; then
  ok "$ZAPRET_DIR đã có sẵn"
elif [ "$DRY" = 1 ]; then
  ok "[dry] sẽ clone $ZAPRET_REPO rồi build"
else
  pkgs=(); for p in git go nftables iproute2; do pacman -Qq "$p" >/dev/null 2>&1 || pkgs+=("$p"); done
  # KHÔNG dùng `[ ] && A || B`: pacman hỏng thì B vẫn chạy và in "đủ gói".
  if [ ${#pkgs[@]} -eq 0 ]; then ok "đủ gói build"
  elif pacman -S --needed --noconfirm "${pkgs[@]}" >/dev/null 2>&1; then ok "đã cài: ${pkgs[*]}"
  else die "cài gói build thất bại: ${pkgs[*]}"; fi
  rm -rf "$ZAPRET_DIR"
  git clone --depth 1 "$ZAPRET_REPO" "$ZAPRET_DIR" || die "git clone thất bại — kiểm mạng"
  make -C "$ZAPRET_DIR" nfq >/dev/null 2>&1 || die "build nfq thất bại"
  [ -x "$ZAPRET_DIR/nfq2/nfqws2" ] || die "build xong nhưng không thấy nfq2/nfqws2"
  ok "đã build nfq2/nfqws2"
fi

# =============================================================================
step "4/9 · CẤU HÌNH zapret2"
# ⚠ /opt/zapret2/config là SCRIPT SHELL, không phải keyfile.
#   "MODE_FILTER = hostlist" bị bash đọc thành lệnh `MODE_FILTER`
#   ⇒ "command not found" và zapret2 KHÔNG LÊN. Phải là KEY=VALUE.
if [ "$DRY" = 1 ]; then
  ok "[dry] sẽ ép khoá + khối NFQWS2_OPT, viết 2 danh sách"
  run "sẽ restart zapret2" systemctl restart zapret2
else
  cfg="$ZAPRET_DIR/config"; [ -f "$cfg" ] || die "không có $cfg"
  set_key() {
    if grep -q "^$1=" "$cfg"; then sed -i "s|^$1=.*|$1=$2|" "$cfg"
    else printf '%s=%s\n' "$1" "$2" >> "$cfg"; fi
  }
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    set_key "${line%%=*}" "${line#*=}"
  done < "$CONF/z2d-zapret2.keys"

  # NFQWS2_OPT là KHỐI NHIỀU DÒNG — sed chỉ thay dòng đầu thì các dòng sau
  # trôi thành lệnh lạ ⇒ config hỏng. Thay cả khối trong một lượt awk.
  awk -v optfile="$CONF/z2d-zapret2-opt" '
    /^NFQWS2_OPT=/ { print "NFQWS2_OPT=\""
      while ((getline l < optfile) > 0) { if (l ~ /^[[:space:]]*$/ || l ~ /^[[:space:]]*#/) continue
        gsub(/<HOSTLIST>/, "", l); print l }
      close(optfile); skipping = 1; next }
    skipping && /^"[[:space:]]*$/ { print "\""; skipping = 0; next }
    skipping { next }
    { print }' "$cfg" > "$cfg.z2d" || die "thay khối NFQWS2_OPT thất bại"
  mv "$cfg.z2d" "$cfg"
  bash -n "$cfg" 2>/dev/null || die "$cfg không đọc được như script shell"

  cp "$CONF/z2d-hosts-user.txt" "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"
  n_user=$(grep -cvE '^[[:space:]]*(#|$)' "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" || true)
  [ "$n_user" = 0 ] || die "danh sách user phải RỔNG, đang có $n_user dòng"

  ex=$(read_exclude)
  # shellcheck disable=SC2086  # tách từ là cố ý: mỗi dải một dòng
  n_ex=$(printf '%s\n' $ex | grep -c .)
  [ "$n_ex" -eq 9 ] || die "cần đúng 9 dải loại trừ, config đang có $n_ex"
  printf '%s\n' $ex > "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt"
  # chấp nhận IPv4 CIDR · IPv6 CIDR · IPv6 đơn (::1)
  grep -qvE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$|^[0-9a-fA-F:]+(/[0-9]{1,2})?$' \
    "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt" && die "exclude có dòng không phải địa chỉ"
  ok "10 khoá + NFQWS2_OPT · danh sách rỗng · $n_ex dải loại trừ"

  systemctl enable zapret2 >/dev/null 2>&1 || true
  systemctl restart zapret2 || die "zapret2 không lên — journalctl -u zapret2 -n 30"
  for _ in $(seq 1 20); do systemctl is-active --quiet zapret2 && break; sleep 1; done
  systemctl is-active --quiet zapret2 || die "zapret2 vẫn không active"
  ok "zapret2 active"
fi

# =============================================================================
step "5/9 · TẦNG 2 — NextDNS qua DoT"
if [ "$DRY" = 1 ]; then
  run "sẽ ghi resolved.conf" true
  run "sẽ bật ignore-auto-dns" true
  run "sẽ restart systemd-resolved" systemctl restart systemd-resolved
  run "sẽ trỏ resolv.conf vào stub" true
else
  sed "s/{{ND_ID}}/$ND_ID/g" "$CONF/z2d-resolved.conf.template" > /etc/systemd/resolved.conf
  ok "đã ghi /etc/systemd/resolved.conf"

  # BỎ QUA device `lo`: profile loopback giả, không DHCP nên không có DNS
  # router. Nhận diện theo THIẾT BỊ, không theo tên (tên tuỳ ý).
  # Gom vào MẢNG: `while` trong pipeline chạy ở subshell nên `exit 1` bên trong
  # chỉ kết thúc subshell — bản đầu in "OK" dù có profile hỏng.
  mapfile -t conns < <(nmcli -t -f NAME,DEVICE,STATE con show 2>/dev/null \
                        | awk -F: '$3=="activated" && $2!="lo" && length($1){print $1}')
  [ "${#conns[@]}" -gt 0 ] || die "không thấy profile mạng thật nào đang kết nối"
  n_ok=0
  for c in "${conns[@]}"; do
    nmcli con modify "$c" ipv4.ignore-auto-dns true ipv6.ignore-auto-dns true 2>/dev/null || true
    got=$(nmcli -g ipv4.ignore-auto-dns,ipv6.ignore-auto-dns con show "$c" 2>/dev/null | paste -sd/ -)
    if [ "$got" = "yes/yes" ]; then n_ok=$((n_ok + 1)); else bad "'$c' = '${got:-<rỗng>}'"; fi
  done
  [ "$n_ok" -eq "${#conns[@]}" ] || die "$(( ${#conns[@]} - n_ok ))/${#conns[@]} profile chưa tắt DNS router"
  ok "ignore-auto-dns=yes/yes trên $n_ok/${#conns[@]} profile"

  systemctl restart systemd-resolved || die "systemd-resolved không khởi động lại được"
  sleep 1
  resolvectl query --cache=no github.com >/dev/null 2>&1 \
    || die "DNS không hỏi được — thử: sudo bash install.sh --uninstall"
  ok "DNS hỏi được"

  stub=/run/systemd/resolve/stub-resolv.conf
  [ -e "$stub" ] || die "không có $stub — DNSStubListener đang tắt?"
  if [ "$(readlink -f /etc/resolv.conf 2>/dev/null)" != "$(readlink -f "$stub")" ]; then
    rm -f /etc/resolv.conf; ln -s "$stub" /etc/resolv.conf || die "không tạo được symlink resolv.conf"
  fi
  [ "$(readlink -f /etc/resolv.conf)" = "$(readlink -f "$stub")" ] || die "resolv.conf không trỏ đúng stub"
  ok "/etc/resolv.conf → stub"
fi

# =============================================================================
step "6/9 · TẦNG 2b — TƯỜNG CHẶN DNS"
if [ "$DRY" = 1 ]; then
  say "  [dry] sẽ đảm bảo 16 rule: 8 ALLOW + 8 DENY (cả IPv4 lẫn IPv6)"
else
  for ip in $ND_V4 $ND_V6; do
    ufw_has "$ip" 53/udp  ALLOW OUT || ufw allow out to "$ip" port 53  proto udp comment 'z2d nextdns 53'  >/dev/null
    ufw_has "$ip" 853/tcp ALLOW OUT || ufw allow out to "$ip" port 853 proto tcp comment 'z2d nextdns 853' >/dev/null
  done
  for pp in $DNS_PORTS; do
    # Phải kiểm CẢ HAI họ: rule "any" tự tạo 2 họ, nhưng nếu v4 đã có sẵn thì
    # ufw chỉ in "Rule updated / Rule added (v6)".
    if ! ufw_has any "$pp" DENY OUT || ! ufw_has v6 "$pp" DENY OUT; then
      ufw deny out to any port "${pp%/*}" proto "${pp#*/}" comment "z2d chan DNS $pp" >/dev/null
    fi
  done
  # Đếm KHÔNG đủ — phải kiểm từng rule.
  wall_complete || die "tường DNS không đủ 16 rule — KHÔNG in HOÀN TẤT"
  ok "tường DNS đủ 16/16 rule (kiểm từng rule, cả hai họ)"
fi

# =============================================================================
step "7/9 · TẦNG 3 — ufw INPUT deny"
if [ "$DRY" = 1 ]; then
  say "  [dry] sẽ tạo 4 rule KDE Connect rồi đặt policy deny incoming"
else
  systemctl enable --now ufw >/dev/null 2>&1
  [ "$(systemctl is-active ufw)" = active ] || die "ufw không chạy — tầng 2b+3 không có"
  # Rule TRƯỚC, policy SAU: đảo thứ tự sẽ tự cắt chính người đang dùng máy.
  for src in 192.168.0.0/16 fe80::/10; do
    for pr in tcp udp; do
      ufw_has "$src" "1714:1764/$pr" ALLOW IN \
        || ufw allow in from "$src" to any port 1714:1764 proto "$pr" comment 'z2d KDE Connect' >/dev/null
    done
  done
  kde_complete || die "rule KDE Connect không đủ 4 — KHÔNG in HOÀN TẤT"
  ufw default deny incoming >/dev/null || die "đặt policy deny incoming thất bại"
  pol=$(ufw status verbose 2>/dev/null | sed -n 's/^Default: \([a-z]*\) (incoming).*/\1/p')
  [ "$pol" = deny ] || die "policy đọc lại là '${pol:-?}', không phải deny"
  ok "4 rule KDE Connect + policy deny incoming"
fi

# =============================================================================
step "8/9 · SYSCTL + 3 lớp phòng thủ"
if [ "$DRY" = 1 ]; then
  say "  [dry] sẽ nạp khoá, trỏ IPT_SYSCTL, cài drop-in + hook + symlink boot"
else
  n_key=$(grep -cE '^(net|fs)\.' "$CONF/z2d-sysctl.conf")
  cp "$CONF/z2d-sysctl.conf" "$Z2D_SYSCTL"
  sysctl --system >/dev/null 2>&1
  install -Dm644 /dev/null /etc/sysctl.d/.z2d-placeholder 2>/dev/null || true
  rm -f /etc/sysctl.d/.z2d-placeholder
  # symlink để boot CŨNG nạp: nếu chỉ để trong /etc/ufw/ thì ufw không chạy là mất hardening.
  ln -sfn "$Z2D_SYSCTL" /etc/sysctl.d/60-z2d-hardening.conf
  ok "$n_key khoá · 1 tệp, 2 đường nạp"

  # Lớp 1: IPT_SYSCTL → phủ `ufw reload` từ CLI (không đi qua systemd)
  install -Dm755 "$CONF/z2d-sysctl-apply" /usr/local/bin/z2d-sysctl-apply
  install -Dm644 "$CONF/z2d-pacman-ufw.hook" /etc/pacman.d/hooks/z2d-pacman-ufw.hook
  /usr/local/bin/z2d-sysctl-apply
  grep -q "^IPT_SYSCTL=$Z2D_SYSCTL$" /etc/default/ufw || die "không trỏ được IPT_SYSCTL"
  ok "lớp 1 — IPT_SYSCTL trong /etc/default/ufw"
  # Lớp 2: drop-in systemd → phủ mỗi lần ufw.service khởi động
  install -Dm644 "$CONF/z2d-ufw-reapply-sysctl.conf" \
    /etc/systemd/system/ufw.service.d/z2d-reapply-sysctl.conf
  systemctl daemon-reload; systemctl restart ufw
  ok "lớp 2 — drop-in ufw.service.d"
  # Lớp 3: hook pacman → phủ khi nâng cấp ufw ghi đè /etc/default/ufw
  ok "lớp 3 — hook pacman"

  n_ok=0; n_bad=0; badk=""
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    k=${line%%=*}; k=$(printf '%s' "$k" | tr -d ' ' | tr '/' '.')
    v=${line#*=};  v=$(printf '%s' "$v" | sed 's/^ *//;s/ *$//')
    c=$(sysctl -n "$k" 2>/dev/null)
    if [ "$c" = "$v" ]; then n_ok=$((n_ok + 1)); else n_bad=$((n_bad + 1)); badk="$badk $k"; fi
  done < "$CONF/z2d-sysctl.conf"
  # Số bốc từ TỆP: bản cứng "15" trong khi tệp có 18 khoá.
  [ "$n_ok" -eq "$n_key" ] || die "$n_bad/$n_key khoá sai:$badk"
  ok "$n_ok/$n_key khoá sysctl đúng"
fi

# =============================================================================
step "9/9 · KIỂM CHỨNG CUỐI"
if [ "$DRY" = 1 ]; then return 0 2>/dev/null || exit 0; fi
nbad=0
# BẪY ĐÃ DÍNH: (a) `grep -c ... || echo 0` in "0" RỒI trả 1 nên `||` in thêm
# "0" nữa → "0\n0" và dòng báo LỆCH dù máy đúng; (b) lookbehind biến thiên
# `(?<=X\s*=\s*)` bị PCRE từ chối — dùng \K.
chk() {
  if [ "$2" = "$3" ]; then printf '  %sOK%s    %-32s %s\n' "$C_G" "$C_0" "$1" "$2"
  else printf '  %sLỆCH%s  %-32s thực tế=[%s] mong đợi=[%s]\n' "$C_R" "$C_0" "$1" "$2" "$3"; nbad=$((nbad+1)); fi
}
chk "zapret2 active"      "$(systemctl is-active zapret2)" active
chk "tiến trình nfqws2"   "$(pgrep -c nfqws2 || true)" 1
chk "MODE_FILTER"         "$(grep -oP '^MODE_FILTER=\K.*' "$ZAPRET_DIR/config")" hostlist
chk "danh sách user rỗng" "$(grep -cvE '^\s*(#|$)' "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" || true)" 0
chk "số dải exclude"      "$(grep -cvE '^\s*(#|$)' "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt" || true)" 9
chk "nameserver"          "$(grep -c '^nameserver' /run/systemd/resolve/resolv.conf)" 4
chk "DoT"                 "$(grep -c '^DNSOverTLS=yes' /etc/systemd/resolved.conf)" 1
chk "tường DNS 16 rule"   "$(wall_complete && echo yes || echo no)" yes
chk "KDE Connect 4 rule"  "$(kde_complete && echo yes || echo no)" yes
chk "policy incoming"     "$(ufw status verbose 2>/dev/null | sed -n 's/^Default: \([a-z]*\) (incoming).*/\1/p')" deny
chk "ufw active"          "$(systemctl is-active ufw)" active
chk "IPT_SYSCTL"          "$(grep -oP '(?<=^IPT_SYSCTL=).*' /etc/default/ufw)" "$Z2D_SYSCTL"
chk "symlink boot sysctl" "$([ -L /etc/sysctl.d/60-z2d-hardening.conf ] && echo co || echo khong)" co
chk "DNS còn hỏi được"    "$(resolvectl query --cache=no github.com >/dev/null 2>&1 && echo ok || echo loi)" ok
say ""
[ "$nbad" -eq 0 ] || die "$nbad mục LỆCH — không in HOÀN TẤT"

# =============================================================================
if [ "$ACTION" = uninstall ]; then
  say ""
  ok "Xong."
else
  say ""
  say "──────────────────────────────────────────────"
  # --dry KHÔNG BAO GIỜ in "HOÀN TẤT": bản đầu in "HOÀN TẤT" ở chế độ dry,
  # tức "thành công giả" — đọc chữ đó là tin đã xong.
  if [ "$DRY" = 1 ]; then
    ok "XEM XONG — chưa thay đổi gì cả"
    say "  chạy thật: sudo bash install.sh --nd-id $ND_ID"
  else
    ok "HOÀN TẤT — 3 tầng đã dựng và đã kiểm chứng"
    say "  backup (duy nhất): $BACKUP"
    say "  kiểm lại          : sudo bash test/t1-config.sh"
    say "  mất mạng thì      : sudo bash install.sh --uninstall"
  fi
  say "──────────────────────────────────────────────"
fi
exit 0
