#!/usr/bin/env bash
# update.sh — kiểm bản zapret2 mới trên GitHub, và cài nếu có.
#
#   sudo bash update.sh                 # kiểm, hỏi, rồi cài nếu có bản mới
#   sudo bash update.sh --check-only    # chỉ báo, không đụng gì
#   sudo bash update.sh --from master   # cài từ branch thay vì release
#   sudo bash update.sh -y              # không hỏi (cho script/cron)
#
# NGUYÊN TẮC: /opt/zapret2/config VÀ HAI DANH SÁCH USER KHÔNG BAO GIỜ BỊ MẤT.
#
#   Ba file đó KHÔNG nằm trong git (đều bị .gitignore loại), nên git coi chúng
#   là file rác. Đó là lý do `git clean -xdf` — thứ người ta hay chạy để "dọn
#   cho sạch" — sẽ XOÁ MẤT CẢ BA. Script này không dùng lệnh đó, và còn backup
#   + đối chiếu SHA256 trước và sau mọi bước.
#
#   Ba file đó là toàn bộ cấu hình của bạn. Máy này MODE_FILTER=hostlist và
#   không có GETLIST, nên zapret2 không tải danh sách nào từ đâu cả — danh sách
#   duy nhất nó dùng là hai file user.
#
# KHÁC GÌ install.sh:
#   install.sh cài MỚI nên `rm -rf /opt/zapret2` rồi clone lại. Update thì không
#   được làm vậy: `rm -rf` sẽ xoá luôn ba file kia.
#   install.sh ghim ZAPRET_TAG=v1.0.5.2. Script này hỏi GitHub xem release mới
#   nhất là gì rồi cài đúng tag đó — cùng cách cài, chỉ là con số lấy động.

set -uo pipefail

# Cho phép ghi đè qua môi trường để chạy thử trong sandbox mà không đụng
# /opt/zapret2 thật. Không đặt thì dùng đường dẫn thật.
ZAPRET_DIR="${ZAPRET_DIR:-/opt/zapret2}"
ZAPRET_REPO="${ZAPRET_REPO:-https://github.com/bol-van/zapret2}"
BACKUP_PARENT="${BACKUP_PARENT:-/var/backups/zapret2-dotfile}"
UNITS="zapret2.service zapret2-list-update.service zapret2-list-update.timer"

# Ba file phải giữ. Đường dẫn tương đối so với $ZAPRET_DIR.
KEEP_FILES="config ipset/zapret-hosts-user.txt ipset/zapret-hosts-user-exclude.txt"

# Binary đã build. `make systemd` chạy `clean` TRƯỚC ⇒ build hỏng là mất binary,
# và zapret2 không khởi động được. Backup để rollback không phải build lại.
KEEP_BIN="binaries"

DRY=0; ASSUME_YES=0; FROM=""; KEEP_BACKUPS=5

# git chạy trong /opt/zapret2 thuộc root. Nếu script bị gọi bởi user (không phải
# sudo) thì git chết với "dubious ownership". -c safe.directory cho phép đọc
# trạng thái mà không cần sửa ~/.gitconfig của người dùng.
G() { git -c safe.directory="$ZAPRET_DIR" "$@"; }

if [ -t 2 ]; then C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else C_R=""; C_G=""; C_Y=""; C_B=""; C_0=""; fi
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s▸ %s%s\n' "$C_B" "$*" "$C_0"; }
ok()   { printf '  %sOK%s    %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '  %sCẢNH BÁO%s %s\n' "$C_Y" "$C_0" "$*"; }
bad()  { printf '  %sLỖI%s    %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { bad "$*"; exit 1; }

# ------------------------------------------------------------------ tham số
usage() {
  cat <<'EOF'
update.sh — cập nhật zapret2 (nfqws2), giữ nguyên config

  --check-only     chỉ báo có bản mới không, không cài
  --from REF       cài từ REF thay vì release mới nhất (vd: master, v1.0.6)
  --keep-backups N giữ N bản backup gần nhất (mặc định 5)
  -y, --yes        không hỏi
  -h, --help       in này
EOF
}
while [ $# -gt 0 ]; do
  case "$1" in
    --check-only)   DRY=1 ;;
    --from)         [ $# -ge 2 ] || die "--from cần một REF"; FROM="$2"; shift ;;
    --from=*)       FROM="${1#--from=}" ;;
    --keep-backups) [ $# -ge 2 ] || die "--keep-backups cần một số"; KEEP_BACKUPS="$2"; shift ;;
    -y|--yes)       ASSUME_YES=1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "tham số lạ: $1 (xem --help)" ;;
  esac
  shift
