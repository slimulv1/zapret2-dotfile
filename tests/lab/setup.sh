#!/usr/bin/env bash
# Dựng / gỡ lab DPI giả lập. Mọi thay đổi đều đảo ngược được bằng `down`.
#
#   Sơ đồ:
#       host ──v2dpi0 (10.99.0.1/30)── netns z2d_dpi (10.99.0.2/30) ── DPI:443
#         └─ route 198.51.100.1/32 → v2dpi0   (địa chỉ TEST-NET-2, không ai dùng)
#
#   Vì sao đi qua netns mà desync vẫn có tác dụng: bảng `inet zapret2` móc ở
#   hook `output` của HOST, không giới hạn theo thiết bị ⇒ gói đi ra veth vẫn
#   bị nfqws2 cắt đoạn đầu. Đã kiểm: `nft list table inet zapret2` cho thấy
#   chain `predefrag_nfqws` ở `hook output`.
set -uo pipefail

NS=z2d_dpi
VETH=v2dpi0
PEER=vethdpi0
HOST_IP=10.99.0.1/30
NS_IP=10.99.0.2/30
FAKE_IP=198.51.100.1        # đóng vai github.com (SNI bị chặn)
FAKE2=198.51.100.2       # đóng vai kernel.org (SNI được phép)
LOG=/tmp/z2d-qa/dpi.log
STATE=/tmp/z2d-qa/lab.state
PIDFILE=/tmp/z2d-qa/dpi.pid

have_root(){ [ "$(id -u)" -eq 0 ]; }

up(){
  have_root || { echo "  cần chạy bằng root"; return 1; }
  down >/dev/null 2>&1 || true
  mkdir -p /tmp/z2d-qa

  sysctl -n net.ipv4.ip_forward > "$STATE.orig"
  sysctl -q -w net.ipv4.ip_forward=1

  ip netns add "$NS"
  ip link add "$VETH" type veth peer name "$PEER"
  ip link set "$PEER" netns "$NS"
  ip addr add "$HOST_IP" dev "$VETH"
  ip link set "$VETH" up
  ip -n "$NS" addr add "$NS_IP" dev "$PEER"
  ip -n "$NS" link set lo up
  ip -n "$NS" link set "$PEER" up
  # netns phải SỞ HỮU địa chỉ đích, nếu không nó không trả lời ARP và gói của
  # host rơi vào hư không (đo được: DPI không nhận kết nối nào dù host đã có
  # route `198.51.100.1/32 dev v2dpi0`).
  #
  # Gán `/24` chứ KHÔNG gán `/32`: một địa chỉ `/32` trên veth bị kernel coi là
  # LOCAL, và nó sẽ chọn địa chỉ đó làm NGUỒN gói đi ra — mà 198.51.100.x không
  # tồn tại ngoài đời, nên không ai trả lời. Đo được: `ip -n z2d_dpi route get
  # 1.1.1.1` ra `src 198.51.100.1`, và mọi kết nối từ netns đều timeout.
  # `/24` vừa cho ARP hoạt động, vừa ép nguồn về 10.99.0.2 bằng `src`.
  ip -n "$NS" addr add "$FAKE_IP"/24 dev "$PEER"
  # Địa chỉ thứ HAI phải được gán thật, nếu không netns không trả lời ARP cho
  # nó ⇒ curl báo "No route to host" và DPI không nhận kết nối nào. Đo được:
  # route hai phía đều đúng, nhưng chỉ 198.51.100.1 có trả lời ARP.
  ip -n "$NS" addr add "$FAKE2"/32 dev "$PEER"
  ip -n "$NS" route replace default via 10.99.0.1 dev "$PEER" src 10.99.0.2

  # ufw mặc định chặn forward; lab cần netns ra ngoài để DPI chuyển tiếp.
  # Chiều ĐÚNG: gói của netns ĐI VÀO trên veth, ĐI RA qua enp8s0.
  # Bản đầu viết `in on v2dpi0 out on enp8s0` mà ufw lại dựng thành
  # "in on enp8s0 out on v2dpi0" ⇒ cho phép ngược chiều, nên netns không ra
  # được internet và DPI báo "khong noi duoc upstream". Đo được: `ufw status`
  # in `Anywhere on enp8s0 ALLOW FWD Anywhere on v2dpi0`.
  # CẢ HAI chiều. Chỉ mở chiều đi thì gói ra được (counter 34→40 đo được) nhưng
  # pha về bị chặn vì `ufw` mặc định `routed deny` và không có rule nào cho
  # `enp8s0 → v2dpi0` ⇒ netns không nhận được câu trả lời, DPI báo
  # "khong noi duoc upstream: timed out". Bằng chứng: `nft list ruleset` không
  # có dòng nào chứa `iifname "enp8s0" oifname "v2dpi0"` trước khi sửa.
  ufw route allow out on enp8s0 in on "$VETH" comment "z2d lab DPI" >/dev/null
  ufw route allow out on "$VETH" in on enp8s0 comment "z2d lab DPI" >/dev/null
  # SNAT. KHÔNG có bước này thì lab không bao giờ chạy được, và nguyên nhân
  # rất dễ chẩn đoán sai: gói ĐI RA được (counter `iifname v2dpi0 oifname
  # enp8s0` tăng 7→13) nhưng không gói nào VỀ (counter phía kia giữ 0), ping
  # 100% mất. Vì netns có nguồn `10.99.0.2` — địa chỉ riêng — nên ngoài đời
  # không có đường quay về, và bên kia lặng lẽ bỏ gói. Đừng đoán là "tường
  # chặn": đã kiểm, cả hai chiều đều có rule accept.
  nft add table ip z2d_lab 2>/dev/null || true
  nft add chain ip z2d_lab postrouting '{ type nat hook postrouting priority srcnat ; }' 2>/dev/null || true
  nft add rule ip z2d_lab postrouting ip saddr 10.99.0.0/30 oifname enp8s0 masquerade

  ip route add "$FAKE_IP"/32 dev "$VETH"
  ip route add "$FAKE2"/32 dev "$VETH"

  # SNI bị chặn: github.com. SNI được cho qua: kernel.org.
  GH=$(dig +short +time=5 github.com A  | grep -E '^[0-9]' | head -1)
  KL=$(dig +short +time=5 kernel.org A  | grep -E '^[0-9]' | head -1)
  [ -n "$GH" ] && [ -n "$KL" ] || { echo "  không phân giải được upstream"; return 1; }
  echo "$GH" > "$STATE.gh"; echo "$KL" > "$STATE.kl"

  # Ghi PID ra tệp rồi kill-theo-PID. KHÔNG dùng `pkill -f lab/dpi.py`:
  # đã dính — mẫu khớp cả dòng lệnh của chính shell đang chạy script này
  # (vì nội dung heredoc có sẵn chuỗi đó) ⇒ tự giết mình giữa chừng.
  ip netns exec "$NS" sh -c "nohup python3 $(pwd)/tests/lab/dpi.py \
      --listen 0.0.0.0:443 \
      --blocked github.com \
      --upstream $FAKE_IP=$GH \
      --upstream $FAKE2=$KL > $LOG 2>&1 & echo \$! > $PIDFILE"
  sleep 1
  echo "  lab UP · $FAKE_IP=github.com (SNI bi chan) · $FAKE2=kernel.org (SNI duoc phep)"
  ip netns exec "$NS" ss -tlnp 2>/dev/null | grep ':443' | sed 's/^/    /'
}

