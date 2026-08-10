# Tailscale Persistent Setup for Snapmaker U1

Thiết lập Tailscale chạy bền vững (persistent) trên máy in 3D **Snapmaker U1** chạy Buildroot Linux (ARM64). Tailscale sẽ tiếp tục chạy ngay cả khi bạn đóng SSH/CMD session và tự động khởi động khi máy in khởi động lại.

## 🎯 Vấn đề

Snapmaker U1 chạy Buildroot Linux với kernel **không hỗ trợ TUN device**. Khi cài Tailscale theo cách thông thường:

- Tailscale bị **kill khi đóng SSH/CMD session** (vì không dùng `nohup`)
- Không tự động khởi động khi máy in reboot
- Cần dùng `--tun=userspace-networking` vì kernel thiếu TUN support

## ✅ Giải pháp

1. **Dùng `nohup`** để tailscaled chạy nền và sống sót khi đóng session
2. **Cấu hình `/etc/rc.local`** để tự động khởi động khi boot
3. **Dùng `--tun=userspace-networking`** vì kernel không có TUN device

## 📁 Cấu trúc dự án

```
tailscale/
├── README.md                    # Tài liệu này
├── .gitignore                   # File loại trừ
└── scripts/
    ├── install-tailscale.sh        # Cài đặt Tailscale từ đầu (chạy trên U1)
    ├── setup-tailscale-persist.sh  # Thiết lập Tailscale bền vững (chạy trên U1)
    ├── fix_rc_loc.sh               # Sửa rc.local dùng nohup (chạy trên U1)
    ├── check-tailscale.sh          # Kiểm tra trạng thái Tailscale (chạy trên U1)
    ├── fix-tailscale.ps1           # Sửa qua SSH từ Windows
    └── run-fix.ps1                 # Chạy fix_rc_loc.sh qua plink từ Windows
```

## 🚀 Cách sử dụng

### Cách 1: Chạy trực tiếp trên Snapmaker U1 (SSH)

```bash
# Copy script lên máy in
scp scripts/setup-tailscale-persist.sh root@192.168.1.81:/tmp/

# SSH vào máy in
ssh root@192.168.1.81

# Chạy script
chmod +x /tmp/setup-tailscale-persist.sh
/tmp/setup-tailscale-persist.sh
```

### Cách 2: Từ Windows qua plink (tự động)

```powershell
# 1. Tải plink.exe (PuTTY) về C:\temp\plink.exe
#    https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe

# 2. Chạy script sửa rc.local
cd scripts
.\run-fix.ps1

# 3. Hoặc chạy script sửa trực tiếp
.\fix-tailscale.ps1
```

## ⚙️ Cấu hình

Các thông số SSH mặc định trong script:

| Tham số | Giá trị |
|---------|---------|
| IP máy in | `192.168.1.81` |
| Username | `root` |
| Password | `snapmaker` |
| Tailscale version | `1.80.0` (ARM64) |

> ⚠️ **Lưu ý**: Nếu IP hoặc password khác, hãy sửa trong các script trước khi chạy.

## 📝 Chi tiết kỹ thuật

### Tại sao cần `--tun=userspace-networking`?

Kernel Buildroot trên Snapmaker U1 không có module TUN (`/dev/net/tun` không tồn tại). Tailscale cần TUN để tạo virtual network interface. Giải pháp là dùng userspace networking - Tailscale tự xử lý network trong userspace thay vì kernel.

### Tại sao cần `nohup`?

Khi chạy `tailscaled &` trong SSH session, process sẽ nhận SIGHUP khi session đóng và bị kill. `nohup` chặn SIGHUP, giúp process tiếp tục chạy nền.

### Nội dung `/etc/rc.local` sau khi sửa

```bash
#!/bin/bash
# Tailscale auto-start
mknod /dev/net/tun c 10 200 2>/dev/null
nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
```

## 🔧 Troubleshooting

### Kiểm tra tailscaled đang chạy

```bash
pgrep -a tailscaled
```

### Kiểm tra Tailscale status

```bash
tailscale status
```

### Kiểm tra IP Tailscale

```bash
tailscale ip -4
```

### Nếu tailscaled không chạy sau reboot

```bash
# Kiểm tra rc.local
cat /etc/rc.local

# Chạy thủ công
nohup tailscaled --tun=userspace-networking > /dev/null 2>&1 &
```

## 📦 Cài đặt Tailscale từ đầu (nếu cần)

```bash
# Copy script lên máy in
scp scripts/install-tailscale.sh root@192.168.1.81:/tmp/

# SSH vào máy in và chạy
ssh root@192.168.1.81
chmod +x /tmp/install-tailscale.sh
/tmp/install-tailscale.sh
```

Script sẽ tự động:
1. Kiểm tra xem Tailscale đã cài chưa
2. Tải Tailscale 1.80.0 ARM64 về
3. Cài đặt vào `/usr/bin/`
4. Tạo `/dev/net/tun`
5. Khởi động tailscaled với `--tun=userspace-networking`
6. Cấu hình auto-start trong `/etc/rc.local`
7. Kết nối tới Tailscale network

## 🔍 Kiểm tra trạng thái

```bash
# Copy script kiểm tra lên máy in
scp scripts/check-tailscale.sh root@192.168.1.81:/tmp/

# SSH vào máy in và chạy
ssh root@192.168.1.81
chmod +x /tmp/check-tailscale.sh
/tmp/check-tailscale.sh
```

## 📄 License

MIT License - Xem file [LICENSE](LICENSE) để biết chi tiết.

## 🤝 Đóng góp

Mọi đóng góp đều được hoan nghênh! Hãy tạo Pull Request hoặc Issue nếu bạn gặp vấn đề hoặc có cải tiến.