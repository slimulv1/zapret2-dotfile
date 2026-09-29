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
# Đường dẫn TUYỆT ĐỐI của chính script này. Bước 9 đọc lại tệp để tự suy ra số
# mục kiểm chứng; ghi cứng "install.sh" sẽ vỡ ngay khi file bị đổi tên.
SELF="$REPO_DIR/$(basename "${BASH_SOURCE[0]}")"
CONF="$REPO_DIR/config"
BACKUP=/var/backups/zapret2-dotfile
Z2D_SYSCTL=/etc/ufw/z2d-sysctl.conf
ZAPRET_DIR=/opt/zapret2
ZAPRET_REPO=https://github.com/bol-van/zapret2
# GHIM tag, không theo master.
#   (1) Repo đúng là `zapret2`, KHÔNG phải `zapret`. `bol-van/zapret` là dự án
#       khác: không có thư mục nfq2/ (chỉ có nfq/), build ra binary `nfqws` chứ
#       không phải `nfqws2`, và config.default dùng khoá NFQWS_* chứ không có
#       NFQWS2_*. Bản đầu clone nhầm repo nên cài sạch sẽ chết ngay, hoặc tệ
#       hơn — build ra binary nào đó rồi bỏ qua toàn bộ khoá NFQWS2_* của ta.
#   (2) Master đi thì không kiểm soát được. Đã thử: HEAD 2026-09-18 vẫn ổn,
#       nhưng đổi cấu trúc thì không có gì chặn. Ghim tag đã đo.
#   Tag v1.0.5.2 (6b6c63e, 2026-09-15) đã kiểm thật: có nfq2/ với 29 file .c,
#   8 khoá NFQWS2_ trong config.default, `make systemd` ra nfq2/nfqws2 chạy được
#   (có sd_notify — xem giải thích ở bước 3).
ZAPRET_TAG=v1.0.5.2
# Mẫu để đếm "còn sót bao nhiêu unit zapret2". Dùng chung cho cảnh báo trong
# uninstall() để không mỗi nơi lại viết riêng một chuỗi rồi lệch nhau.
# `.*` chứ không phải `(-list-update)?`: zapret2 còn có `zapret2-bc2.service`
# (unit thử blockcheck2) — mẫu hẹp KHÔNG khớp nó, nên cảnh báo im lặng đúng
# lúc còn sót. Đo được: đã cố tình để lại zapret2-bc2.service rồi chạy
# uninstall, nó vẫn báo OK.
RE_UNIT_BASE='^zapret2.*\.(service|timer)[[:space:]]'

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

# `need_val <tên> <giá trị>` — chặn giá trị trông như TÙY CHỌN khác.
#
#   KHÔNG có hàm này thì `--nd-key --dry` bị đọc thành "đường dẫn tên là
#   --dry", cờ --dry bị nuốt, DRY vẫn bằng 0, và script CÀI THẬT trong khi
#   người dùng tưởng mình chỉ xem trước. Đo được trên máy thật: lệnh đó in ra
#   "HOÀN TẤT — 3 tầng đã dựng" và restart zapret2 lúc 11:39:37.
#
#   Một lỗi chính tả biến thao tác chỉ-đọc thành thao tác sửa máy, nên chặn
#   ở đây chứ không phải để cho chạy rồi mới báo lỗi.
need_val() { # need_val <tên tùy chọn> <giá trị theo sau>
  case "$2" in
    -*) die "$1 cần một giá trị, nhưng thấy '$2' — có lẽ bạn quên viết giá trị?
        (xem --help)" ;;
  esac
}

while [ $# -gt 0 ]; do
case "$1" in
--nd-id)     [ $# -ge 2 ] || die "--nd-id cần một giá trị"
            need_val "--nd-id"  "$2"; ND_ID=$2; shift 2 ;;
--nd-key)    [ $# -ge 2 ] || die "--nd-key cần một đường dẫn"
            need_val "--nd-key" "$2"; ND_KEY=$2; shift 2 ;;
    --dry)       DRY=1; shift ;;
    --uninstall) ACTION=uninstall; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "không hiểu '$1' — xem --help" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "phải chạy bằng sudo"
[ -d "$CONF" ] || die "không thấy config/ cạnh script: $CONF"