down(){
  # Giết MỌI tiến trình dpi còn sót, không chỉ PID cuối cùng — mỗi lần `up`
  # ghi đè PIDFILE nên các lần trước lọt lưới. Đo được: sau 5 vòng up/down còn
  # 1 tiến trình, và nó giữ cổng ⇒ lần `up` sau báo "Address already in use".
  # Lọc bằng `ps` + awk rồi kill theo PID; KHÔNG dùng `pkill -f lab/dpi.py`
  # vì mẫu đó khớp luôn dòng lệnh của shell đang chạy script này.
  ps -eo pid,args --no-headers | awk '/[l]ab\/dpi\.py/ {print $1}' \
    | while read -r p; do kill -9 "$p" 2>/dev/null; done
  rm -f "$PIDFILE"
  nft delete table ip z2d_lab 2>/dev/null || true
  ip route del "$FAKE_IP"/32 dev "$VETH" 2>/dev/null || true
  ip route del "$FAKE2"/32 dev "$VETH" 2>/dev/null || true
  ufw route delete allow out on enp8s0 in on "$VETH" 2>/dev/null || true
  ufw route delete allow out on "$VETH" in on enp8s0 2>/dev/null || true
  ufw route delete allow in on "$VETH" out on enp8s0 2>/dev/null || true
  ip link del "$VETH" 2>/dev/null || true
  ip netns del "$NS" 2>/dev/null || true
  # Dọn TẤT CẢ rule gắn nhãn lab. Bản đầu xoá theo đúng một câu lệnh, nên mỗi
  # vòng up/down để lại 1 cặp rule ⇒ dồn dập. Và lấy số PHẢI từ `[ N ]`, không
  # phải từ `grep -n` (cho SỐ DÒNG của output, không phải số rule) — dùng nhầm
  # đã xoá 6 rule thật của hệ 3 tầng. Đo được: 30 rule → 14.
  for _ in $(seq 1 40); do
    n=$(ufw status numbered 2>/dev/null | grep 'z2d lab DPI' | head -1 \
        | grep -oE '^\[[ 0-9]+\]' | grep -oE '[0-9]+')
    [ -z "$n" ] && break
    ufw --force delete "$n" >/dev/null 2>&1 || break
  done
  if [ -s "$STATE.orig" ]; then
    sysctl -q -w "net.ipv4.ip_forward=$(cat "$STATE.orig")"
    rm -f "$STATE.orig"
    # PHẢI nạp lại tệp hardening sau khi trả ip_forward. Đo được 3/3 lần:
    # đặt `net.ipv4.ip_forward=0` làm kernel TỰ ĐẶT LẠI
    # `net.ipv4.conf.all.accept_redirects` từ 0 về 1. Lab mà bỏ bước này thì
    # sau mỗi vòng up/down để lại tầng 3 yếu đi một khoá, và
    # `t1-config.sh` báo "LỆCH · khoá sysctl đúng thực tế=[17] mong đợi=[18]".
    sysctl -q -p /etc/sysctl.d/60-z2d-hardening.conf 2>/dev/null || true
  fi
  echo "  lab DOWN"
}

case "${1:-}" in
  up)   up ;;
  down) down ;;
  *)    echo "dùng: $0 up|down"; exit 2 ;;
esac