done

# Chốt tham số ngay sau khi phân tích: số thì phải là số THẬT. `--keep-backups abc`
# để nguyên thì `[ abc -gt 0 ]` in "integer expression expected" rồi trả về
# false ⇒ nhánh dọn backup bị bỏ qua lặng lẽ, và người dùng tưởng đã đặt được.
case "$KEEP_BACKUPS" in
  ''|*[!0-9]*) die "--keep-backups cần một số nguyên không âm, nhận được '$KEEP_BACKUPS'" ;;
esac

# ------------------------------------------------------------------ điều kiện
step "1/5 · KIỂM TRA"
[ "$(id -u)" = 0 ] || die "phải chạy bằng sudo"
[ -d "$ZAPRET_DIR" ] || die "không có $ZAPRET_DIR — chưa cài zapret2. Chạy: sudo bash install.sh --nd-id <ID>"
[ -d "$ZAPRET_DIR/.git" ] || die "$ZAPRET_DIR không phải bản clone git — không update được"

for c in git make gcc; do
  command -v "$c" >/dev/null || die "thiếu lệnh: $c"
done
ok "đủ lệnh cần thiết"

# Không có curl thì dùng git ls-remote thay. Không có gì thì không hỏi nổi.
HAVE_CURL=0; command -v curl >/dev/null && HAVE_CURL=1
ok "cách hỏi GitHub: $([ "$HAVE_CURL" = 1 ] && echo 'API releases/latest' || echo 'git ls-remote (curl không có)')"

# Cấu hình phải tồn tại TRƯỚC khi ta đụng gì. Không có thì "giữ nguyên" là vô nghĩa.
n_missing=0
for f in $KEEP_FILES; do
  [ -f "$ZAPRET_DIR/$f" ] || { bad "không có $ZAPRET_DIR/$f"; n_missing=$((n_missing+1)); }
done
[ "$n_missing" -eq 0 ] \
  || die "$n_missing/3 file cấu hình không tồn tại — không có gì để giữ, dừng lại đây"
ok "đủ 3 file cấu hình để giữ"

# Xác định đang chạy phiên bản nào. PHẢI dùng commit SHA làm chuẩn, không dùng
# tag — vì sau khi ai đó chạy `--from master`, HEAD nằm trên commit KHÔNG có tag
# nào, `git describe --tags` trả rc=128 và bản đầu chết ngay ở đây.
#
# Đúng tình huống thật: master của zapret2 đi trước release v1.0.5.2 tới hai
# tuần. Nghĩa là "cài từ master một lần" rồi chạy "update.sh lần sau" là tự khoá
# chính mình ra khỏi công cụ — thất bại tệ nhất vì âm thầm.
#
#   CUR_COMMIT : luôn có, dùng để QUAY LUI. SHA luôn checkout được, kể cả khi
#                tag đã bị xoá khỏi remote.
#   CUR_TAG    : để HIỂN THỊ và SO SÁNH. Có thể rỗng — xử lý riêng, không chết.
CUR_COMMIT=$(G rev-parse HEAD 2>/dev/null)
[ -n "$CUR_COMMIT" ] || die "không đọc được HEAD — $ZAPRET_DIR có vẻ không phải repo git"