# =============================================================================
#  GỠ — phục hồi đúng trạng thái trước khi cài
#
#  ⚠ BẢN ĐẦU KHÔNG GỠ GÌ CẢ.
#  Chỉ bước 1 được bảo vệ bởi `ACTION = install`; bước 2 đến 9 thì không. Nên
#  `--uninstall` chạy đủ 9 bước CÀI ĐẶT rồi in "Xong." — tức cài chứ không gỡ.
#  Kiểm chứng: `bash install.sh --uninstall --dry` in ra đủ 9 bước.
#  Tệ hơn: README dặn "mất mạng thì chạy uninstall", tức dặn ngược.
#
#  Vì vậy phần gỡ phải đứng TRƯỚC bước 1 và tự thoát, không chạy tiếp xuống.
# =============================================================================
uninstall() {
  # ⚠ MỌI khối phá huỷ ở đây đều phải hỏi $DRY trước.
  #   Bản đầu của hàm này bỏ trống, nên `bash install.sh --uninstall --dry`
  #   thật sự chạy `systemctl disable --now zapret2` — tắt cả tầng 1 trên máy
  #   thật. Đã dính: chính tôi chạy phép thử này và làm tầng 1 ngãng.
  #   --dry mà thay đổi máy thì còn tệ hơn là không có --dry.
  if [ "$DRY" = 1 ]; then D=1; else D=0; fi

  step "GỞ · dừng zapret2"
  if [ "$D" = 1 ]; then
  say "    [dry] dừng zapret2, xoá 3 unit ở CẢ /etc và /usr/lib/systemd/system/"
else
  systemctl disable --now zapret2 >/dev/null 2>&1
  # Xoá ở CẢ HAI chỗ, không chỉ /etc.
  #
  #   Bản đầu chỉ xoá /etc/systemd/system/. Nhưng bản build zapret2 (make
  #   systemd) cũng để lại 3 unit ở /usr/lib/systemd/system/, và `pacman -Qo`
  #   trả RỖNG cho chúng — không gói nào sở hữu, chúng là rác. Đo được lúc
  #   làm trắng máy: xoá /etc xong, `systemctl list-unit-files` vẫn liệt kê đủ
  #   3 unit này, và ExecStart của chúng trỏ vào
  #   /opt/zapret2/init.d/sysv/zapret2 — thứ đã bị xoá. Gỡ xong mà còn unit thì
  #   systemd vẫn cố chạy tầng 1 rồi chết, và người dùng tưởng còn cài.
  for u in zapret2.service zapret2-list-update.service zapret2-list-update.timer; do
    rm -f "/etc/systemd/system/$u" "/usr/lib/systemd/system/$u"
  done
  systemctl daemon-reload
  n_left=$(systemctl list-unit-files 2>/dev/null | grep -cE "$RE_UNIT_BASE" || true)
  if [ "$n_left" -gt 0 ]; then
    warn "còn $n_left unit zapret2 trong systemd mà lệnh này không xoá được"
    warn "kiểm tay: systemctl list-unit-files | grep zapret2"
  else
    ok "zapret2 đã dừng, unit đã gỡ khỏi cả /etc và /usr/lib"
  fi
    # Xoá bảng nft của tầng 1.
    #
    #   Bản đầu không đụng tới. Bảng `inet zapret2` được nạp lúc zapret2 chạy và
    #   TỰ TỒN TẠI trong kernel sau khi dịch vụ dừng — đo được: sau
    #   `--uninstall`, `nft list tables` vẫn còn `table inet zapret2` cùng set
    #   `zapret` 522288 phần tử. Gỡ xong mà còn bảng thì máy vẫn còn dấu vết
    #   của tầng 1, và lần cài sau gặp lại bảng cũ.
    if nft list table inet zapret2 >/dev/null 2>&1; then
      nft delete table inet zapret2 2>/dev/null \
        || warn "không xoá được bảng nft inet zapret2 — kiểm tay: nft list tables | grep zapret2"
    fi

  fi

  step "GỞ · 20 dòng rule ufw (16 đặc tả)"
  # Đúng thứ tự như lúc thêm ở bước 6 và 7. Tổng 16 đặc tả:
  #   4 IP × 2 cổng (53/udp, 853/tcp)      =  8 ALLOW OUT
  #   4 cổng × "any"                       =  4 DENY OUT  (mỗi cái ra 2 dòng: v4 + v6)
  #   2 nguồn × 2 giao thức (1714:1764)    =  4 ALLOW IN
  # ufw hiện 20 dòng rule; ta xoá theo 16 đặc tả.
  if [ "$D" = 1 ]; then
    say "    [dry] xoá 16 đặc tả rule: 8 ALLOW + 4 DENY + 4 KDE Connect"
  else
    n_del=0
    for ip in $ND_V4 $ND_V6; do
      ufw_del_port ALLOW OUT "$ip" 53  udp && n_del=$((n_del+1))
      ufw_del_port ALLOW OUT "$ip" 853 tcp && n_del=$((n_del+1))
    done
    for pp in $DNS_PORTS; do
      ufw_del_port DENY OUT any "${pp%/*}" "${pp#*/}" && n_del=$((n_del+1))
    done
    for src in 192.168.0.0/16 fe80::/10; do
      for pr in tcp udp; do
        ufw_del_port ALLOW IN "$src" 1714:1764 "$pr" && n_del=$((n_del+1))
      done
    done
    if [ "$n_del" -ge 16 ]; then
      ok "đã xoá $n_del/16 đặc tả rule"
    else
      warn "chỉ xoá được $n_del/16 đặc tả rule"
      warn "kiểm tay: ufw status numbered — còn dòng nào ghi 53, 853 hay 1714:1764 là sót"
    fi
  fi

  step "GỞ · tệp cấu hình"
  # Với mỗi tệp: CÓ trong backup thì khôi phục; KHÔNG có trong backup thì xoá
  # hẳn — vì không có trong backup nghĩa là trước khi cài nó chưa tồn tại.
  #
  # Đếm bằng `if` chứ không `cmd && n=$((n+1))`: lệnh hỏng thì biến không tăng
  # mà không ai báo — bản đầu in "0 tệp xoá" trong khi đã thử 7 tệp và cả 7
  # đều hỏng. Im lặng kiểu đó nguy hiểm hơn là không đếm.
  if [ "$D" = 1 ]; then
    say "    [dry] khôi phục hoặc xoá 7 tệp theo $BACKUP, xoá /opt/zapret2"
  else
    n_ok=0 n_rm=0 n_fail=0 n_keep=0
    for rel in etc/systemd/resolved.conf \
               etc/sysctl.d/60-z2d-hardening.conf \
               etc/ufw/sysctl.conf \
               etc/ufw/z2d-sysctl.conf \
               etc/default/ufw \
               etc/nftables.conf \
               etc/pacman.d/hooks/z2d-pacman-ufw.hook; do
      if [ -e "$BACKUP/$rel" ]; then
        mkdir -p "/$(dirname "$rel")"
        # `rm` TƯỚC khi `cp` — nếu không, và /$rel đang là symlink (điển hình
        # /etc/resolv.conf trỏ stub), `cp` sẽ đi theo symlink và GHI ĐÈ mất
        # tệp đích, còn symlink vẫn trỏ vào đó. Đo được: sau uninstall, phải
        # có `rm` mới giữ được /run/systemd/resolve/stub-resolv.conf nguyên vẹn.
        rm -f "/$rel" 2>/dev/null
        if cp -a "$BACKUP/$rel" "/$rel" 2>/dev/null; then n_ok=$((n_ok+1)); else n_fail=$((n_fail+1)); fi
      else
        # KHÔNG có trong backup.
        #
        #   CHỈ xoá tệp do hệ 3 tầng TẠO RA. Tệp thuộc GÓI phải để nguyên.
        #   Đo được: chạy `--uninstall` trên máy chưa từng cài, không có backup
        #   ⇒ nó in "0 tệp khôi phục · 7 tệp xoá" và xoá luôn
        #     /etc/default/ufw      (thuộc gói ufw)
        #     /etc/ufw/sysctl.conf  (thuộc gói ufw)
        #     /etc/nftables.conf    (thuộc gói nftables)
        #   Tức uninstall trên máy KHÔNG CÀI gì vẫn phá 3 tệp của gói. Mất
        #   dữ liệu thật, không phải lỗi hiển thị.
        #
        #   Cách phân biệt: `pacman -Qo` trả tên gói ⇒ tệp của gói, để yên.
        #   Rỗng ⇒ không gói nào sở hữu ⇒ tệp do ta tạo, xoá được.
        if [ ! -e "/$rel" ]; then
          n_rm=$((n_rm + 1))                       # đã vắng sẵn, không cần xoá
        elif _own=$(pacman -Qo "/$rel" 2>/dev/null); then
          n_keep=$((n_keep + 1))                  # thuộc gói — GIỮ NGUYÊN
        elif rm -f "/$rel" 2>/dev/null; then n_rm=$((n_rm + 1)); else n_fail=$((n_fail + 1)); fi
      fi
    done
    if [ -d "$BACKUP/etc/systemd/system/ufw.service.d" ]; then
      cp -a "$BACKUP/etc/systemd/system/ufw.service.d/." /etc/systemd/system/ufw.service.d/ 2>/dev/null
    fi
    # Những thứ do ta TẠO RA, không bao giờ có trong backup.
    rm -f /etc/systemd/system/ufw.service.d/z2d-reapply-sysctl.conf
    rm -f /etc/systemd/system/ufw.service.d/z2d-reapply-sysctl.conf
    # Xoá thư mục drop-in NẾU RỖNG — và chỉ khi rỗng.
    #
    #   Bản đầu chỉ xoá file, để lại /etc/systemd/system/ufw.service.d/ rỗng.
    #   Đo được: sau --uninstall, thư mục này vẫn còn. Systemd thì bỏ qua nên
    #   vô hại, nhưng đó là tàn dư do ta tạo ra, cùng loại với unit rác ở
    #   /usr/lib mà đã sửa.
    #
    #   CHỈ xoá khi rỗng: nếu trước khi cài, người dùng đã có drop-in riêng
    #   trong đó thì khối trên đã khôi phục lại chúng — xoá thư mục lúc đó sẽ
    #   xoá luôn việc của họ.
    z2d_dir=/etc/systemd/system/ufw.service.d
    if [ -d "$z2d_dir" ] && [ -z "$(ls -A "$z2d_dir" 2>/dev/null)" ]; then
      rmdir "$z2d_dir" 2>/dev/null || warn "không xoá được thư mục rỗng $z2d_dir"
    fi
    rm -f /usr/local/bin/z2d-sysctl-apply
    rm -rf "$ZAPRET_DIR" 2>/dev/null
    # Phải phân nhánh theo n_fail. Bản đầu in "OK …" vô điều kiện, nên khi tệp
    # không xử lý được thì vẫn đọc là đã xong.
    if [ "$n_fail" -eq 0 ]; then
      ok "$n_ok tệp khôi phục · $n_rm tệp xoá · $n_keep tệp của gói (giữ nguyên)"
    else
      warn "$n_ok khôi phục · $n_rm xoá · $n_keep giữ nguyên · $n_fail KHÔNG xử lý được"
      warn "xem lại: ls -l /etc/systemd/resolved.conf /etc/ufw/ /etc/default/ufw"
    fi
  fi

  step "GỞ · nạp lại"
  if [ "$D" = 1 ]; then
    say "    [dry] trỏ resolv.conf về stub, restart systemd-resolved + ufw"
  else
    # Phải kiểm kết quả từng lệnh. Bản đầu `rm` và `ln` đều hỏng (Permission
    # denied) mà vẫn in "systemd-resolved + ufw đã nạp lại" — đọc chữ OK là
    # tin sai, và người dùng mất mạng thì tưởng đã gỡ xong.
    rm -f /etc/resolv.conf 2>/dev/null
    systemctl restart systemd-resolved >/dev/null 2>&1
    n_res=0
    if [ -e /run/systemd/resolve/stub-resolv.conf ]; then
      if ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null; then
        n_res=1
      else
        warn "không tạo được symlink /etc/resolv.conf — DNS có thể hỏng"
      fi
    else
      warn "không có /run/systemd/resolve/stub-resolv.conf — DNSStubListener đang tắt?"
    fi
    systemctl restart ufw >/dev/null 2>&1
    # Khôi phục policy INPUT nếu backup có lưu. Không có thì KHÔNG đoán — báo
    # và bỏ qua, vì đặt bừa còn tệ hơn không đặt.
    _pol_saved=$(cat "$BACKUP/ufw-policy-in.txt" 2>/dev/null || true)
    case "$_pol_saved" in
      allow|deny|reject)
        if ufw default "$_pol_saved" incoming >/dev/null 2>&1; then
          ok "policy incoming → $_pol_saved (khôi phục từ backup)"
        else
          warn "không đặt lại được policy incoming ($_pol_saved)"
        fi ;;
      "") warn "backup không lưu policy INPUT — giữ nguyên policy hiện tại" ;;
      *)  warn "policy trong backup lạ ($_pol_saved) — giữ nguyên" ;;
    esac
    # Quay lại đúng trạng thái BẬT/TẮT trước khi cài (xem giải thích ở bước 2).
    _en_saved=$(head -1 "$BACKUP/ufw-enabled.txt" 2>/dev/null || true)
    case "$_en_saved" in
    no)  if ufw --force disable >/dev/null 2>&1; then
           ok "ufw → tắt (đúng trạng thái trước khi cài)"
         else
           warn "không tắt được ufw — nó sẽ còn bật dù trước đó bạn không bật"
         fi ;;
    yes) ok "ufw vẫn bật (đúng trạng thái trước khi cài)" ;;
    "")  warn "backup không lưu trạng thái bật/tắt của ufw — giữ nguyên hiện tại" ;;
    *)   warn "trạng thái ufw trong backup lạ ('$_en_saved') — giữ nguyên" ;;
    esac
    if [ "$n_res" = 1 ]; then
      ok "resolv.conf → stub · ufw đã nạp lại"
    else
      warn "resolv.conf chưa trỏ lại stub — kiểm: readlink -f /etc/resolv.conf"
    fi
  fi

  say ""
  if [ "$D" = 1 ]; then
    ok "XEM XONG — chưa thay đổi gì cả"
  elif [ -d "$BACKUP" ]; then
    ok "Xong. Trạng thái trước khi cài nằm ở $BACKUP"
  else
    warn "Xong, nhưng KHÔNG có $BACKUP để đối chiếu — gỡ xong không còn bản sao"
  fi
  say "  nếu DNS vẫn lỗi: nmcli con mod '<tên profile>' ipv4.ignore-auto-dns no ipv6.ignore-auto-dns no"
  exit 0
}

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

# ufw_del_port <ALLOW|DENY> <IN|OUT> <địa chỉ> <cổng> <proto> — xoá đúng
# rule mà ufw_has tìm thấy. Trả 0 nếu có xoá, 1 nếu không có rule nào khớp.
#
# Xoá THEO ĐẶC TẢ (`ufw delete ...`), KHÔNG phân tích số thứ tự từ
# `ufw status numbered`. Ba lý do:
#   (1) Chính repo này ghi ở phần trên: `ufw status` in BA bố cục khác nhau,
#       và đó là nơi bộ kiểm sai nhiều nhất. Xoá theo số phải dựa vào đúng
#       bố cục đó.
#   (2) Xoá một rule làm số thứ tự các rule sau dịch lên, nên phải quét lại
#       sau mỗi lần xoá.
#   (3) `ufw delete <đặc tả>` tự khớp theo nội dung rule, không cần biết số.
#       Cách này không phụ thuộc bố cục hiển thị.
#
# KHÔNG lọc bằng comment: ufw lưu comment dạng hex
# (comment=7a3264206e657874646e73203533 = "z2d nextdns 53") nên grep chữ "z2d"
# luôn ra 0 dòng.
#
# Lặp tối đa 3 lần: một đặc tả "any" tạo RA HAI rule (v4 + v6) và ufw đôi khi
# chỉ xoá một; lặp lại cho tới khi báo "non-existent" thì hết.
ufw_del_port() { # ufw_del_port <ALLOW|DENY> <IN|OUT> <addr> <port> <proto>
  local act dir addr port proto n=0 r
  # HẠ CHỮ thông điệp và hướng trước khi gọi ufw.
  #
  #   `ufw` PHÂN BIỆT HOA/THƯỜNG — đo được:
  #       $ ufw delete ALLOW OUT to 45.90.28.0 port 53 proto udp
  #       ERROR: Invalid syntax
  #       $ ufw delete allow out to 45.90.28.0 port 53 proto udp
  #       Rule deleted
  #
  #   Bản đầu truyền thẳng `$act`/`$dir` xuống ufw, mà nơi gọi truyền chữ HOA
  #   (ALLOW/DENY, IN/OUT) — nên KHÔNG lần nào xoá được. uninstall im lặng để
  #   lại toàn bộ 20 rule, chỉ in một dòng cảnh báo. Hạ chữ ở đây thì nơi gọi
  #   viết HOA hay thường đều chạy, không còn phụ thuộc.
  act=${1,,}; dir=${2,,}; addr=$3; port=$4; proto=${5,,}
  # Xoá tới khi hết, không giới hạn 3 lần: lệnh "deny out to any" sinh RA HAI
  # rule (v4 + v6) nên phải gọi hai lần mới sạch, và 3 là số tùy ý.
  while [ "$n" -lt 8 ]; do
    # Cú pháp phải KHỚP ĐÚNG lệnh đã thêm rule, không tự bịa:
    #   rule DNS (OUT) : ufw allow out to <ip>  port 53  proto udp
    #   rule KDE (IN)  : ufw allow in  from <src> to any port 1714:1764 proto tcp
    # Đảo vị trí from/to là "ERROR: Invalid syntax" và ufw không xoá gì cả.
    if [ "$addr" = "any" ]; then
      r=$(ufw delete "$act" out to any port "$port" proto "$proto" 2>&1)
    elif [ "$dir" = in ]; then
      r=$(ufw delete "$act" in from "$addr" to any port "$port" proto "$proto" 2>&1)
    else
      r=$(ufw delete "$act" out to "$addr" port "$port" proto "$proto" 2>&1)
    fi
    case "$r" in
      *"non-existent"*|*"Skipping"*|*"Invalid syntax"*|*"ERROR"*) break ;;
    esac
    n=$((n + 1))
  done
  [ "$n" -gt 0 ]
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

