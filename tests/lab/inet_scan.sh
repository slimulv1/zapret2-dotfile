#!/usr/bin/env bash
# Dựng "máy ngoài" để kiểm tầng 3 (chặn INPUT).
#
#   Sơ đồ:
#       netns z2d_in ──vin0 (nguồn giả lập)── host: v2in0 (10.98.0.1/30)
#       netns quét tới ĐỊA CHỈ LAN THẬT của host (192.168.1.24) ⇒ gói đi đúng
#       chuỗi prerouting → INPUT, y hệt gói từ một máy khác trong mạng.
#
#   Hai kịch bản, khác nhau ở NGUỒN:
#     up 192.168.99.2   → nằm trong 192.168.0.0/16 ⇒ KĐANG ĐƯỢC KDE Connect mở
#     up 203.0.113.5    → ngoài 192.168.0.0/16 ⇒ KHÔNG được mở gì cả
#
#   Vì sao phải khai báo route cho nguồn giả lập: `rp_filter` chế độ chặt (1)
#   sẽ loại gói có nguồn không định tuyến được qua đúng giao diện đến — và nó
#   loại TRƯỚC khi tới chuỗi INPUT. Không khai báo route thì phép thử đo sai
#   thứ: đo `rp_filter` chứ không đo tường.
set -uo pipefail

NS=z2d_in
VETH=v2in0
PEER=vin0
HOST_IP=10.98.0.1/30
STATE=/tmp/z2d-qa/inlab.state

up(){
  local src=$1
  [ "$(id -u)" -eq 0 ] || { echo "  cần root"; return 1; }
  down >/dev/null 2>&1 || true
  mkdir -p /tmp/z2d-qa
  echo "$src" > "$STATE.src"

  ip netns add "$NS"
  ip link add "$VETH" type veth peer name "$PEER"
  ip link set "$PEER" netns "$NS"
  ip addr add "$HOST_IP" dev "$VETH"
  ip link set "$VETH" up
  ip -n "$NS" addr add 10.98.0.2/30 dev "$PEER"
  ip -n "$NS" link set lo up
  ip -n "$NS" link set "$PEER" up
  ip -n "$NS" route add default via 10.98.0.1

  # Gán NGUỒN giả lập. Dùng /24 để có route on-link, và khai báo route về
  # nguồn đó trên host để rp_filter chấp nhận.
  ip -n "$NS" addr add "${src}/24" dev "$PEER"
  local net=${src%.*}.0
  ip route add "$net"/24 dev "$VETH"
  # ÉP NGUỒN. Nếu không, gói tới 192.168.1.24 đi theo route mặc định và kernel
  # chọn nguồn 10.98.0.2 — tức KHÔNG nằm trong 192.168.0.0/16, nên rule KDE
  # Connect không khớp và phép thử đo sai thứ. Đo được: counter
  # `ufw-user-input` = 0 dù quét đúng cổng 1716.
  ip -n "$NS" route replace 192.168.1.24/32 dev "$PEER" src "$src"
  echo "  in-lab UP · nguồn $src (mạng $net/24) · quét tới 192.168.1.24"
}

down(){
  if [ -f "$STATE.src" ]; then
    local net; net=$(sed 's/\.[0-9]*$/.0/' "$STATE.src")
    ip route del "$net"/24 dev "$VETH" 2>/dev/null || true
    rm -f "$STATE.src"
  fi
  ip link del "$VETH" 2>/dev/null || true
  ip netns del "$NS" 2>/dev/null || true
  echo "  in-lab DOWN"
}

case "${1:-}" in
  up)   up "${2:?cần nguồn, vd 192.168.99.2}" ;;
  down) down ;;
  *)    echo "dùng: $0 up <nguon-cidr> | down"; exit 2 ;;
esac