# Tệp do chính script này ghi, nằm NGOÀI /opt/zapret2 để git không đụng tới và
# để một `git clean` trong tương lai không xoá mất. Ưu tiên hơn `git describe`
# vì nó ghi đúng thứ ĐÃ CÀI, kể cả khi sau đó ai đó đổi branch.
STAMP_FILE="$BACKUP_PARENT/INSTALLED"
CUR_TAG=""
if [ -r "$STAMP_FILE" ]; then
  CUR_TAG=$(sed -n 's/^TAG=//p' "$STAMP_FILE" | head -1)
  st_c=$(sed -n 's/^COMMIT=//p' "$STAMP_FILE" | head -1)
  # KHÔNG tin tay tệp stamp. Lý do: rollback là LƯỚI AN TOÀN duy nhất của cả
  # script, mà nó lại dùng đúng giá trị này. Stamp bị sửa tay, bị cắt ngắn, hoặc
  # còn lại từ repo khác ⇒ `git checkout <rác>` thất bại lặng lẽ, và lúc đó
  # người dùng mất cả zapret2 lẫn đường lùi.
  #
  # Đo được cả hai kiểu hỏng:
  #   COMMIT=master           → rev-parse trả nguyên chuỗi "master", không phải
  #                             SHA; checkout bằng nó không ra cái gì
  #   COMMIT=000…0 (40 số 0)  → đúng dạng SHA nhưng không có object, cat-file
  #                             từ chối
  if [ -n "$st_c" ] && printf '%s' "$st_c" | grep -qP '^[0-9a-f]{7,40}$' \
     && G cat-file -e "${st_c}^{commit}" 2>/dev/null; then
    CUR_COMMIT="$st_c"
  elif [ -n "$st_c" ]; then
    warn "tệp stamp có COMMIT không hợp lệ ('$st_c') — bỏ qua, dùng HEAD thật"
  fi
fi
[ -n "$CUR_TAG" ] || CUR_TAG=$(G describe --tags --abbrev=0 2>/dev/null)

ok "đang chạy: ${CUR_TAG:-<không rõ phiên bản>} (${CUR_COMMIT:0:7})"
if [ -z "$CUR_TAG" ]; then
  warn "HEAD không nằm trên tag nào — có lẽ lần trước cài từ branch"
  warn "không tự kết luận có bản mới hay không; sẽ hỏi bạn"
fi

# ------------------------------------------------------------------ 2 · hỏi GitHub
step "2/5 · HỎI BẢN MỚI NHẤT"

# Ưu tiên releases/latest: GitHub tự loại draft và prerelease, trả đúng "bản
# release mới nhất" — đúng thứ đề bài hỏi.
#   `tag_name` xuất hiện nhiều lần trong JSON (mỗi asset url, mỗi field khác),
#   nên lấy LẦN ĐẦU chứ không lấy hết rồi nhét vào biến.
LATEST=""
if [ "$HAVE_CURL" = 1 ]; then
  body=$(curl -fsS --max-time 20 -H 'Accept: application/vnd.github+json' \
         "https://api.github.com/repos/bol-van/zapret2/releases/latest" 2>/dev/null)
  if [ -n "$body" ]; then
    LATEST=$(printf '%s' "$body" \
      | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1)
  else
    warn "gọi API thất bại — rơi xuống git ls-remote"
  fi
fi
if [ -z "$LATEST" ]; then
  # ls-remote không cần API nên không bị chặn rate limit.
  LATEST=$(G ls-remote --tags --refs "$ZAPRET_REPO" 2>/dev/null \
            | grep -oP 'refs/tags/\Kv[0-9][0-9.]*$' | sort -V | tail -1)
fi
[ -n "$LATEST" ] || die "không lấy được tag mới nhất từ GitHub — kiểm mạng rồi thử lại"
ok "release mới nhất trên GitHub: $LATEST"

TARGET="$LATEST"
EXPLICIT=0
if [ -n "$FROM" ]; then
  TARGET="$FROM"; EXPLICIT=1
  warn "bỏ qua release, cài từ '$TARGET' theo yêu cầu"
  case "$TARGET" in
    v[0-9]*) warn "'$TARGET' là tag chưa chắc đã phát hành — cài vào máy thật thì tự chịu rủi ro" ;;
    *)       warn "'$TARGET' KHÔNG phải tag phiên bản ⇒ không có gì để so sánh, cài đúng theo yêu cầu" ;;
  esac
