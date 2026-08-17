# ss-erx3 — EdgeRouter X Shadowsocks 2022 (SIP022) 科学上网包

> Shadowsocks 2022 (SIP022) client for Ubiquiti EdgeRouter X (ER-X).
> Prebuilt static binaries: shadowsocks-rust (SS2022 + transparent proxy),
> chinadns-ng (DNS anti-pollution). Works on EdgeOS **3.0.x (systemd)** and 1.x/2.x.

[English README](./README-en.md)

为 EdgeRouter X (ER-X) 定制的 Shadowsocks 2022 科学上网方案,基于 **shadowsocks-rust
v1.24.0**(支持 SIP022 2022 密码与 redir 透明代理)与 **chinadns-ng**(DNS 防污染),
全部交叉编译为 **mipsel 静态二进制**,无需在路由器上安装任何依赖。

适配 EdgeOS **3.0.1**(systemd、内核 4.14.54-UBNT、iptables-legacy)以及 1.x/2.x。

---

## ✨ 特性

- **Shadowsocks 2022 (SIP022)**:`2022-blake3-aes-128/256-gcm`、`2022-blake3-chacha20-poly1305`,抗主动探测
- **透明代理**:iptables REDIRECT,LAN 内所有设备免配置翻墙(TCP)
- **SOCKS5 代理**:`192.168.1.1:1080`(含 UDP 中继)
- **DNS 防污染**:chinadns-ng 按 chnroute IP 分流,国外域名经 SS 隧道走 TCP DNS
- **开箱即用**:`install.sh` 一键安装;systemd 单元(EdgeOS 3.x)/ rc.local + post-config.d 自启
- **国内 IP 表在线更新**:`update-chnroute.sh`(来源 17mon/china_ip_list)

## 📁 文件结构

```
ss-erx3/
├── install.sh                              # 一键安装脚本(交互式)
├── UPGRADE-GUIDE.md                        # 完整升级指南(固件升级/服务端/排障,含踩坑实录)
├── BUILD-REPRODUCE.md                      # 交叉编译复现文档
├── THIRD-PARTY-NOTICES.md                  # 第三方组件许可证
├── LICENSE                                 # MIT
├── etc/init.d/shadowsocks                  # 服务脚本
├── etc/systemd/system/shadowsocks.service  # systemd 单元(EdgeOS 3.x)
└── config/shadowsocks/
    ├── bin/  sslocal · chinadns-ng · chinadns · pdnsd · update-chnroute.sh · ss-monitor.sh
    └── conf/ shadowsocks.json.example · chinadns-ng.conf · pdnsd.conf · chnroute.txt
```

## 🚀 快速开始

```bash
# 1) 上传到路由器
scp -r ss-erx3 admin@192.168.51.1:/tmp/

# 2) SSH 登录路由器执行
cd /tmp/ss-erx3
sudo bash install.sh
```

按提示输入服务器地址、端口、方法、密钥、ISP DNS。

### ⚠️ 安装前必读(踩坑总结,详见 UPGRADE-GUIDE.md)

1. **服务端必须支持 2022**:shadowsocks-rust / sing-box / xray(**3X-UI**)。shadowsocks-libev 不支持。
2. **xray/3X-UI 服务端只能用 `2022-blake3-aes-128/256-gcm`**,不支持 chacha20-poly1305 变体;方法统一选 **aes-256-gcm**。
3. **密钥格式**:xray 多用户(3X-UI Clients 多个)时,路由器配置必须写 **`客户端A密钥:客户端B密钥`**(双密钥,EIH 要求);只写单个密钥会"连上即断"。
4. **部署后必做**:让 DHCP 把路由器自身(LAN IP)作为客户端 DNS 下发,否则客户端 DNS 被污染、透明代理对墙外站点超时:
   ```
   configure
   set service dhcp-server shared-network-name LAN subnet 192.168.51.0/24 dns-server 192.168.51.1
   commit && save
   ```
   客户端重连 WiFi / `ipconfig /renew` 生效。

### 验证

```bash
curl -x socks5h://127.0.0.1:1080 -I https://www.google.com   # 隧道(应 200)
dig @192.168.51.1 www.google.com                              # 客户端 DNS(真实 IP)
```

## 🛠 日常使用

```bash
sudo systemctl status/restart/stop shadowsocks   # EdgeOS 3.x(systemd)
sudo /etc/init.d/shadowsocks status              # 兼容写法(自动重定向 systemctl)
```

可选自愈监控(每 5 分钟检测,失败自动重启):
```
*/5 * * * * sh /config/shadowsocks/bin/ss-monitor.sh
```

国内 IP 表更新:
```bash
sudo sh /config/shadowsocks/bin/update-chnroute.sh
```

## 📚 文档

- [UPGRADE-GUIDE.md](./UPGRADE-GUIDE.md)— 从 EdgeOS 1.10.11 升到 3.0.1 + SS2022 的完整指南:固件升级、服务端配置、密钥格式、DHCP DNS、故障排查(含本项目的实战踩坑记录)
- [BUILD-REPRODUCE.md](./BUILD-REPRODUCE.md)— sslocal/chinadns-ng 的 mipsel 交叉编译全过程(Zig + Rust build-std)

## ⚖️ 许可证与致谢

- 本项目代码(脚本、文档):**MIT**,见 [LICENSE](./LICENSE)
- 第三方二进制各自保留许可证,见 [THIRD-PARTY-NOTICES.md](./THIRD-PARTY-NOTICES.md)
- 安装/服务脚本基于 [izerosoul/shadowsocks_erx](https://github.com/izerosoul/shadowsocks_erx) 的思路重写,特此致谢
- 上游项目:[shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust) · [chinadns-ng](https://github.com/zfl9/chinadns-ng) · [17mon/china_ip_list](https://github.com/17mon/china_ip_list)

## ⚠️ 免责声明

本仓库仅用于技术学习与交流。请遵守所在国家/地区的法律法规,使用者自行承担一切责任。