# Đọc JSON theo ĐƯỜNG DẪN, không dùng eval.
#
#   nd_get   <tệp> <a.b.c>   in giá trị (rỗng nếu không có)
#   nd_count <tệp> <a.b>     in số phần tử của mảng (0 nếu không có)
#   nd_flag  <tệp> <a.b>     in "bat" nếu giá trị ĐÚNG, "tat" nếu sai
#
# Bản đầu truyền vào một BIỂU THỨC python rồi `eval` nó. Hiện tại không có dữ
# liệu người dùng nào chạm tới eval — toàn bộ chuỗi truyền vào đều là hằng số
# viết trong chính script này. Nhưng `eval` trong script chạy dưới quyền root
# thì không đáng giữ, và người đọc phải tự chứng minh điều đó mỗi lần sửa.
# Ở đây chỉ cần 3 thao tác, nên làm thẳng cho rõ.
_nd_py() { # _nd_py <tệp> <chế độ> <đường dẫn>
  python3 - "$1" "$2" "$3" <<'NDJSON' 2>/dev/null || true
import json, sys
try:
    cur = json.load(open(sys.argv[1])).get('data') or {}
except Exception:
    print(''); raise SystemExit
for k in filter(None, sys.argv[3].split('.')):
    if not isinstance(cur, dict) or k not in cur:
        cur = None; break
    cur = cur[k]
mode = sys.argv[2]
if cur is None:        out = ''
elif mode == 'count': out = str(len(cur)) if hasattr(cur, '__len__') else ''
elif mode == 'flag':  out = 'bat' if cur else 'tat'
else:                 out = cur if isinstance(cur, str) else ''
print(out)
NDJSON
}
nd_get()   { _nd_py "$1" get   "$2"; }
nd_count() { _nd_py "$1" count "$2"; }
nd_flag()  { _nd_py "$1" flag  "$2"; }

# nd_check — gọi sau khi đã kiểm định dạng ID. Chết (die) nếu ID sai; mọi
# trường hợp không kiểm được thì chỉ cảnh báo, không chặn cài.
nd_check() {
  local kf body code name dn al bl

  command -v curl >/dev/null 2>&1 || {
    warn "không có curl — BỎ QUA kiểm ID NextDNS. Nếu ID sai, mọi tầng vẫn chạy nhưng không lọc."
    return 0
  }

  if ! kf=$(nd_key_path); then
    warn "không tìm thấy API key NextDNS — BỎ QUA kiểm ID."
    warn "ID sai sẽ không báo lỗi, chỉ chạy nhưng không lọc."
    warn "Đặt key ở /root/.config/nextdns/api.key (quyền 600), hoặc dùng --nd-key /đường/dẫn,"
    warn "rồi chạy lại để có kiểm. Kiểm tay: dig +short <một tên miền profile của bạn chặn>"
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
        warn "Kiểm tay: dig +short <một tên miền profile của bạn chặn>"; return 0 ;;
    "")  rm -f "$body"
        warn "không gọi được api.nextdns.io (mất mạng, hoặc bị chặn) — BỎ QUA kiểm ID."
        warn "Cài xong nhớ kiểm tay: dig +short <một tên miền profile của bạn chặn>"; return 0 ;;
    *)   rm -f "$body"
        warn "API trả HTTP $code lạ (thường là 429 quá nhiều request) — BỎ QUA kiểm ID."
        warn "Kiểm tay: dig +short <một tên miền profile của bạn chặn>"; return 0 ;;
  esac

  # Tới đây là ID thật. Báo tình trạng — đây là thứ mà bản cũ thiếu hẳn:
  # người dùng không có cách nào biết tầng 2 có thật sự lọc không.
  name=$(nd_get   "$body" name)
  dn=$(nd_count   "$body" denylist)
  al=$(nd_count   "$body" allowlist)
  bl=$(nd_count   "$body" privacy.blocklists)
  ok "profile NextDNS: ${name:-?} (ID $ND_ID)"
  ok "trên đám mây: $bl blocklist · $dn mục chặn · $al mục cho qua"

  # Hai công tắc này quyết định gần như hết kết quả. Tắt thì tầng 2 vẫn
  # "chạy" nhưng phần lớn chặn biến mất — và đó cũng là kiểu hỏng im lặng.
  #
  # nd_flag in "bat" khi công tắc BẬT, "tat" khi TẮT. Phải cảnh báo khi nó là
  # "tat". Bản đầu kiểm [ -z ] trên chuỗi rỗng-mặc-định-khi-bật — tức cảnh
  # báo đúng lúc mọi thứ ổn và im lặng đúng lúc hỏng. Đảo điều kiện là cảnh báo
  # hỏng nhất, vì nó dạy người đọc bỏ qua cảnh báo.
  for sw in aiThreatDetection threatIntelligenceFeeds; do
    [ "$(nd_flag "$body" "security.$sw")" = tat ] \
      && warn "công tắc $sw đang TẮT — nhiều trang sẽ không bị chặn"
  done
  rm -f "$body"
  return 0
}