fi

# Chỉ so phiên bản khi TARGET lấy từ release. Khi --from được dùng, người
# dùng ĐÃ quyết rồi; so sánh lúc đó chỉ gây hại:
#
#   `sort -V` xếp "master" TRƯỚC "v1.0.5.2", nên tail -1 ra v1.0.5.2 — tức bản
#   đang chạy. Bản đầu báo "không mới hơn, dừng" rồi thoát 0, tức `--from
#   master` im lặng không làm gì. Đó là thất bại tệ nhất: người dùng đã yêu
#   cầu rõ, ta trả lời bằng im lặng. Mọi ref không phải số (master, HEAD,
#   origin/master) đều rơi vào bẫy này.
if [ "$EXPLICIT" = 0 ]; then
  # Không rõ phiên bản đang chạy thì KHÔNG so được. Chết ở đây thì tệ; coi
  # như "có bản mới" rồi hỏi thì cũng sai. Nên: in ra sự thật, rồi để prompt
  # bên dưới quyết — con người có đủ thông tin để chọn.
  if [ -z "$CUR_TAG" ]; then
    warn "không so được phiên bản (bản đang chạy không nằm trên tag nào) — GitHub có $TARGET"
    warn "nếu $TARGET là release, cài nó sẽ ĐÁNH LẤN đè code bạn đang chạy"
  elif [ "$(printf '%s\n%s\n' "$TARGET" "$CUR_TAG" | sort -V | tail -1)" = "$CUR_TAG" ] \
       && [ "$TARGET" != "$CUR_TAG" ]; then
    ok "$TARGET không mới hơn $CUR_TAG đang chạy — không có gì để làm"
    exit 0
  elif [ "$TARGET" = "$CUR_TAG" ]; then
    ok "đã là bản mới nhất ($CUR_TAG) — không có gì để làm"
    exit 0
  fi
fi

# ---- hỏi xác nhận ----
# Việc này dừng zapret2, checkout sang ref khác, rồi build lại. Người dùng phải
# có cơ hội nói không. `-y` bỏ qua hẳn; không có stdin (cron, pipe) thì coi như
# CHƯA đồng ý — cài im lặng tệ hơn là hỏi.
if [ "$ASSUME_YES" = 0 ]; then
  say ""
  say "    SẼ CÀI: ${CUR_TAG:-<không rõ phiên bản>} → $TARGET"
  say "    giữ nguyên: $KEEP_FILES"
  say "    zapret2 dừng trong lúc cài (vài chút)"
  if [ -t 0 ]; then
    printf '    %sTiếp tục? [y/N] ' "$C_B"
    read -r ans
    case "$ans" in
      [yY]|[yY][eE][sS]) ;;
      *) say "    đã hủy — không đụng gì"; exit 0 ;;
    esac
  else
    die "không có stdin để hỏi mà không có -y — thêm -y nếu chắc chắn muốn cài"
  fi
fi

# Ba file kia nằm trong .gitignore nên git không hề biết tới. Ghi lại để sau
# đối chiếu, và để báo ngay nếu tệp nào vốn đã KHÔNG tồn tại (không phải lỗi
# update, nhưng phải nói rõ để không tưởng update xoá mất).
MANIFEST=""
for f in $KEEP_FILES; do
  MANIFEST="$MANIFEST$(sha256sum "$ZAPRET_DIR/$f" 2>/dev/null | awk '{print $1}')  $f"$'\n'
done
say ""
say "  Ba file sẽ được giữ (đều nằm ngoài git — script này backup riêng):"
printf '%s' "$MANIFEST" | sed 's/^/    /'

if [ "$DRY" = 1 ]; then
  step "KẾT QUẢ · --check-only"
  ok "có bản mới: ${CUR_TAG:-<không rõ phiên bản>} → $TARGET"
  say "    chạy lại không kèm --check-only để cài"
  say "    config và hai danh sách user được giữ nguyên"
  exit 0
fi

# ------------------------------------------------------------------ 3 · backup
step "3/5 · BACKUP TRƯỚC KHI ĐỤNG"

