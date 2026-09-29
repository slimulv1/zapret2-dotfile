# Khung kiểm thử — `install.sh`

47+ phép kiểm, viết bằng pytest + testinfra. Mục tiêu không phải "cho xanh" mà
là **đòi bằng chứng**: mỗi test phải đo được, và phép đo hỏng thì phải báo là
hỏng chứ không được trả về số 0 rồi tưởng là đạt.

## Cài đặt (không đụng hệ thống)

```bash
python3 -m venv /tmp/z2d-qa/venv
/tmp/z2d-qa/venv/bin/python -m pip install pytest testinfra
```

Không `pacman -S python-pytest` — cài vào venv là đủ, và không đụng gói nền.

## Chạy

```bash
export SUDO_ASKPASS=/tmp/.zz.sh          # xem "Chuẩn bị sudo" bên dưới

# 1) chỉ phép ĐỌC — an toàn, không đổi gì trên máy
sudo -A /tmp/z2d-qa/venv/bin/python -m pytest tests/ -q

# 2) đầy đủ, gồm cài/gỡ thật
sudo -A /tmp/z2d-qa/venv/bin/python -m pytest tests/ -q \
     --nd-id <ID-6-ky-tu> --run-destructive \
     --snapshot 2026.09 --kernel linux-cachyos

# 3) chỉ một nhóm
… -m invariants          # quét invariant §4
… -m "not destructive"   # chỉ phép đọc (mặc định khi thiếu --run-destructive)
```

**Phải chạy bằng `sudo`**: phép đo đoạn gói cần `CAP_NET_RAW`. Cố chạy bằng
user thường sẽ bỏ qua test đó kèm lý do rõ ràng.

## Chuẩn bị sudo

Dùng `SUDO_ASKPASS`, **không** dùng `printf … | sudo -S` — cái sau làm PAM
conversation hỏng và có thể khoá tài khoản (đã dính, phải `faillock --reset`).

```bash
cat > /tmp/.zz.sh <<'EOF'
#!/bin/sh
printf '%s\n' 'MẬT-KHẨU-Ở-ĐÂY'
EOF
chmod 700 /tmp/.zz.sh
```

Tệp này **nằm ngoài repo** và không được commit. Khi xong thì xoá.

## Vì sao chạy test phá huỷ lại an toàn

Đặc tả PHA 3 cô lập bằng snapshot VM. Máy này không có QEMU, nên khung tự làm
thay bằng hai cơ chế:

| Cơ chế | Việc |
|---|---|
| `_restore_machine_at_session_end` | ghi nhớ trạng thái **đầu phiên**, cuối phiên trả máy về đúng trạng thái đó |
| `require_installed` / `require_clean` | mỗi test phá huỷ có đúng tiền đề kiện nó cần |
| `offload_off` | tắt TSO/GSO để đo gói, **bật lại đúng trạng thái gốc** trong `finally` |
| bảng `nft` tạm | tự xoá trong `finally`, và test tự kiểm là đã xoá |

Bằng chứng nó hoạt động: chạy xong 48 test phá-huỷ, `zapret2` vẫn active,
20 rule, backup nguyên vẹn.

## Vì sao có chỗ ghi "KHÔNG ĐO ĐƯỢC"

`Blocked` / `pytest.skip` với lý do cụ thể, không phải trả về giá trị giả:

- `vm` — thiếu `qemu-system-x86_64`, `qemu-img` ⇒ BLOCKED, nêu rõ còn thiếu gì
- `dig @[2a07:a8c0::]` — `getaddrinfo` của `dig` không phân tích được literal
  dạng `::`. Đó **không** phải mạng hỏng ⇒ `qa/dnsprobe.py` trả
  `KHÔNG ĐO ĐƯỢC` thay vì `CHẶN`, và test IPv6 dùng bằng chứng `ss` thật
- `dig -p 853` thiếu `+tls` — gửi DNS rõ qua cổng DoT, NextDNS im lặng

## Ma trận test

| Tệp | Nhóm | Phá huỷ? |
|---|---|---|
| `test_invariants.py` | §4: tường DNS, DoT, fail-closed, desync 1 byte, IPv6, sysctl CachyOS | 2 ca có |
| `test_config.py` | 3 tệp cấu hình + `IPT_SYSCTL` trỏ đúng | không |
| `test_install.py` | cài: hook NFQUEUE, service, 16 rule DNS, 1 backup, gói nền | có |
| `test_uninstall.py` | gỡ: tệp gói về gốc, cờ `ENABLED`, không sót rule | có |
| `test_idempotent.py` | cài 2 lần không nhân bản, không đầu backup | có |
| `test_negative.py` | ID sai, cờ lạ, giá trị bắt đầu bằng `-`, tự chữa lành | có |
| `test_airgap.py` | không có `pacman` ⇒ chết sạch; `--help` không đụng gì | 1 ca có |

## Những lỗi khung này đã bắt được

Hai lỗi S2 ở `install.sh` lộ ra khi viết `test_uninstall.py` và
`test_idempotent.py`, **không phải** khi đọc code:

- bản sao lưu bị *"đầu"* ⇒ uninstall không bao giờ về bản gốc của gói
- uninstall bỏ qua cờ `ENABLED` của ufw

Và khung tự bắt được một lỗ hổng trong chính cách tôi sửa: bộ dò "backup đã đầu"
lọc đúng chuỗi `z2d-sysctl.conf` nên **không** phát hiện `/etc/systemd/resolved.conf`
cũng bị đầu. Đã đổi lọc mọi dấu vết `z2d`.