# -----------------------------------------------------------------------------
#  Cài gói phụ thuộc
#
#  Máy mới cài Arch/CachyOS thường thiếu nftables, ufw, make, gcc… Bản đầu chỉ
#  kiểm rồi chết, đẩy hết việc pacman ra cho người dùng tự gõ.
#
#  Hỏi bằng `pacman -Qq` chứ không `command -v`: cần biết CÓ GÓI hay không,
#  vì `command -v` trả về 0 ngay cả khi gói đã bị gỡ mà lệnh còn sót.
#
#  --dry không cài gì cả, chỉ báo đang thiếu gì.
# -----------------------------------------------------------------------------
need_pkgs() {
  local p miss=()
  for p in "$@"; do
    pacman -Qq "$p" >/dev/null 2>&1 || miss+=("$p")
  done
  [ ${#miss[@]} -eq 0 ] && return 0
  if [ "$DRY" = 1 ]; then
    say "    [dry] thiếu gói, sẽ cài: ${miss[*]}"
    return 0
  fi
  say "  thiếu gói: ${miss[*]}"
  say "  đang cài bằng pacman (có thể hỏi mật khẩu quản trị)…"
  # KHÔNG nuốt lỗi trong im lặng: pacman hỏng thì phải báo, không in "đã cài".
  pacman -S --needed --noconfirm "${miss[@]}" \
    || die "pacman không cài được: ${miss[*]}. Cài tay rồi chạy lại:
       sudo pacman -S --needed ${miss[*]}"
  ok "đã cài: ${miss[*]}"
}


# =============================================================================
# Đường GỠ chạy ở đây — sau TẤT CẢ định nghĩa hàm, trước bước 1.
# Đặt sớm hơn thì ufw_del_port chưa tồn tại lúc gọi.
[ "$ACTION" = uninstall ] && uninstall

# =============================================================================
step "1/8 · KIỂM TRA MÁY"
if [ "$ACTION" = install ]; then
  # Đủ 3 tầng + 3 lớp phòng thủ. Bỏ gói nào thì tầng đó hỏng, nên cài hết một
  # lượt thay vì mỗi tầng tự cài — người dùng chỉ phải đồng ý một lần.
  #   nftables      : nft, tầng 1 (FWTYPE=nftables) + tầng 2b/3
  #   ufw           : tường DNS + chặn INPUT
  #   networkmanager: ignore-auto-dns (tầng 2)
  #   procps-ng     : sysctl, 18 khoá hardening
  #   iproute2      : ip, dùng khi kiểm route
  #   git, make, gcc: clone + build zapret2
  need_pkgs nftables ufw networkmanager procps-ng iproute2 git make gcc
  ok "đủ lệnh cần thiết"
ok "đủ lệnh cần thiết"
  # Kiểm đủ TẬP config cần thiết, ngay ở bước 1.
  #
  #   Bản đầu không kiểm. Đo được: xoá `config/z2d-exclude.txt` rồi chạy
  #   `--dry`, nó vẫn in "XEM XONG — chưa thay đổi gì cả" và exit 0. Nghĩa là
  #   `--dry` — thứ đúng ra để BẮT LỖI TRƯỚC KHI CÀI — lại không thấy lỗi.
  #   Chạy thật thì chết muộn ở bước 4 với câu "cần đúng 9 dải loại trừ,
  #   config đang có 0", trỏ nhầm vào con số thay vì vào tệp đang thiếu.
  #
  #   Liệt kê đủ 9 tệp thay vì chỉ kiểm thư mục `config/` có tồn tại: thư mục
  #   có nhưng thiếu một tệp thì vẫn hỏng, và đó mới là lỗi hay gặp (clone
  #   thiếu, cài tay dán bừa).
  miss_conf=
  for f in z2d-exclude.txt z2d-hosts-user.txt z2d-pacman-ufw.hook \
           z2d-resolved.conf.template z2d-sysctl-apply z2d-sysctl.conf \
           z2d-ufw-reapply-sysctl.conf z2d-zapret2-opt z2d-zapret2.keys; do
    [ -f "$CONF/$f" ] || miss_conf="$miss_conf $f"
  done
  if [ -n "$miss_conf" ]; then
    die "thiếu tệp config trong $CONF:$miss_conf
       Lấy lại repo:  git -C $REPO_DIR pull
       rồi chạy lại. Thiếu tệp thì --dry vẫn chạy được nhưng lúc cài thật
       sẽ chết giữa chừng."
  fi
  ok "đủ 9 tệp config"

  # Chấp nhận CHỮ HOA, rồi hạ về chữ thường.
  #
  #   Bản đầu dùng `^[0-9a-f]{6}$` nên từ chối `785FAD`. Nhưng ID hoa VẪN ĐÚNG:
  #   đo được — API NextDNS trả 200 cho cả `785fad`, `785FAD`, `785Fad`; và
  #   bắt tay TLS thẳng với `<id>.dns.nextdns.io` cho cả ba đều trả về đúng
  #   238 byte. Tức là chỗ bị chặn là hoàn toàn dùng được, và người dùng dán
  #   ID từ nguồn nào đó in hoa thì bị chặn với lý do sai.
  #
  #   Hạ về chữ thường để `785FAD.dns.nextdns.io` không bao giờ lọt vào
  #   `resolved.conf` — file đó được so khớp byte với bản trong repo.
  printf '%s' "$ND_ID" | grep -qE '^[0-9a-fA-F]{6}$' \
    || die "--nd-id phải 6 ký tự hex (0-9a-fA-F), bạn đưa '${ND_ID:-<rỗng>}' — lấy ở my.nextdns.io"
  ND_ID=${ND_ID,,}
  ok "ID NextDNS: $ND_ID"
  nd_check
fi

# =============================================================================
step "2/8 · SAO LƯU VÀO $BACKUP"
# KHÔNG nuốt lỗi: bản đầu có `2>/dev/null` và mất im lặng 41 tệp, trong đó mất
# cả opt/zapret2/config — đúng thứ cần để quay lại.
if [ "$DRY" = 1 ]; then
  ok "[dry] sẽ ghi đè $BACKUP"
else
  st=$(mktemp -d /var/backups/.z2d.XXXXXX) \
    || die "không tạo được thư mục tạm trong /var/backups — hãy kiểm tra dung lượng và quyền"
  # `mktemp` hỏng mà không kiểm thì `st` RỖNG, và `mkdir -p "$st/etc/..."` sẽ
  # tạo nhầm trong chính /etc. Lỗi này bị che vì `mkdir` chạy thành công.
  #
  # Dọn thư mục tạm khi chết giữa chừng: `die` ở bước sao lưu / tar xảy ra
  # TRƯỚC khi `mv "$st" "$BACKUP"`, nên mỗi lần chết là thêm một thư mục rác
  # trong /var/backups. Sau khi `mv` xong, $st không còn tồn tại ⇒ trap vô hại.
  #   CHỈ xoá khi tên khớp ĐÚNG mẫu của mktemp — `rm -rf` với biến rỗng là
  #   bi kịch, nên không được bỏ chặt kiểm tra này.
  st_gc() { case "${st:-}" in /var/backups/.z2d.*) rm -rf -- "$st" ;; esac; }
  trap st_gc EXIT

  # BẮT TÍN HIỆU. `trap ... EXIT` một mình là chưa đủ.
  #
  #   Đo bằng pty thật (đúng cách Ctrl-C gửi ):
  #     bản cũ — chỉ có `trap … EXIT`:
  #         in "BUOC-A" → Ctrl-C → DỪNG, không in gì thêm → exit 0
  #     bản mới — có `trap … INT TERM`:
  #         in "BUOC-A" → Ctrl-C → in "DỪNG do tín hiệu" → exit 130
  #
  #   Tức script CÓ dừng (và EXIT trap có dọn thư mục tạm — đo được 0 mục rác).
  #   Lỗi thật là **im lặng và trả 0**: người dùng bấm Ctrl-C lúc `make` đang
  #   chạy ở bước 3, thấy exit 0 thì tưởng cài xong, trong khi thực tế máy có
  #   thể đang ở giữa chừng và không ai canh giữ nữa.
  #
  #   Ghi lại cả nhầm lẫn của tôi: lần đầu tôi gửi tín hiệu bằng
  #   `kill -INT -- -$PID` cho nhóm của tiến trình `setsid`, quan sát thấy script
  #   vẫn in các dòng sau, và kết luận "không dừng". Cách gửi đó không giống
  trap on_sig INT TERM
  mkdir -p "$st/etc/systemd/system/ufw.service.d" "$st/etc/sysctl.d" \
           "$st/etc/ufw" "$st/etc/default" "$st/etc/pacman.d/hooks" "$st/opt/zapret2"
  # BẢN ĐẦU NUỐT LỖI Ở ĐÂY, VÀ ĐÂY CHÍNH LÀ CHỖ NGUY HIỂM NHẤT.
  #   `[ -e "$f" ] && cp ... || true` — `|| true` bắt cả hai ca: file không tồn
  #   tại (vô hại) VÀ cp hỏng (mất tệp backup mà không ai biết). Rồi
  #   `--uninstall` xoá hẳn những tệp không có trong backup ⇒ cài xong, gỡ là
  #   MẤT luôn không thể quay lại.
  #   Nên: tệp có thật mà cp hỏng thì CHẾT, kèm tên tệp.
  n_bk=0 n_bkbad=0 n_keepbk=0
  # `/etc/resolv.conf` PHẢI có mặt. Bản đầu không có, mà bước 5 lại `rm -f` rồi
  # tạo symlink trỏ stub ⇒ khi uninstall, tệp gốc không có chỗ nào để khôi phục.
  #   Nguy hiểm nhất khi nó vốn là TỆP THẬT chứ không phải symlink: máy dùng
  #   resolvconf, hoặc admin tự viết. Mất luôn, không phục hồi được.
  #   `cp -a` giữ nguyên symlink (không chép theo đích) nên phục hồi đúng cả hai.
  #   Phần khôi phục phải `rm` trước — nếu không, `cp` sẽ đi theo symlink stub
  #   và ghi đè mất `/run/systemd/resolve/stub-resolv.conf`.
  for f in /etc/systemd/resolved.conf /etc/sysctl.d/60-z2d-hardening.conf \
           /etc/ufw/sysctl.conf /etc/ufw/z2d-sysctl.conf /etc/default/ufw \
           /etc/nftables.conf /etc/pacman.d/hooks/z2d-pacman-ufw.hook \
           /etc/resolv.conf; do
    [ -e "$f" ] || continue                       # chưa có thì không cần lưu
    # KHÔNG ghi đè tệp backup đã có. Đây là chỗ làm HỎNG bản sao lưu.
    #
    #   Bản đầu ở cuối bước 2 chạy `rm -rf "$BACKUP"` rồi `mv "$st" "$BACKUP"`
    #   — tức MỖI lần cài đều xoá sạch backup cũ, thay bằng trạng thái HIỆN
    #   TẠI. Mà lần cài #1 đã sửa `/etc/default/ufw` (đặt
    #   `IPT_SYSCTL=/etc/ufw/z2d-sysctl.conf`). Nên lần cài #2 sao lưu chính
    #   tệp ĐÃ SỬA. Đo được:
    #     backup/etc/default/ufw : sha 38ed8cb2 · có `z2d-sysctl`   ← bị đầu
    #     /etc/default/ufw       : sha 38ed8cb2 · có `z2d-sysctl`   ← y hệt
    #   ⇒ uninstall in "khôi phục 7 tệp" xong vẫn còn dấu z2d trong tệp của
    #     gói, `pacman -Qkk ufw` vẫn báo SHA256 mismatch ⇒ KHÔNG BAO GIỜ quay
    #     được về bản gốc của gói. Đây là lỗi S2 theo tiêu chí F-item.
    #
    #   Sửa: tệp nào đã có trong backup thì GIỮ bản cũ (lần cài đầu là lúc máy
    #   còn nguyên). Chỉ chép những tệp backup chưa có.
    if [ -e "$BACKUP$f" ]; then
      # PHẢI chép bản CŨ sang $st, không được chỉ `continue`.
      #   Vì cuối bước 2 là `rm -rf "$BACKUP"` + `mv "$st" "$BACKUP"` — tức
      #   thay THẬT SỰ cả thư mục backup. Nếu chỉ bỏ qua thì $st không có tệp
      #   đó, và sau mv thì backup MẤT HẲN tệp. Đo được: lần cài #2 in
      #   "GIỮ 8 tệp từ lần cài trước" rồi `sha256sum backup/etc/default/ufw`
      #   → "No such file or directory", rồi uninstall in "0 tệp khôi phục".
      mkdir -p "$(dirname "$st$f")"
      cp -a "$BACKUP$f" "$st$f" 2>/dev/null \
        || die "giữ bản sao lưu cũ của $f thất bại — dừng, chưa sửa gì trên máy"
      n_keepbk=$((n_keepbk + 1))
      # "Bị đầu" chỉ có nghĩa với TỆP CỦA GÓI: tệp mà ta tự tạo (tên `z2d-*`)
      # thì có dấu z2d là CHUYỆN BÌNH THƯỜNG, không phải backup hỏng.
      # Lần sửa đầu báo nhầm cho 60-z2d-hardening.conf và z2d-sysctl.conf.
      if pacman -Qo "/$f" >/dev/null 2>&1 \
         && grep -q 'z2d-sysctl\.conf' "$BACKUP$f" 2>/dev/null; then
        warn "bản sao lưu của $f ĐÃ BỊ ĐẦU (tệp của gói mà trong đó có dấu z2d)"
        warn "  — bản gốc của gói đã mất. Gỡ sạch thật thì: sudo rm -rf $BACKUP"
        warn "  rồi cài lại từ đầu."
      fi
      continue
    fi
    if cp -a --parents "$f" "$st/" 2>/dev/null; then
      n_bk=$((n_bk + 1))
    else
      bad "sao lưu hỏng: $f — dừng, chưa sửa gì trên máy"
      n_bkbad=1
    fi
  done
  # Drop-in của ufw: KHÔNG dùng `|| true`, vì glob không khớp thì hợp lệ (chưa
  # có drop-in nào) nhưng cp hỏng thì không — nên phân biệt bằng cách xem có
  # file nào khớp glob hay không.
  shopt -s nullglob
  ufw_dropins=(/etc/systemd/system/ufw.service.d/*.conf)
  shopt -u nullglob
  # Giữ bản backup drop-in đầu tiên, cùng lý do ở vòng lặp tệp cấu hình.
  if [ -d "$BACKUP/etc/systemd/system/ufw.service.d" ]; then
    cp -a "$BACKUP/etc/systemd/system/ufw.service.d/." \
      "$st/etc/systemd/system/ufw.service.d/" 2>/dev/null || true
    ufw_dropins=()
  fi
  if [ "${#ufw_dropins[@]}" -gt 0 ]; then
    if ! cp -a "${ufw_dropins[@]}" "$st/etc/systemd/system/ufw.service.d/" 2>/dev/null; then
      bad "sao lưu drop-in ufw.service.d hỏng — dừng"
      n_bkbad=1
    else
      n_bk=$((n_bk + ${#ufw_dropins[@]}))
    fi
  fi
  [ "$n_bkbad" -eq 0 ] || die "sao lưu chưa đủ — KHÔNG tiếp tục, vì uninstall sẽ mất tệp không sao lưu"
  if [ "$n_keepbk" -gt 0 ]; then
    ok "sao lưu $n_bk tệp mới · GIỮ $n_keepbk tệp từ lần cài trước"
    say "    (giữ bản cũ vì chỉ lần cài ĐẦU mới chụp được lúc máy còn nguyên;"
    say "     nếu ghi đè thì backup chứa tệp ĐÃ SỬA và uninstall gỡ không trọn)"
  else
    ok "sao lưu $n_bk tệp cấu hình"
  fi
  if [ -d "$ZAPRET_DIR" ]; then
    # Chỉ sao lưu thứ ĐANG CÓ, không giả định.
    #
    #   Bản đầu thấy /opt/zapret2 tồn tại là `cp -a $ZAPRET_DIR/config` thẳng.
    #   Nhưng `git clone` + `make systemd` chỉ tạo ra `config.default`; file
    #   `config` do chính bước 4 của installer mới sinh ra. Đo được khi cài
    #   trên máy trắng: clone xong, bước 3 chết (vì lỗi SIGPIPE ở trên), chạy
    #   lại installer thì bước 2 chết ngay vì /opt/zapret2/config chưa tồn tại
    #   ⇒ CÀI LẠI KHÔNG ĐƯỢC sau khi hỏng giữa chừng. Đúng thứ khách sạn gặp
    #   nhất: cài hỏng một lần là phải xoá tay rồi làm lại từ đầu.
    #
    #   `tar` bên dưới vẫn nén trọn /opt/zapret2 nên không mất gì.
    n_z2=0
    for sub in config ipset; do
      if [ -e "$ZAPRET_DIR/$sub" ]; then
        cp -a "$ZAPRET_DIR/$sub" "$st/opt/zapret2/" \
          || die "sao lưu $sub zapret2 thất bại — dừng"
        n_z2=$((n_z2 + 1))
      else
        say "    /opt/zapret2/$sub chưa có — bỏ qua (chưa tới bước cấu hình)"
      fi
    done
    # Giữ bản nén đầu tiên — "trạng thái trước khi cài" là của lần cài ĐẦU.
    if [ -e "$BACKUP/opt-zapret2.tar.gz" ]; then
      cp -a "$BACKUP/opt-zapret2.tar.gz" "$st/opt-zapret2.tar.gz"
    else
      tar -C / -czf "$st/opt-zapret2.tar.gz" opt/zapret2 || die "nén /opt/zapret2 thất bại"
      tar -tzf "$st/opt-zapret2.tar.gz" >/dev/null 2>&1 || die "file nén hỏng — dừng"
    fi
  fi
  ufw status numbered > "$st/ufw-numbered.txt" 2>/dev/null || true
  # Lưu policy INPUT để khôi phục khi gỡ. `ufw status verbose` bên dưới chỉ
  # để NGƯỜI ĐỌC, không được code dùng lại. Bản đầu chỉ set `ufw default deny
  # incoming` mà không lưu giá trị cũ ⇒ uninstall xong vẫn còn deny dù hệ thống
  # đã bị gỡ hết, và người dùng dễ quy nhầm cho ufw.
  # Policy INPUT: GIỮ bản ghi ĐẦU TIÊN. Nếu ghi đè, lần cài #2 sẽ lưu "drop"
  # (giá trị chính bước 3 đặt), uninstall "khôi phục" về drop ⇒ gỡ xong vẫn
  # chặn vào — đúng cái lỗi mà việc lưu policy này sinh ra để tránh.
  # Cờ ENABLED của ufw — thứ mà `ufw-policy-in.txt` KHÔNG nắm được.
  #
  #   Đo được: đặt nền `ENABLED=no` (ufw tắt) → cài (`bước 6` gọi
  #   `ufw --force enable`, nên bật lên `yes`) → gỡ. Kết quả:
  #       trước khi cài : ENABLED=no
  #       sau khi cài   : ENABLED=yes
  #       sau khi gỡ    : ENABLED=yes   ← PHẢI là `no`
  #   Tức uninstall để lại tường đang bật dù người dùng chưa từng bật: đây là
  #   F-item "unit enabled" không revert (S2). Hướng hậu quả là fail-secure
  #   (tường còn chạy) nên không phải lỗ hổng, nhưng vẫn là trạng thái ngoài ý
  #   muốn và người dùng không đoán được.
  #
  #   Chiều ngược lại (nền `ENABLED=yes`) thì ĐÚNG rồi: uninstall không gọi
  #   `ufw disable` nên giữ nguyên `yes`. Đo cả hai hướng, không đoán hướng.
  if [ -e "$BACKUP/ufw-enabled.txt" ]; then
    cp -a "$BACKUP/ufw-enabled.txt" "$st/ufw-enabled.txt"
  else
    sed -n 's/^ENABLED=//p' /etc/ufw/ufw.conf 2>/dev/null | head -1 \
      > "$st/ufw-enabled.txt" 2>/dev/null || true
  fi
  if [ -e "$BACKUP/ufw-policy-in.txt" ]; then
    cp -a "$BACKUP/ufw-policy-in.txt" "$st/ufw-policy-in.txt"
  else
    ufw status verbose 2>/dev/null | sed -n 's/^Default: \([a-z]*\) (incoming).*/\1/p' \
      > "$st/ufw-policy-in.txt" 2>/dev/null || true
  fi
  nft list ruleset   > "$st/nft-ruleset.txt"   2>/dev/null || true
  { echo "Sao lưu chuẩn — $(date -Is)"
    echo "Phục hồi: sudo bash install.sh --uninstall"; } > "$st/BAO-GHI.txt"
  rm -rf "$BACKUP"; mkdir -p "$(dirname "$BACKUP")"; mv "$st" "$BACKUP" \
    || die "không chuyển được $st thành $BACKUP — bản sao lưu cũ đã bị xoá, kiểm $st"
  trap - EXIT   # $st đã thành $BACKUP; tắt trap dọn để không xoá nhầm bản sao lưu
  ok "đã ghi $BACKUP ($(find "$BACKUP" -type f | wc -l) file)"
fi

# =============================================================================
step "3/8 · TẦNG 1 — zapret2"
if [ -x "$ZAPRET_DIR/nfq2/nfqws2" ]; then
  ok "$ZAPRET_DIR đã có sẵn"
elif [ "$DRY" = 1 ]; then
  ok "[dry] sẽ cài gói build, clone $ZAPRET_TAG rồi 'make systemd'"
else
  # ---- 1. CÀI GÓI, PHẢI TRƯỚC KHI BUILD ----
  # KHÔNG cài sau. Bản đầu kiểm 5 thư viện SAU khi build, sai thứ tự: nfq2/Makefile
  # dùng chúng ở cả lúc BIÊN DỊCH lẫn lúc LIÊN KẾT
  #   LIBS_LINUX = -lz -lnetfilter_queue -lnfnetlink -lmnl -lm
  # Trên Arch, gói runtime cũng chứa header (không tách -dev như Debian), nên thiếu
  # gói ⇒ make fail NGAY, chẳng bao giờ tới bước kiểm thư viện phía sau.
  #   git      : clone repo
  #   make gcc : biên dịch (nfq2 là C thuần: 29 file .c, 0 file .go — KHÔNG cần go)
  #   pkgconf  : pkg-config tìm luajit. Thiếu vẫn build được nhờ fallback trong
  #              Makefile (/usr/lib/libluajit-5.1.*), nhưng có pkgconf thì chắc chắn
  #   zlib libnetfilter_queue libnfnetlink libmnl luajit : theo LIBS_LINUX + Lua
  #   curl     : zapret2 tự liệt kê là điều kiện (check_prerequisites_linux), và
  #              chính install.sh cũng dùng curl ở nd_check
  need_pkgs git make gcc pkgconf zlib libnetfilter_queue libnfnetlink libmnl luajit curl

  # ---- 2. CLONE ----
  # KHÔNG cần `go`: nfq2 là C thuần. Bản đầu có `go` trong danh sách gói build —
  # vô dụng ở đây và nặng hàng trăm MB.
  rm -rf "$ZAPRET_DIR"
  git clone --depth 1 --branch "$ZAPRET_TAG" "$ZAPRET_REPO" "$ZAPRET_DIR" \
    || die "git clone thất bại — kiểm mạng rồi thử lại"

  # ---- 3. BUILD ----
  # Target `systemd`, KHÔNG phải `all`. Đây là điểm bản đầu sai.
  #
  #   Makefile zapret2 chỉ có: all · systemd · android · bsd · clean.
  #   `make nfq` không tồn tại → "No rule to make target 'nfq'. Stop."
  #   Riêng `make all` thì build được, NHƯNG cho binary KHÔNG có sd_notify.
  #
  #   Target `systemd` thêm -DUSE_SYSTEMD + -lsystemd, khiến nfqws2 tự gọi
  #   sd_notify(0, "READY=1") (nfqws.c:435). Đo trên máy này:
  #       binary đang chạy : sd_notify=1  READY=1=1  288768 byte
  #       build bằng `all` : sd_notify=0  READY=1=0  232216 byte
  #   Tức binary đang chạy do build `systemd`. Installer chính thức của zapret2
  #   cũng vậy — install_easy.sh đặt make_target=systemd khi SYSTEM=systemd.
  #   Dùng `all` là lệch cả máy lẫn upstream.
  #
  # Cờ build y hệt install_easy.sh: OPTIMIZE=-O2 CFLAGS=-march=native.
  #   Makefile mặc định OPTIMIZE=-Os (ưu tiên nhỏ), installer chính thức đổi sang
  #   -O2 vì nfqws2 nằm trên đường dữ liệu, tốc độ quan trọng hơn kích thước.
  #   -march=native tinh chỉnh cho CPU của máy đang cài (build tại chỗ nên hợp lệ).
  CFLAGS="-march=native" OPTIMIZE=-O2 make -C "$ZAPRET_DIR" systemd >/dev/null 2>&1 || {
    echo "  --- log build ---" >&2
    CFLAGS="-march=native" OPTIMIZE=-O2 make -C "$ZAPRET_DIR" systemd 2>&1 | tail -20 >&2
    die "build thất bại (xem log trên)"
  }
  [ -x "$ZAPRET_DIR/nfq2/nfqws2" ] || die "build xong nhưng không thấy nfq2/nfqws2"
  # Kiểm đúng target, không chỉ kiểm "binary tồn tại": `all` cũng cho binary tồn
  # tại, chỉ khác ở chỗ không có sd_notify.
  if nm -D "$ZAPRET_DIR/binaries/my/nfqws2" 2>/dev/null | grep -q sd_notify; then
    ok "đã build nfq2/nfqws2 ($ZAPRET_TAG, target systemd, có sd_notify)"
  else
    die "binary không có sd_notify — build sai target, phải là 'systemd' chứ không phải 'all'"
  fi

  # ---- 4. THƯ VIỆN LÚC CHẠY ----
  # Đã cài ở bước 1 vì cần cho build. Ở đây chỉ XÁC NHẬN: nếu gói lỡ bị gỡ
  # giữa hai lúc, service sẽ chết lúc start với "error while loading shared
  # libraries" — lỗi không nói ra nguyên nhân.
  # Tên biến khác `miss` vì `miss` đã là MẢNG trong need_pkgs; dùng lại ở đây
  # khiến shellcheck báo SC2178 và dễ gây lỗi khi sửa tiếp.
  # GỌI `ldconfig -p` ĐÚNG MỘT LẦN, rồi so khớp bằng bash thuần.
  #
  #   Bản đầu viết `ldconfig -p | grep -qF "$lib"` cho từng thư viện. Đó là
  #   lỗi CHẶN CÀI ĐẶT trên máy trắng, và chỉ lộ ra ở đây:
  #
  #     $ set -o pipefail; ldconfig -p | grep -qF libz.so.1; echo $?
  #     141
  #
  #   `grep -q` thoát ngay khi thấy kết quả đầu tiên ⇒ `ldconfig` đang ghi bị
  #   SIGPIPE (141) ⇒ `pipefail` lấy 141 ⇒ dấu "||" bắt ⇒ coi thư viện ĐANG CÓ
  #   là THIẾU rồi `die`. Đo trên máy này: 20/20 lần thất bại, cả 5 thư viện.
  #   Bỏ `pipefail` thì 0 lần thất bại.
  #
  #   Nguyên nhân sâu hơn: bộ đệm pipe chỉ 64 KB. Output của `ldconfig -p` ở đây
  #   là 3760 dòng (~300 KB) nên vượt đệm → tiến trình ghi bị chặn → grep thoát
  #   → SIGPIPE. Còn `nm -D` chỉ 212 dòng (~17 KB) thì nằm vừa đệm, chạy
  #   100/100 lần không lỗi — cùng mẫu lệnh, khác hành vi. Đừng thấy "chỗ này
  #   chạy được" rồi mặc định chỗ kia cũng vậy.
  #
  #   Sửa bằng cách bỏ `grep -q`: lấy danh sách một lần rồi `case` thuần bash.
  #   Vừa hết pipeline (không còn SIGPIPE), vừa nhanh hơn — bản cũ chạy
  #   `ldconfig` 5 lần cho 5 thư viện.
  ld_list=$(ldconfig -p 2>/dev/null || true)
  [ -n "$ld_list" ] || die "ldconfig không trả về danh sách thư viện nào — không kiểm được tầng 1"
  n_lib=0; ten_lib=""
  for lib in libnetfilter_queue.so.1 libnfnetlink.so.0 libmnl.so.0 \
             libluajit-5.1.so.2 libz.so.1; do
    case "$ld_list" in
      *"$lib"*) : ;;
      *) n_lib=$((n_lib + 1)); ten_lib="$ten_lib $lib" ;;
    esac
  done
  if [ "$n_lib" -eq 0 ]; then
    ok "thư viện lúc chạy: đủ 5"
  else
    die "thiếu thư viện lúc chạy:$ten_lib
       sudo pacman -S libnetfilter_queue libnfnetlink libmnl luajit zlib"
  fi

  # ---- 5. SYSTEMD UNIT ----
  # Bản đầu KHÔNG copy unit, chỉ gọi `systemctl enable`/`restart`. Trên máy mới
  # thì không có unit để enable, `systemctl restart` chết, và tầng 1 mất.
  # Máy đang chạy có unit ở /usr/lib/systemd/system/ do cài tay từ trước, nên
  # bản đầu chạy trơn và lỗi này không lộ.
  #
  # Cài vào /etc/systemd/system/ (đúng chỗ dành cho unit cục bộ), đè lên bản
  # trong /usr/lib nếu có. File lấy từ chính repo đã ghim, không tự viết tay —
  # ExecStart trỏ vào init.d/sysv/zapret2, tức nơi binary vừa dựng xong.
  #