STAMP=$(date +%Y%m%d-%H%M%S)
BK="$BACKUP_PARENT/update-$STAMP"
mkdir -p "$BK" || die "không tạo được $BK"
chmod 700 "$BACKUP_PARENT" 2>/dev/null

n=0
for f in $KEEP_FILES; do
  mkdir -p "$BK/$(dirname "$f")"
  cp -a "$ZAPRET_DIR/$f" "$BK/$f" || die "backup $f thất bại — dừng, không đụng gì"
  n=$((n+1))
done
printf '%s' "$MANIFEST" > "$BK/SHA256SUMS"
printf '%s\n' "$CUR_TAG" > "$BK/PREV_TAG"

# Binary: `make systemd` chạy `clean` TRƯỚC khi build. Build hỏng là mất sạch
# nfqws2, zapret2 không khởi động được, và phải build lại từ đầu để cứu.
if [ -d "$ZAPRET_DIR/$KEEP_BIN" ]; then
  cp -a "$ZAPRET_DIR/$KEEP_BIN" "$BK/binaries" || die "backup binary thất bại"
  ok "backup binary (để rollback không phải build lại)"
fi
ok "backup $n/3 file cấu hình → $BK"

# Dọn backup cũ. Chỉ xoá thư mục tên update-*, không đụng thư mục install của
# install.sh (chúng cùng nằm trong $BACKUP_PARENT).
if [ "$KEEP_BACKUPS" -gt 0 ]; then
  mapfile -t old_bk < <(find "$BACKUP_PARENT" -maxdepth 1 -type d -name 'update-*' \
                          | sort -r | tail -n "+$((KEEP_BACKUPS+1))")
  for d in "${old_bk[@]}"; do rm -rf "$d"; done
  [ "${#old_bk[@]}" -eq 0 ] || ok "xoá ${#old_bk[@]} backup cũ, giữ $KEEP_BACKUPS bản gần nhất"
fi

# ------------------------------------------------------------------ 4 · cài
step "4/5 · CÀI $TARGET"

# Rollback = quay lại tag cũ, đặt lại ba file, build lại, khởi động.
# Mọi đường thoát sau khi bắt đầu sửa cây đều phải qua đây.
rollback() {
  bad "đang quay lui về ${CUR_TAG:+$CUR_TAG }${CUR_COMMIT:0:7}"
  systemctl stop zapret2 >/dev/null 2>&1
  # Quay lại bằng SHA, KHÔNG bằng tên tag. Khi bản đang chạy là branch thì
  # CUR_TAG rỗng; khi tag đã bị xoá khỏi remote thì tên tag không còn resolve.
  # SHA luôn còn đó và luôn checkout được.
  G checkout -f "$CUR_COMMIT" >/dev/null 2>&1
  for f in $KEEP_FILES; do [ -f "$BK/$f" ] && cp -a "$BK/$f" "$ZAPRET_DIR/$f"; done
  if [ -d "$BK/binaries" ]; then
    rm -rf "$ZAPRET_DIR/$KEEP_BIN"
    cp -a "$BK/binaries" "$ZAPRET_DIR/$KEEP_BIN"
  fi
  CFLAGS="-march=native" OPTIMIZE=-O2 make -C "$ZAPRET_DIR" systemd >/dev/null 2>&1
  for u in $UNITS; do
    [ -f "$ZAPRET_DIR/init.d/systemd/$u" ] && \
      install -Dm644 "$ZAPRET_DIR/init.d/systemd/$u" "/etc/systemd/system/$u"
  done
  systemctl daemon-reload
  systemctl enable --now zapret2 >/dev/null 2>&1
  if [ "$(systemctl is-active zapret2 2>/dev/null)" = active ]; then
    ok "đã quay lui xong, zapret2 chạy lại trên ${CUR_TAG:+$CUR_TAG }${CUR_COMMIT:0:7}"
  else
    bad "quay lui xong nhưng zapret2 KHÔNG lên — xem: journalctl -u zapret2 -n 50"
  fi
}

# Ctrl-C giữa đường sẽ để zapret2 dừng với cây ở nửa chừng. Bẫy này đã được
# dính lần trước ("Ctrl-C im lặng") nên đặt từ đầu.
INTERRUPTED=0
trap 'INTERRUPTED=1; warn "bị gián đoạn — đang quay lui"; rollback; exit 130' INT TERM

systemctl stop zapret2 >/dev/null 2>&1
ok "đã dừng zapret2"

# Bản clone là `--depth 1` với refspec CHỈ có một tag:
#   +refs/tags/v1.0.5.2:refs/tags/v1.0.5.2
# Nên `git fetch --tags` hay `git fetch origin` đều chỉ lấy lại tag cũ. Phải
# chỉ định đích thì nó mới về. Đây là chỗ dễ bỏ sót nhất — lệnh fetch "thành
# công" nhưng không có gì mới.
#
# `fetch ... tag X` chỉ nhận TAG. `--from master` là branch, nên phải có đường
# thứ hai: thử tag trước, không được thì thử branch/commit.
fetched=0
G fetch --depth 1 origin tag "$TARGET" >/dev/null 2>&1 && fetched=1
if [ "$fetched" = 0 ]; then
  G fetch --depth 1 origin "$TARGET" >/dev/null 2>&1 && fetched=1
fi
[ "$fetched" = 1 ] || { rollback; die "không fetch được '$TARGET' — mạng, hoặc ref không tồn tại"; }

# Tag thì có ref cục bộ để checkout theo tên; branch/commit thì chỉ có FETCH_HEAD.
if G rev-parse --verify --quiet "refs/tags/$TARGET" >/dev/null 2>&1; then
  G checkout -f "refs/tags/$TARGET" >/dev/null 2>&1 \
    || { rollback; die "checkout $TARGET thất bại"; }
else
  G checkout -f FETCH_HEAD >/dev/null 2>&1 \
    || { rollback; die "checkout FETCH_HEAD thất bại"; }
fi
ok "đã checkout $TARGET ($(G rev-parse --short HEAD))"

# Cài gói build trước, y như install.sh: nfq2/Makefile dùng thư viện ở cả lúc
# biên dịch lẫn liên kết, thiếu gói thì make chết ngay.
NEED=""
for p in make gcc pkgconf zlib libnetfilter_queue libnfnetlink libmnl luajit; do
  pacman -Qq "$p" >/dev/null 2>&1 || NEED="$NEED $p"
done
[ -z "$NEED" ] || {
  say "    cài gói build:$NEED"
  pacman -S --needed --noconfirm $NEED >/dev/null 2>&1 \
    || { rollback; die "cài gói build thất bại:$NEED"; }
}

if ! CFLAGS="-march=native" OPTIMIZE=-O2 make -C "$ZAPRET_DIR" systemd >/tmp/z2d-build.log 2>&1; then
  tail -20 /tmp/z2d-build.log >&2
  rollback; die "build thất bại — xem /tmp/z2d-build.log"
fi
ok "đã build (log: /tmp/z2d-build.log)"

# `make systemd` tự đặt unit ở /usr/lib/systemd/system/. Cài đè ở /etc để
# /etc thắng — đúng như install.sh làm, và đúng thứ tự: /etc được đọc trước.
n_unit=0
for u in $UNITS; do
  [ -f "$ZAPRET_DIR/init.d/systemd/$u" ] || continue
  install -Dm644 "$ZAPRET_DIR/init.d/systemd/$u" "/etc/systemd/system/$u" && n_unit=$((n_unit+1))
done
[ "$n_unit" -eq 3 ] || { rollback; die "chỉ cài được $n_unit/3 unit systemd"; }
systemctl daemon-reload
ok "$n_unit unit systemd → /etc/systemd/system/"

# ------------------------------------------------------------------ 5 · giữ config
step "5/5 · ĐỐI CHIẾU CONFIG"