#
# SAI Ở MỘT CHỖ, CỐ Ý GIỮ NGUYÊN: đây là 3 unit mà install_easy.sh cài
# (service_install_systemd + timer_install_systemd), nhưng ta CHỈ enable
# `zapret2.service`, KHÔNG enable `zapret2-list-update.timer`. Upstream thì
# enable cả hai (install_easy.sh:559).
#
#   Đo được: `GETLIST=` trong config RỖNG, nên get_config.sh (ExecStart của
#   list-update.service) không có gì để tải — chạy tay thì chỉ in
#   "reloading nftables set backend (forced-update)" rồi thoát 0, config
#   không đổi (đã diff), zapret2 vẫn chạy. Tức bật timer cũng vô hại, nhưng
#   cũng vô dụng: cứ 2 ngày lúc 00:00 chạy một việc không có việc gì.
#
#   Nên comment cũ "Đây cũng là 3 unit mà install_easy.sh cài" đọc ra như thể
#   ta bám sát upstream cả về hành vi, và không đúng. Giữ file unit cho khớp
#   bộ của upstream (và để ai đó tự enable được), nhưng nói thẳng ra là không
#   bật, và vì sao.
  fi

  # ---- 3 unit systemd: cài ở MỌI nhánh, không chỉ nhánh clone ----
  #
  #   Bản đầu đặt khối này TRONG nhánh `else` (nhánh clone). Hệ quả: máy đã có
  #   /opt/zapret2 thì nhánh "đã có sẵn" chạy, khối bị bỏ qua, và unit KHÔNG
  #   BAO GIỜ được cài — dù máy trắng hoàn toàn, không có unit nào ở /etc lẫn
  #   /usr/lib. Đo được: sau khi xoá sạch, chạy installer thì bước 4 chết với
  #   "Failed to restart zapret2.service: Unit zapret2.service not found".
  #
  #   Đây là lỗi thứ BAO cùng loại trong một installer: logic quan trọng bị nhét
  #   vào nhánh không phải lúc nào cũng chạy. Hai người trước là kiểm thư viện
  #   và tạo config — đều chỉ lộ ra khi làm trắng máy.
  #
  #   Nguồn là `init.d/systemd/` TRONG BẢN CLONE zapret2, không phải repo dotfile
  #   (repo này không có file .service nào — `git ls-files` xác nhận). Comment
  #   cũ ghi "file lấy từ chính repo đã ghim" là SAI, đã sửa ở đây.
  if [ "$DRY" = 1 ]; then
    say "    [dry] sẽ cài 3 unit systemd từ init.d/systemd/ của bản zapret2"
  else
    n_unit=0
    for u in zapret2.service zapret2-list-update.service zapret2-list-update.timer; do
      src="$ZAPRET_DIR/init.d/systemd/$u"
      [ -f "$src" ] || continue
      install -Dm644 "$src" "/etc/systemd/system/$u" && n_unit=$((n_unit + 1))
    done
    # Cả 3 đều phải có, không phải "≥ 1": thiếu timer thì danh sách phân giải
    # không bao giờ được cập nhật, và sự cố đó lộ ra rất muộn.
    [ "$n_unit" -eq 3 ] \
      || die "cài được $n_unit/3 unit systemd từ $ZAPRET_DIR/init.d/systemd/ — tầng 1 không khởi động được"
    systemctl daemon-reload
    ok "$n_unit unit systemd → /etc/systemd/system/"
  fi


  # ---- config: tạo từ config.default nếu chưa có ----
  # Đặt NGOÀI if/elif/else ở trên để mọi nhánh đều qua, kể cả nhánh
  # "/opt/zapret2 đã có sẵn" — máy đã clone nhưng chưa từng chạy installer thì
  # vẫn thiếu config.
  #
  # Bản đầu không có đoạn này và bước 4 chỉ `die` nếu thiếu. Đo được khi cài
  # trên máy trắng: `git clone` + `make systemd` chỉ sinh `config.default`,
  # KHÔNG sinh `config`; bước 4 chết với "không có /opt/zapret2/config".
  # Nói cách khác: trên máy thật cài được vì config có sẵn từ lần cài tay
  # trước đó — đoạn này CHƯA TỪNG CHẠY cho tới khi làm trắng máy.
  #
  # Cách làm giống hệt zapret2: `cp config.default config`
  # (install_easy.sh dòng 19, biến ZAPRET_CONFIG_DEFAULT → ZAPRET_CONFIG).
  if [ "$DRY" = 1 ]; then
    say "    [dry] sẽ tạo /opt/zapret2/config từ config.default nếu chưa có"
  elif [ ! -f "$ZAPRET_DIR/config" ]; then
    [ -f "$ZAPRET_DIR/config.default" ] \
      || die "không có $ZAPRET_DIR/config.default — bản zapret2 clone về bị thiếu, tầng 1 không dựng được"
    cp "$ZAPRET_DIR/config.default" "$ZAPRET_DIR/config" \
      || die "không tạo được $ZAPRET_DIR/config từ config.default"
    # config là SCRIPT SHELL, không phải keyfile: thiếu dấu = ở là lệnh lạ.
    bash -n "$ZAPRET_DIR/config" || die "$ZAPRET_DIR/config không phải shell script hợp lệ"
    ok "đã tạo $ZAPRET_DIR/config từ config.default"
  else
    say "    $ZAPRET_DIR/config đã có — giữ nguyên"
  fi

# =============================================================================
step "4/8 · CẤU HÌNH zapret2"
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
  # Đếm khoá TỪ TỆP. Bản đầu viết cứng "10 khoá" rồi thêm 2 khoá (DISABLE_IPV6,
  # FLOWOFFLOAD) mà quên sửa con số — thêm xong vẫn in 10 trong khi tệp có 12.
  n_khoa=$(grep -cvE '^[[:space:]]*(#|$)' "$CONF/z2d-zapret2.keys")
  ok "$n_khoa khoá + NFQWS2_OPT · danh sách rỗng · $n_ex dải loại trừ"

  # KHÔNG nuốt lỗi: enable hỏng thì dịch vụ chạy được BÂY GIỜ nhưng mất khi
  # khởi động lại — máy lên mà không có tầng 1, và không có gì báo.
  if ! systemctl enable zapret2 >/dev/null 2>&1; then
    warn "không bật tự khởi động được zapret2 — sau khi reboot, tầng 1 sẽ không chạy"
    warn "thử tay: sudo systemctl enable zapret2"
  fi
  systemctl restart zapret2 || die "zapret2 không lên — journalctl -u zapret2 -n 30"
  for _ in $(seq 1 20); do systemctl is-active --quiet zapret2 && break; sleep 1; done
  systemctl is-active --quiet zapret2 || die "zapret2 vẫn không active"
  ok "zapret2 active"
fi