# KHÔNG tin rằng git giữ được. Ba file nằm ngoài git nên checkout không đụng,
# nhưng "không đụng" là suy đoán, còn SHA256 là đo. Đối chiếu từng file; lệch
# thì đặt lại từ backup và báo.
n_same=0; n_restored=0
while read -r want file; do
  [ -n "$want" ] || continue
  got=$(sha256sum "$ZAPRET_DIR/$file" 2>/dev/null | awk '{print $1}')
  if [ "$got" = "$want" ]; then
    ok "$file — nguyên vẹn"
    n_same=$((n_same+1))
  else
    warn "$file BỊ ĐỔI — đặt lại từ backup"
    cp -a "$BK/$file" "$ZAPRET_DIR/$file" || die "không đặt lại được $file từ backup!"
    got2=$(sha256sum "$ZAPRET_DIR/$file" 2>/dev/null | awk '{print $1}')
    [ "$got2" = "$want" ] || die "đặt lại $file xong vẫn khác — backup có vấn đề"
    n_restored=$((n_restored+1))
  fi
done <<< "$MANIFEST"

# config là SCRIPT SHELL. Cú pháp hỏng thì zapret2 không lên, và nguyên nhân sẽ
# nằm ở bản mới chứ không phải ở config — dễ chẩn đoán nhầm.
bash -n "$ZAPRET_DIR/config" || { rollback; die "$ZAPRET_DIR/config không còn là shell hợp lệ"; }
ok "config vẫn là shell script hợp lệ"

if [ "$n_restored" -gt 0 ]; then
  warn "đã khôi phục $n_restored/3 file — xem $BK/SHA256SUMS để đối chiếu"
else
  ok "cả 3 file cấu hình nguyên vẹn, không cần khôi phục"
fi

trap - INT TERM
systemctl enable --now zapret2 >/dev/null 2>&1 || true
sleep 1

STATE=$(systemctl is-active zapret2 2>/dev/null)
if [ "$STATE" != active ]; then
  journalctl -u zapret2 -n 30 --no-pager >&2 2>/dev/null
  rollback
  die "zapret2 không lên sau khi cài $TARGET — thường là config dùng cờ mà bản mới bỏ"
fi
ok "zapret2 active"

NPROC=$(pgrep -c nfqws2 2>/dev/null || echo 0)
[ "$NPROC" -ge 1 ] || { rollback; die "zapret2 active nhưng không có tiến trình nfqws2"; }
ok "tiến trình nfqws2: $NPROC"

nft list table inet zapret2 >/dev/null 2>&1 \
  && ok "bảng nft inet zapret2 đã nạp" \
  || warn "không thấy bảng nft inet zapret2 — kiểm: nft list tables | grep zapret2"

printf '%s\n' "$TARGET" > "$BK/NEW_TAG"

# Ghi phiên bản vừa cài. Nhờ tệp này, lần update sau biết chính xác đang chạy
# gì — kể cả khi đó là branch và `git describe` không nói được.
NEW_COMMIT=$(G rev-parse HEAD 2>/dev/null)
mkdir -p "$BACKUP_PARENT" 2>/dev/null
{
  printf 'TAG=%s\n' "$TARGET"
  printf 'COMMIT=%s\n' "${NEW_COMMIT:-$CUR_COMMIT}"
  printf 'WHEN=%s\n' "$(date -Is)"
} > "$STAMP_FILE"
ok "ghi phiên bản đã cài vào $STAMP_FILE"

step "HOÀN TẤT"
ok "${CUR_TAG:-<không rõ>} → $TARGET"
ok "config + 2 danh sách user: nguyên vẹn ($n_same/3 không đổi${n_restored:+, $n_restored khôi phục})"
say "    backup trước khi cài: $BK"
say "    quay lui: cp -a $BK/config $ZAPRET_DIR/config rồi chạy lại script với --from $CUR_COMMIT"

# Dọn backup cũ SAU CÙNG, lúc này đã thành công, để lần hỏng giữa đường
# không xoá mất đường lùi.
if [ "$KEEP_BACKUPS" -gt 0 ]; then
  mapfile -t old_bk < <(find "$BACKUP_PARENT" -maxdepth 1 -type d -name 'update-*' \
                          | sort -r | tail -n "+$((KEEP_BACKUPS+1))")
  for d in "${old_bk[@]}"; do rm -rf "$d"; done
fi
exit 0