# =============================================================================
step "5/8 · TẦNG 2 — NextDNS qua DoT"
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

  # ---- Đường mặc định: cáp trước, wifi chỉ là dự phòng ----
  # VÌ SAO CẦN: cả 3 tầng chỉ được đo trên cáp. Lưu lượng lặt qua wifi thì
  # tầng 1 không bao giờ được kích hoạt, và mọi số đo trong README là ứng dụng
  # cho sai đường.
  #
  # CƠ CHẾ CHỈ CÓ MỘT: route-metric. Linux lấy đường có metric NHỎ HƠN.
  #   cáp 100  ·  wifi 50000  →  cáp thắng
  # Khi cáp hỏng, route của cáp biến mất và wifi thành đường mặc định — không
  # cần làm gì thêm. Đã đo: đặt metric cáp lên 100000 (cao hơn wifi) thì
  # `ip route get 1.1.1.1` trả về `dev wlan0`, tức lưu lượng thật sự chuyển.
  #
  # KHÔNG dùng connection.autoconnect-priority ở đây. Tài liệu NM nói rõ nó
  # "only matters if there are more than one candidate profile to select for
  # autoconnect". Cáp và wifi nằm ở HAI THIẾT BỊ KHÁC NHAU nên mỗi cái tự
  # kích hoạt, không tranh chỗ với nhau. Đo: đặt priority cáp 0 → 100 thì bảng
  # định tuyến và danh sách kết nối active y hệt, không đổi gì.
  #
  # Dùng UUID, KHÔNG dùng tên: `nmcli -t` phân tách bằng dấu `:` nên tên profile
  # chứa `:` sẽ vỡ (nmcli escape thành `test\:colon`, tách ra là `test\` và
  # `colon`). UUID không bao giờ chứa `:`. Đã kiểm `nmcli con modify <UUID>` nhận.
  #
  # `-f` ở chế độ terse CHỈ nhận tên trường NGẮN (UUID, TYPE, NAME…). Tên đầy đủ
  # như `connection.uuid` chỉ dùng được với `-g`. Bản đầu viết
  # `-f connection.uuid,connection.type` → nmcli báo lỗi ra stderr, vòng lặp
  # nhận rỗng, script im lặng bỏ qua rồi chỉ cảnh báo "không thấy profile cáp
  # nào" — tức cài xong mà không đặt được gì mà vẫn đi tiếp. Giờ thì chết ngay.
  mapfile -t nm_list < <(nmcli -t -f UUID,TYPE con show 2>/dev/null)
  [ "${#nm_list[@]}" -gt 0 ] \
    || die "nmcli không trả về profile nào — không đặt được đường mặc định.
       Kiểm: nmcli -t -f UUID,TYPE con show"
  n_w=0 n_f=0
  for line in "${nm_list[@]}"; do
    cu=${line%%:*}; ct=${line#*:}
    [ -n "$cu" ] || continue
    case "$ct" in
      802-3-ethernet)
        if nmcli con modify "$cu" ipv4.route-metric 100 ipv6.route-metric 100 2>/dev/null; then
          n_w=$((n_w + 1))
        else
          bad "đặt route-metric cho cáp thất bại ($cu)"
        fi ;;
      802-11-wireless)
        if nmcli con modify "$cu" ipv4.route-metric 50000 ipv6.route-metric 50000 2>/dev/null; then
          n_f=$((n_f + 1))
        else
          bad "đặt route-metric cho wifi thất bại ($cu)"
        fi ;;
    esac
  done
  # Không có cáp thì cảnh báo, không chết: máy chỉ có wifi vẫn dùng được, chỉ là
  # không có gì để "dự phòng".
  if [ "$n_w" -gt 0 ]; then ok "$n_w profile cáp: metric 100 (mặc định)"
  else warn "không thấy profile cáp nào — wifi sẽ là đường mặc định"
  fi
  if [ "$n_f" -gt 0 ]; then ok "$n_f profile wifi: metric 50000 (chỉ dự phòng)"; fi
  # Cần reapply mới có hiệu lực: `nmcli con modify` chỉ ghi vào profile, route
  # đang chạy không đổi. Đo trên máy: modify xong, `ip route` vẫn ra metric cũ.
  for c in "${conns[@]}"; do
    nmcli device reapply "$(nmcli -g connection.interface-name con show "$c" 2>/dev/null)" >/dev/null 2>&1
  done
  ok "route-metric đã nạp lại"

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
step "6/8 · TẦNG 2b — TƯỜNG CHẶN DNS · TẦNG 3 — ufw INPUT deny"
# BỐN THỨ, ĐÚNG THỨ TỰ: rule TRƯỚC, bật tường SAU, kiểm CUỐI CÙNG.
#
#   Trước đây bước 6 thêm rule tường DNS rồi `wall_complete` kiểm, còn bước 7 mới
#   `systemctl enable --now ufw`. Trên máy đã cài, ufw luôn chạy sẵn nên
#   `ufw status` in ra bảng rule và mọi kiểm tra đều đúng. Trên MÁY TRẮNG, ufw
#   chưa từng bật:
#       $ ufw status          →  Status: inactive     (KHÔNG in bảng rule)
#       $ ufw allow out to 45.90.28.0 port 53 proto udp
#                             →  Skipping adding existing rule
#   Lệnh `ufw allow` ghi vào /etc/ufw/user.rules thật (đủ 8 rule — đã kiểm), nhưng
#   `ufw_has` đọc `ufw status` nên thấy 0 rule, rồi `die`:
#       LỖI  tường DNS không đủ 16 rule
#   Tức là kiểm tra SAI, không phải thiếu rule. Không có lỗi này lộ ra trước đây
#   vì máy phát triển luôn có ufw chạy.
#
#   Còn một rủi ro thật trong thứ tự cũ: `ufw --force reset` để
#   DEFAULT_INPUT_POLICY=DROP, mà bản cũ bật ufw ở bước 7 TRƯỚC khi thêm 4 rule
#   KDE Connect ⇒ có một khoảnh thời gian mọi kết nối vào đều bị chặn. Nay tạo
#   hết rule rồi mới bật, nên khoảnh đó không còn.
if [ "$DRY" = 1 ]; then
  say "  [dry] sẽ đảm bảo 20 rule (16 tường DNS + 4 KDE Connect) rồi bật ufw"
  say "  [dry] sẽ đặt policy deny incoming"
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
  # 4 rule KDE Connect đặt trước khi bật tường, để khoảnh thời gian ufw
  # active mà chưa có gì cho vào là bằng không.
  for src in 192.168.0.0/16 fe80::/10; do
    for pr in tcp udp; do
      ufw_has "$src" "1714:1764/$pr" ALLOW IN \
        || ufw allow in from "$src" to any port 1714:1764 proto "$pr" comment 'z2d KDE Connect' >/dev/null
    done
  done

  # Bật tường. Tới đây `ufw status` mới in bảng rule, tức là các phép kiểm
  # dưới đây mới kiểm được thứ thật thay vì kiểm trên bảng rỗng.
  # Bật tường bằng `ufw enable`, KHÔNG bằng `systemctl enable --now ufw`.
  #
  #   Hai cái này KHÔNG giống nhau, và đo được rõ:
  #       $ systemctl enable --now ufw ; systemctl is-active ufw   →  active
  #       $ ufw status                                           →  inactive
  #   Vì `ufw --force disable` đặt cờ `ENABLED=no` trong /etc/ufw/ufw.conf, còn
  #   `systemctl start ufw` chỉ chạy unit nạp iptables — KHÔNG bật lại cờ đó.
  #   Hậu quả: mọi kiểm tra rule đọc `ufw status` đều thấy bảng rỗng, nên
  #   `wall_complete` và `kde_complete` FAIL dù rule đã ghi đúng vào
  #   /etc/ufw/user.rules. Máy cài mới (hoặc máy vừa `ufw disable`) là đúng
  #   trường hợp này — và máy phát triển của tôi luôn có ufw bật sẵn nên không
  #   lộ.
  #
  #   `--force` vì script chạy không tương tác: `ufw enable` khi có phiên SSH
  #   đang mở sẽ HỎI "Command may disrupt existing ssh connections" rồi chờ,
  #   script treo vô hạn. Ở đây không có SSH nên cứ --force, và cảnh báo
  #   ngay sau đó để người dùng biết mình vừa bật tường thật.
  ufw --force enable >/dev/null 2>&1 \
    || die "ufw enable thất bại — tầng 2b+3 không có"
  say "    đã bật tường: mọi kết nối vào bị chặn trừ 4 rule KDE Connect"

  # Đếm KHÔNG đủ — phải kiểm từng rule, cả hai họ.
  wall_complete || die "tường DNS không đủ 16 rule — KHÔNG in HOÀN TẤT"
  kde_complete  || die "rule KDE Connect không đủ 4 — KHÔNG in HOÀN TẤT"
  ok "tường DNS đủ 16/16 rule + 4 rule KDE Connect (kiểm từng rule, cả hai họ)"

  ufw default deny incoming >/dev/null || die "đặt policy deny incoming thất bại"
  pol=$(ufw status verbose 2>/dev/null | sed -n 's/^Default: \([a-z]*\) (incoming).*/\1/p')
  [ "$pol" = deny ] || die "policy đọc lại là '${pol:-?}', không phải deny"
  ok "policy deny incoming"
fi
# =============================================================================
step "7/8 · SYSCTL + 3 lớp phòng thủ"
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
step "8/8 · KIỂM CHỨNG CUỐI"
# --dry DỪNG Ở ĐÂY, nhưng KHÔNG thoát: còn phải chạy tới khối in kết quả
# cuối file để in "XEM XONG" và gợi ý câu lệnh chạy thật.
# Bản đầu viết `return 0 2>/dev/null || exit 0` — ở top-level `return` là lệnh
# không hợp lệ (nên phải chặn lỗi), và `exit 0` chạy được ⇒ --dry im lặng kết
# thúc ở dòng "8/8", không có dòng nào báo đã xem xong. Nhánh `if [ "$DRY" = 1 ]`
# ở cuối file trở thành code chết. Đo: --dry in "XEM XONG" 0 lần.
nbad=0
# BẪY ĐÃ DÍNH Ở chính chỗ này: (a) `grep -c ... || echo 0` in "0" RỒI trả 1
# nên `||` in thêm "0" nữa → "0\n0" và dòng báo LỆCH dù máy đúng;
# (b) lookbehind biến thiên `(?<=X\s*=\s*)` bị PCRE từ chối — dùng \K.
#
#   `printf '%-32s'` của bash LUÔN đệm theo BYTE, kể cả khi LC_CTYPE là UTF-8.
#   Nhãn tiếng Việt có dấu thì 1 ký tự chiếm 2 byte, nên cột bị hụt:
#   đo được "tiến trình nfqws2" = 17 ký tự = 20 byte ⇒ thiếu 3 cột, còn
#   "policy incoming" = 15 ký tự = 15 byte ⇒ đủ 32. Cột lệch tới 3 ký tự ở
#   NGAY BẢN GỐC, không phải do thêm nhãn mới.
#
#   Cách sửa: đặt LC_ALL C.UTF-8 để `${#1}` đếm KÝ TỰ (17 thay vì 20), rồi tự
#   tính số khoảng trắng. Đặt `local` để chỉ có tác dụng trong hàm này — đặt
#   ở cấp script sẽ đổi cả thứ tự `sort`, mà `sort` đang dùng để so hai danh
#   sách ở bước 4 (dù cùng locale thì vẫn so được, nhưng đừng thêm rủi ro).
chk() {
  local LC_ALL=C.UTF-8 sp n
  # Mọi nhãn đều đi qua đây, nên đặt chốt ở chỗ này là đủ — không cần chốt
  # riêng cho từng nhãn, và `--dry` cũng được kiểm vì chk chạy ở cả hai nhánh.
  # (Bản đầu đặt chốt cạnh nhãn route-metric: `--dry` không đi tới đó vì cả
  # khối nằm trong nhánh không-dry, nên thử với nhãn 51 ký tự thì --dry vẫn
  # exit 0 — chốt không có tác dụng gì. Đo được.)
  [ "${#1}" -le 32 ] || { bad "nhãn quá dài: ${#1} ký tự (tối đa 32) — $1"; nbad=$((nbad+1)); return; }
  n=$(( 32 - ${#1} ))
  printf -v sp '%*s' "$n" ''
  if [ "$2" = "$3" ]; then
    printf '  %sOK%s    %s%s %s\n' "$C_G" "$C_0" "$1" "$sp" "$2"
  else
    printf '  %sLỆCH%s  %s%s thực tế=[%s] mong đợi=[%s]\n' "$C_R" "$C_0" "$1" "$sp" "$2" "$3"
    nbad=$((nbad+1))
  fi
}
# Số mục SUY RA TỪ CHÍNH KHỐI NÀY, không viết cứng. Bản đầu ghi "14 mục", thêm
# một mục thành 15 mà quên sửa — cùng kiểu lỗi với "10 khoá" ở bước 4.
#   Khối chạy từ bước KIỂM CHỨNG CUỐI đến hết file; mọi `chk` trong đó đều chạy
#   đúng
#   một lần (route-metric đã được rút về một lệnh chk ở trên).
#   KHỚP THEO NỘI DUNG bước ("KIỂM CHỨNG CUỐI"), không theo số thứ tự. Bản đầu
#   dùng `/^step "9\/[0-9]/` — vỡ ngay khi số bước đổi (gộp 2 bước làm
#   9/9 → 8/8), và hậu quả là n_chk ra 0 chứ không báo lỗi.
n_chk=$(awk '/^step ".*KIỂM CHỨNG CUỐI/{f=1} f' "$SELF" | grep -c '^ *chk ')
if [ "$DRY" = 1 ]; then
  say "    [dry] $n_chk mục kiểm chứng cuối — chạy thật mới kiểm"
else
chk "zapret2 active"      "$(systemctl is-active zapret2)" active
chk "tiến trình nfqws2"   "$(pgrep -c nfqws2 || true)" 1
chk "MODE_FILTER"         "$(grep -oP '^MODE_FILTER=\K.*' "$ZAPRET_DIR/config")" hostlist
chk "danh sách user rỗng" "$(grep -cvE '^\s*(#|$)' "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" || true)" 0
chk "số dải exclude"      "$(grep -cvE '^\s*(#|$)' "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt" || true)" 9
chk "nameserver"          "$(grep -c '^nameserver' /run/systemd/resolve/resolv.conf)" 4

  # DoT: kiểm KẾT NỐI THẬT, không chỉ đọc tệp.
  #
  #   Bản đầu chỉ `grep -c '^DNSOverTLS=yes'` — tức đọc dòng cấu hình. Đó là
  #   câu hỏi "ta đã ghi gì vào tệp", KHÔNG phải "máy có thật sự hỏi ở 853
  #   không". Sơ đồ README lại khẳng định: "Hỏi tên miền ở cổng 853". Nên phải
  #   nhìn kết nối thật của systemd-resolved.
  #
  #   Đo được kiểu mới: `ss -tnp` cho thấy
  #       systemd-resolve  192.168.1.24:40682 → 45.90.28.0:853
  #   tức khẳng định của sơ đồ là đúng.
  #
  #   Có thời gian chờ nên báo "không xác nhận được" thay vì báo đạt, và KHÔNG
  #   chết: báo đạt khi không biết là báo đạt giả — thứ tệ nhất.
  dot_seen=no
  for _try in 1 2 3 4 5 6 7 8 9 10; do
    resolvectl query --cache=no "z2d-$_try.does-not-exist.invalid" >/dev/null 2>&1
    # Thứ tự là quan trọng: `ss` in địa chỉ đích TRƯỚC tên tiến trình
    # (`… 45.90.28.0:853 users:(("systemd-resolve",…))`), nên mẫu
    # `systemd-resolve.*:853` KHÔNG BAO GIỜ khớp — lần đầu viết vậy thì cảnh
    # báo "không xác nhận được" dù kết nối DoT có thật. Tách thành hai lần
    # grep trên cùng một dòng: thứ tự nào cũng khớp.
    if ss -tnp 2>/dev/null | grep systemd-resolve | grep -q ':853'; then dot_seen=yes; break; fi
    sleep 0.3
  done
  if [ "$dot_seen" = yes ]; then
    ok "DoT thật — systemd-resolved đang nối cổng 853"
  else
    warn "KHÔNG xác nhận được kết nối DoT ở cổng 853 trong ~3 giây"
    warn "tệp cấu hình vẫn có DNSOverTLS=$(grep -c '^DNSOverTLS=yes' /etc/systemd/resolved.conf)"
    warn "kiểm tay:  ss -tnp | grep systemd-resolve"
    warn "          (không phải lỗi chắc chắn — có thể chỉ là chưa có truy vấn nào)"
  fi

  # Policy INPUT: đọc KERNEL, không đọc lời khai của ufw.
  #
  #   Bản đầu hỏi `ufw status verbose` — đó là ufw tự báo. Nhưng ufw có thể
  #   "active" mà ruleset chưa nạp, hoặc nạp thiếu. Chỗ kiểm được là
  #   `nft list ruleset`: kernel tự nói `hook input ... policy drop`.
  #   Đo được: `hook input priority filter; policy drop;` cho cả IPv4 và IPv6.
  _pol=$(nft list ruleset 2>/dev/null | awk '
    /^table /  { f = ($2 == "ip6") ? "v6" : (($2 == "ip") ? "v4" : "") }
    /hook input/ && /policy drop/ { if (f != "") c[f]++ }
    END { printf "%d/%d", c["v4"]+0, c["v6"]+0 }')
  chk "policy INPUT: kernel v4/v6" "$_pol" "1/1"

chk "tường DNS 16 rule"   "$(wall_complete && echo yes || echo no)" yes
chk "KDE Connect 4 rule"  "$(kde_complete && echo yes || echo no)" yes
chk "policy incoming"     "$(ufw status verbose 2>/dev/null | sed -n 's/^Default: \([a-z]*\) (incoming).*/\1/p')" deny
chk "ufw active"          "$(systemctl is-active ufw)" active
chk "IPT_SYSCTL"          "$(grep -oP '(?<=^IPT_SYSCTL=).*' /etc/default/ufw)" "$Z2D_SYSCTL"
chk "symlink boot sysctl" "$([ -L /etc/sysctl.d/60-z2d-hardening.conf ] && echo co || echo khong)" co
chk "DNS còn hỏi được"    "$(resolvectl query --cache=no github.com >/dev/null 2>&1 && echo ok || echo loi)" ok
# route-metric: buoc 5 vua dat, phai kiem lai. Cung loai hong "da dat nhung
# dat sai" — im lang trong khi may sai thi moi nguy hiem.
n_rm_bad=0 n_rm_seen=0
while IFS=: read -r cu ct; do
  [ -n "$cu" ] || continue
  case "$ct" in
    802-3-ethernet)  m=$(nmcli -g ipv4.route-metric con show "$cu" 2>/dev/null)
                     n_rm_seen=$((n_rm_seen + 1))
                     [ "$m" = 100 ]   || n_rm_bad=$((n_rm_bad + 1)) ;;
    802-11-wireless) m=$(nmcli -g ipv4.route-metric con show "$cu" 2>/dev/null)
                     n_rm_seen=$((n_rm_seen + 1))
                     [ "$m" = 50000 ] || n_rm_bad=$((n_rm_bad + 1)) ;;
  esac
done < <(nmcli -t -f UUID,TYPE con show 2>/dev/null)
# Gom vào MỘT lệnh chk chứ không viết if/else quanh chk: hai nhánh loại trừ
# nhau khiến số dòng `chk` trong khối này nhiều hơn số mục thật sự chạy, và
# bộ đếm bên dưới sẽ báo sai. Rút nhãn/giá trị ra biến, gọi chk đúng một lần.
if [ "$n_rm_seen" -eq 0 ]; then
  n_rm_lbl="route-metric (0 profile)"
  n_rm_val="không đọc được profile nào"; n_rm_exp="cần thấy cáp và wifi"
else
  n_rm_lbl="route-metric cáp 100 · wifi 50k"
  n_rm_val="$n_rm_bad"; n_rm_exp=0
fi
chk "$n_rm_lbl" "$n_rm_val" "$n_rm_exp"
fi
say ""
[ "$nbad" -eq 0 ] || die "$nbad mục LỆCH — không in HOÀN TẤT"

# =============================================================================
# Đến đây chắc chắn là CÀI (đường gỡ đã thoát ở trên). Bản đầu còn nhánh
# `ACTION = uninstall` in "Xong." ở đây — nhưng nhánh đó không bao giờ chạy
# được, vì uninstall thoát sớm.
say ""
say "──────────────────────────────────────────────"
# --dry KHÔNG BAO GIỜ in "HOÀN TẤT": bản đầu in "HOÀN TẤT" ở chế độ dry,
# tức "thành công giả" — đọc chữ đó là tin đã xong.
if [ "$DRY" = 1 ]; then
  ok "XEM XONG — chưa thay đổi gì cả"
  say "  chạy thật         : sudo bash install.sh --nd-id $ND_ID"
else
  ok "HOÀN TẤT — 3 tầng đã dựng và đã kiểm chứng"
  say "  backup (duy nhất) : $BACKUP"
  say "  kiểm lại          : sudo bash test/t1-config.sh"
  say "  gỡ ra             : sudo bash install.sh --uninstall"
fi
say "──────────────────────────────────────────────"
exit 0
