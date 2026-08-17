# EdgeRouter X 科学上网升级指南
### EdgeOS 1.10.11 → 3.0.1 + Shadowsocks 2022 (SIP022)

> 适用设备:EdgeRouter X / ER-X-SFP / EP-R6 / ER-10X(e50 平台)
> 本指南与 `ss-erx3/` 安装包配套。

---

## 0. 事实核查(从官方固件解包验证,2026-08)

以下结论全部来自对官方固件 `e50.v3.0.1.5862409.tar` 的直接解包检查:

| 项目 | EdgeOS 1.10.11 | EdgeOS 3.0.1 |
|---|---|---|
| 固件文件 | e50.v1.10.11.*.tar | **e50.v3.0.1.5862409.tar**(2025-10-30 发布) |
| Linux 内核 | 3.10.x | **4.14.54-UBNT**(gcc 6.3.0 构建,2025-09-24) |
| 用户空间 | Debian 8 (Jessie) | **Debian 9.13 (Stretch), glibc 2.24** |
| iptables | iptables-legacy | **iptables-legacy(xtables-multi,无 nftables)** |
| ipset | 有 | **有,内核模块齐全** |
| init 系统 | sysvinit | **systemd(PID1 = systemd;`/etc/init.d/*` 经 40-systemd 钩子重定向到 systemctl,需为自定义服务创建 systemd 单元)** |
| /config | 独立分区,持久化 | **保留,`/config/scripts/post-config.d/` 存在** |
| WireGuard | 无 | **内置内核模块** |

**结论:内核从 3.10 升到 4.14,但用户空间和网络栈基本没变。**

- 旧的静态链接 MIPS 二进制(chinadns 等)是 MIPS-I、ELF for Linux 2.6.18,内核 4.14 完全向后兼容,**可以继续运行**;pdnsd 仅需 GLIBC_2.8 符号,glibc 2.24 兼容;
- 旧 init 脚本用的 `iptables -t nat REDIRECT` + `ipset`,在 3.0.1 的 iptables-legacy 上**原样可用**;
- 真正需要换客户端二进制的原因只有一个:**Shadowsocks 2022 需要支持 SIP022 的实现**(shadowsocks-libev 上游不支持,本包改用 shadowsocks-rust)。

---

## 1. 第一步:升级固件到 EdgeOS 3.0.1

### 1.1 备份
1. Web 界面或 CLI 备份配置:
   ```
   show configuration | save /tmp/backup-1.10.11.conf
   ```
   或用 GUI「System → Backup」下载 `config.boot`。
2. 建议同时用 `scp` 把 `/config/shadowsocks/` 整个目录下载到电脑(它包含你 7 年的 SS 配置)。

### 1.2 获取固件
官方渠道(UI.com → EdgeRouter → EdgeRouter X → Downloads):
`e50.v3.0.1.5862409.tar`

> 注意:固件文件约 74MB,升级前确认路由器闪存充足。3.0.1 采用双分区(active/backup)机制,升级失败可回退。

### 1.3 升级
1. GUI:System → Upload firmware,选择 `.tar` 文件,点 Upgrade。
2. 等待 3–5 分钟,路由器自动重启。
3. 登录后确认版本:
   ```
   show version
   ```
   应显示 `Version: v3.0.1.5862409.250924.1407`、`Kernel: 4.14.54-UBNT`。

### 1.4 升级后必做检查
- **第三方包需要重装**:zerotier 等(恩山用户反馈:2.0.9-hotfix4 → 3.0.1 后需重装 zerotier)。`/config` 下的文件会保留,但 `/etc` 下的软件包会被清空——所以本方案的 SS 全部放 `/config`,升级后重跑一次 `install.sh` 即可(或直接执行第 3 步安装新版)。
- 配置迁移:官方固件自带 config-migration 脚本,1.x/2.x 配置一般能迁移。**如果 1.10.11 配置里有自定义防火墙规则,升级后检查 `show firewall`**。
- 已知社区反馈:电信宽带下 IPv6 前缀分配异常(部分用户反馈,与 SS 无关);如果遇到可考虑在 CLI 关掉 IPv6 或换 OpenWrt(不推荐,影响小)。

### 1.5 回滚
升级失败时,路由器会自动从 backup 分区启动。手动回滚:上传旧版固件(如 e50.v1.10.11 或 e50.v2.0.9-hotfix.x)重新升级即可,`/config` 配置不受影响。

---

## 2. 第二步:升级到 Shadowsocks 2022 (SIP022)

### 2.1 为什么要升
- 旧的 shadowsocks-libev **v3.1.0**(2017 年)协议没有 EIH(加密身份头),流量特征明显、**可被主动探测**;
- **Shadowsocks 2022 (SIP022)** 引入:
  - **EIH**:每个连接都带加密身份头,主动探测者无法区分真假服务端(解决"抗探测/抗干扰"的核心问题);
  - **BLAKE3** 密钥派生(替代旧的 HKDF-SHA1);
  - 固定长度 **base64 PSK**(类似 WireGuard),不再用任意字符串密码;
  - 原生支持**单端口多用户**(多 PSK)。
- 兼容性:**2022 与老协议不互通**——必须服务端、客户端同时升级。

### 2.2 客户端:本安装包(`ss-erx3`)
基于 **shadowsocks-rust v1.24.0**(官方支持 SIP022),用 **Zig + Rust nightly build-std 交叉编译为静态 MIPS32r2 小端二进制**(11.5MB,无任何动态库依赖,内核 4.14 直接运行)。

> 为什么不用 shadowsocks-libev:上游 shadowsocks-libev(包括 3.3.6)从未合并 2022 密码支持;shadowsocks-rust 是 SIP022 的参考实现,同时支持新旧协议,并原生提供 `redir`(透明代理)模式,与你的 iptables REDIRECT 架构完全兼容。

一个 `sslocal` 二进制、两个进程实例:
- `:1080` — SOCKS5 代理(含 UDP 中继,`-U`)
- `:1081` — 透明代理(`--protocol redir --tcp-redir redirect`,iptables REDIRECT 进来的 TCP 流量)

支持的 2022 方法:

| 方法 | 密钥长度 | ER-X 上的评价 |
|---|---|---|
| **2022-blake3-chacha20-poly1305** | 32 字节 | **推荐**。SIP022 规格明确说它是"为没有 AES 指令的 CPU 设计"。MT7621 无 AES 硬件加速,纯软件 chacha20 比 AES 快得多 |
| 2022-blake3-aes-128-gcm | 16 字节 | 可用,但软件 AES-GCM 在 MIPS 上吞吐明显更低 |
| 2022-blake3-aes-256-gcm | 32 字节 | 同上,更慢 |
| chacha20-ietf-poly1305(旧) | — | 仅作过渡:保持 7 年旧配置不变,但不解决抗探测 |

### 2.3 生成密钥(两端必须一致)
```
openssl rand -base64 32     # 2022-blake3-chacha20-poly1305 / aes-256-gcm
openssl rand -base64 16     # 2022-blake3-aes-128-gcm
```
> 旧版 SS 的"密码"是一串任意字符;**2022 的"密码"必须是 base64 编码的固定长度随机密钥**。不能直接沿用旧密码!

### 2.4 服务端(VPS)升级
任选其一(必须支持 2022):

**方案 A:shadowsocks-rust(推荐,服务端首选)**
```json
{
    "server": "0.0.0.0",
    "server_port": 8388,
    "method": "2022-blake3-chacha20-poly1305",
    "password": "<上面生成的 base64 密钥>"
}
```
安装:`cargo install shadowsocks-rust` 或下载 release 二进制,用 systemd 托管。

**方案 B:sing-box / xray / 3X-UI**(面板用户最常见)
- 支持 `shadowsocks` 入站 + `2022-blake3-*` 密码;配置示例略(见各自文档)。

> ⚠️ 注意:
> 1. **shadowsocks-libev 服务端不支持 2022 密码**,如果你的 VPS 现在跑的是 libev,必须换成 shadowsocks-rust / sing-box / xray 三者之一(或保持旧协议过渡)。
> 2. **xray 的 SS2022 只支持 `2022-blake3-aes-128-gcm` 和 `2022-blake3-aes-256-gcm`,不支持 `2022-blake3-chacha20-poly1305`**。用 3X-UI/xray 时方法必须选 **aes-256-gcm**(或 aes-128-gcm),并让路由器端一致。否则 xray 拒绝启动,日志报:`shadowsocks 2022 (multi-user): only blake3-aes-*-gcm methods are supported`。
> 3. **xray 的 SS2022 强制要求 EIH(加密身份头),且默认多用户模式**——见 2.5.1 的密钥格式说明,这是"能连上但立刻被断开"的最常见原因。

### 2.5 客户端配置(`/config/shadowsocks/conf/shadowsocks.json`)
```json
{
    "server": "your-vps.example.com",
    "server_port": 8388,
    "local_address": "0.0.0.0",
    "local_port": 1080,
    "password": "<base64 密钥>",
    "timeout": 300,
    "method": "2022-blake3-chacha20-poly1305"
}
```

### 2.5.1 ⚠️ 密钥格式:xray 服务端必须用"双密钥"写法(踩坑实录)
shadowsocks-rust 客户端对 2022 密码的解析规则(`rsplit(':')`):
- `-k 密钥`(单个)→ **不发送 EIH**,xray 必然拒绝(表现:隧道建立后立刻被 RST);
- `-k 身份密钥:主密钥`(冒号分隔,**冒号后是主密钥,冒号前是身份密钥**)→ 发送 EIH,服务端才能验证通过。

3X-UI 的 SS2022 入站默认是**多用户模式**(Clients 列表,每个客户端一个密钥)。**只要服务端不止一个客户端密钥,路由器端就必须写成双密钥格式**(冒号前的作为 EIH 身份、冒号后的作为主密钥,服务端匹配到其中一个即成功)。

> 实战结论:3X-UI 里同时存在"面板生成的手机密钥"和"手动填的路由器密钥"两个客户端时,路由器配置必须写成 `"手机密钥:路由器密钥"` 才能连通;**改成任意单个密钥都连不上**(日志:连接建立 → 约 200ms 后 `Connection reset by peer`)。若服务端只保留一个客户端,可写 `密钥:同一密钥`(如 `K1:K1`)。

验证隧道是否连通(用 SOCKS5 绕开 DNS 因素):
```bash
curl -x socks5h://127.0.0.1:1080 -I --connect-timeout 8 https://www.google.com
```
- `HTTP/2 200` = 隧道通;
- `curl: (35) Unknown SSL protocol error` 或快速失败 = 服务端方法/密钥不匹配,见第 4 节排障表。

### 2.6 抗干扰能力说明(重要预期管理)
- SS2022 解决的是**主动探测**(GFW 扫描端口、发探测包识别 SS 服务端)——这是旧版 SS 被封锁的主要方式;
- 它**不承诺**解决所有 DPI 特征识别。如果未来遇到更激进的封锁,常见进阶方案:
  1. 服务端换成 **sing-box / xray**,把 SS2022 流量包进 **REALITY** 或 **TLS 隧道**;
  2. 或换 **Hysteria2 / NaiveProxy** 等新协议;
  3. 保留本路由器方案不变(路由器只管透明代理),只换服务端协议——客户端侧相应调整。
- 对 7 年只求"稳定能用"的使用场景,SS2022 + AES-256-GCM(xray 服务端)或 chacha20(shadowsocks-rust 服务端)是当前性价比最高的升级。

### 2.7 性能预期
- MT7621 双核 880MHz,无 AES 硬件加速;
- 软件 chacha20-poly1305 + BLAKE3 在 ER-X 上实测通常可达 **30–60 Mbps**(与旧版 chacha20-ietf-poly1305 相近,BLAKE3 开销很小);
- 如果你宽带 >100M 且对速度敏感,ER-X 本身(NAT 转发)就是瓶颈,与 SS 版本无关;
- 建议升级后用 `iperf3` 或 speedtest 实测,若 <20Mbps 再排查(见故障排查)。

---

## 3. 第三步:安装 `ss-erx3` 包

### 3.1 文件清单
```
ss-erx3/
├── install.sh                         # 安装脚本(交互式)
├── UPGRADE-GUIDE.md                   # 本指南
├── BUILD-REPRODUCE.md                 # 交叉编译复现说明
├── etc/init.d/shadowsocks             # 服务脚本(EdgeOS 3.x 适配,shadowsocks-rust 版)
├── etc/systemd/system/shadowsocks.service   # systemd 单元(EdgeOS 3.x PID1=systemd 必需)
├── config/
│   ├── scripts/post-config.d/50-ss-rules.sh   # 每次 commit 后重挂 iptables 规则
│   └── shadowsocks/
│       ├── bin/
│       │   ├── sslocal                # 新编译:shadowsocks-rust v1.24.0,SS2022 + redir
│       │   ├── chinadns-ng            # 官方预编译:chinadns-ng 2025.08.09(mipsel musl 静态)
│       │   ├── chinadns               # 旧版,仅当 chinadns-ng 缺失时作为兜底
│       │   ├── pdnsd                  # 旧版,同上(仅需 GLIBC≤2.8,glibc 2.24 兼容)
│       │   ├── update-chnroute.sh     # chnroute.txt 在线更新脚本
│       │   └── ss-monitor.sh          # 5 分钟健康检查/自愈
│       └── conf/
│           ├── shadowsocks.json.example
│           ├── chinadns-ng.conf       # chinadns-ng 配置(替代 pdnsd 的 TCP DNS 角色)
│           ├── pdnsd.conf             # 旧版兜底用
│           └── chnroute.txt           # 国内 IP 表(已更新至 17mon 2026-08 数据,7456 条)
```

### 3.2 安装步骤
```bash
# 1) 把 ss-erx3 目录传到路由器
scp -r ss-erx3 admin@192.168.1.1:/tmp/

# 2) SSH 登录路由器,执行
cd /tmp/ss-erx3
sudo bash install.sh
```
按提示输入:服务器地址、端口、方法、密钥、ISP DNS。
> 方法选择提醒:**3X-UI/xray 服务端必须选 `2022-blake3-aes-256-gcm`(选项 3)**;
> 只有 shadowsocks-rust 服务端才选 chacha20-poly1305(选项 1,见 2.4 的警告)。
> 密钥若来自 3X-UI 多用户客户端,填"双密钥"格式(见 2.5.1)。

### 3.3 安装脚本做了什么(可手工复查)
1. 写 `/config/shadowsocks/conf/shadowsocks.json`(2022 格式);
2. 复制二进制到 `/config/shadowsocks/bin/`(**放 /config 是为了:配置备份一起备份、固件升级不丢**);
3. 复制 init 脚本到 `/etc/init.d/shadowsocks`;
4. **DNS 改用 config tree 方式**(关键改进):
   ```
   set service dns forwarding options "server=127.0.0.1#5301"
   set service dns forwarding options "no-resolv"
   ```
   旧版直接 `sed` 改 `/etc/dnsmasq.conf`,但 vyatta 每次 commit 会重新生成该文件导致改动丢失;config tree 方式持久化在 `config.boot`,重启/commit 都不丢。
5. 开机自启:**post-config.d 脚本**(每次 commit 和开机都会运行,自动补挂被 commit 清掉的 iptables 规则)+ rc.local 兜底;
6. **systemd 单元**(EdgeOS 3.x 关键):PID 1 是 systemd,`/etc/init.d/* start` 会被
   `/lib/lsb/init-functions.d/40-systemd` 自动重定向为 `systemctl start *.service`,
   因此 install.sh 会创建并启用 `/etc/systemd/system/shadowsocks.service`
   (`Type=oneshot`,ExecStart/ExecStop 调用 init 脚本);之后 `systemctl start/stop/status shadowsocks`
   即可管理,rc.local 和 post-config.d 里的调用也会经由该单元正常生效;
7. 启动服务(`systemctl restart shadowsocks`)。

DNS 链路(新版,chinadns-ng 替代 chinadns + pdnsd):
```
客户端 → dnsmasq(53) → chinadns-ng(5301)
   ├─ 应答 IP 命中 chnroute ipset(国内)→ 114.114.114.114 直接解析
   └─ 其余 → tcp://8.8.8.8(TCP 查询经 iptables REDIRECT 走 SS 隧道)
```
说明:chinadns-ng 用 `ipset-name4 chnroute` 做 IP 分流判定,`chnroute` ipset 由
init 脚本启动时从 `chnroute.txt` 载入(约 7500 条,秒级完成);`trust-dns tcp://8.8.8.8`
的 TCP 查询与旧 pdnsd 一样被透明代理进 SS 隧道,防污染效果相同。

### 3.3.1 ⚠️ 部署后必做:DHCP 必须下发路由器自身作为客户端 DNS(踩坑实录)
**透明代理能不能用,取决于客户端解析到的目标 IP 是否真实**。EdgeOS 的 DHCP
默认把 **WAN 侧 DNS(如 119.29.29.29/223.5.5.5)下发给 LAN 客户端**,而 GFW
会对这些 UDP 查询注入污染应答 → 客户端拿到假 Google IP → 透明代理把流量送进
隧道后,服务端连假 IP → 超时。症状:**国内正常、SOCKS5 正常、透明代理对墙外
站点全部超时**,且客户端 `dig` 墙外域名得到的是 Facebook/Twitter 等无关 IP。

修复:让 DHCP 把**路由器自身(LAN IP)**作为第一个 DNS 下发(经 dnsmasq →
chinadns-ng 防污染):
```bash
configure
set service dhcp-server shared-network-name LAN subnet 192.168.51.0/24 dns-server 192.168.51.1
commit
save
```
(WAN DNS 可保留为后备,但路由器 IP 必须在最前面。改完后客户端需重连 WiFi /
`ipconfig /renew` 重新获取 DHCP。)

> 排查提示:路由器**本机**的 curl/getent 不能用来看 DNS 效果——EdgeOS 自身的
> `/etc/resolv.conf` 直连 WAN DNS(不走 dnsmasq),本机解析墙外域名必然被污染。
> 要测真实客户端效果,请在 LAN 客户端上 `dig @<路由器IP> www.google.com`,
> 或临时用 `curl --resolve www.google.com:443:<真实IP> https://www.google.com` 验证透明代理。
> (可选)让路由器本机也走防污染:`set system name-server 127.0.0.1`。

chnroute.txt 更新(来源:17mon/china_ip_list,IPIP.net 维护):
```bash
sudo sh /config/shadowsocks/bin/update-chnroute.sh
# 可选:crontab 每周自动更新
# 0 3 * * 1 sh /config/shadowsocks/bin/update-chnroute.sh >> /var/log/chnroute_update.log 2>&1
```

### 3.4 日常使用
```bash
# EdgeOS 3.x(systemd)推荐方式:
sudo systemctl status shadowsocks      # 查看状态
sudo systemctl restart shadowsocks     # 重启
sudo systemctl stop shadowsocks        # 停止(会清 iptables 规则)
# 或兼容方式(自动重定向到 systemctl):
sudo /etc/init.d/shadowsocks status
sudo /etc/init.d/shadowsocks restart
```
自愈监控(沿用旧版,可选):
```
sudo crontab -e
# 添加:
*/5 * * * * sh /config/shadowsocks/bin/ss-monitor.sh
```
Socks5 代理:任意设备设 `127.0.0.1:1080`(路由器本机)/ 局域网 IP:1080。

---

## 4. 故障排查

| 症状 | 原因与处理 |
|---|---|
| `Unit shadowsocks.service could not be found` | EdgeOS 3.x 是 systemd,`/etc/init.d/*` 会重定向到 systemctl;需先创建单元:`cp ss-erx3/etc/systemd/system/shadowsocks.service /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now shadowsocks`(新版 install.sh 会自动做) |
| `curl -x socks5h://127.0.0.1:1080 ...` 报 `(35) Unknown SSL protocol error`,或隧道建立约 200ms 后 `Connection reset by peer` | 服务端方法/密钥不匹配。① 核对 method(3X-UI 里必须 `2022-blake3-aes-256-gcm`,xray 不支持 chacha20 2022);② 核对密钥字节数;③ **3X-UI 多用户模式下路由器必须用"双密钥"格式**(见 2.5.1);④ 前台跑 `sslocal ... -vv` 看日志:`identity verification failed` = 密钥错 |
| xray 日志 `shadowsocks 2022 (multi-user): only blake3-aes-*-gcm methods are supported` | xray 不支持 `2022-blake3-chacha20-poly1305`,方法改成 aes-128/256-gcm |
| xray 日志每分钟刷 `proxy/shadowsocks_2022: context canceled` | 客户端 EIH 验证失败 = 客户端密钥不在服务端用户列表里;把客户端密钥加进 3X-UI Clients(或改用双密钥格式) |
| 服务端手填密钥后仍连不上 | 3X-UI 面板改动可能没真正写入 xray 配置:在 VPS 上 `grep -c '你的base64密钥' /usr/local/x-ui/bin/config.json` 确认;0 表示没生效,删除客户端重新添加 |
| 国内正常、SOCKS5 正常、**透明代理对墙外站点超时** | 客户端 DNS 被污染(连到假 IP):DHCP 必须下发路由器 IP 作为 DNS(见 3.3.1);客户端重连 WiFi/`ipconfig /renew` |
| 路由器本机 curl 墙外超时,但 LAN 客户端正常 | 正常现象:路由器自身 resolv.conf 直连 WAN DNS(不走 dnsmasq)会被污染;可选 `set system name-server 127.0.0.1` |
| `show version` 后仍是旧版 | 双分区回退;重新上传固件,或在 GUI 检查是否从 backup 分区启动 |
| ss-redir(sslocal 透明实例)起不来,日志报 cipher 错误 | 服务端/客户端 method 或 password(base64)不一致;重新核对 |
| 2022 报 "key length" 错误 | base64 密钥字节数不对:chacha20-poly1305/aes-256 必须 32 字节,aes-128 必须 16 字节 |
| 国内网站正常,国外打不开 | 先 `curl -x socks5h://127.0.0.1:1080 -I https://www.google.com` 区分隧道 vs 透明代理;再查 `iptables -t nat -L SHADOWSOCKS` 规则是否被 commit 清掉(看 post-config.d 是否生效);最后查服务端 |
| DNS 解析失败 | 确认 chinadns-ng(5301)在运行:`netstat -lnt \| grep 5301`;再查 chnroute ipset 是否载入:`ipset list chnroute \| head` |
| 速度明显下降 | 换 chacha20 方法(软件 AES 在 MIPS 上慢;但注意 xray 服务端只能用 AES);检查 MTU/MSS |
| 升级后 zerotier 等失效 | EdgeOS 3.x 清空了 /etc 下的软件包,重新安装 |
| 用脚本改 vyatta 配置报 `calling ... without config session` | `vyatta-cfg-cmd-wrapper` 用 `$PPID` 作会话 ID,多次调用会丢会话;固定会话:`sudo env CMD_WRAPPER_SESSION_ID=xxx /opt/vyatta/sbin/vyatta-cfg-cmd-wrapper begin/set/.../commit/save`(同一个 ID) |

---

## 5. 参考资料
- [Shadowsocks 2022 协议规范 (SIP022)](https://shadowsocks.org/doc/sip022.html)
- [Shadowsocks 2022 可扩展身份头 (EIH) 规范](https://github.com/Shadowsocks-NET/shadowsocks-specs/blob/main/2022-2-shadowsocks-2022-extensible-identity-headers.md)
- [shadowsocks-rust (GitHub,本包客户端)](https://github.com/shadowsocks/shadowsocks-rust)
- [xray-core Shadowsocks 文档(注意其 2022 仅支持 AES-GCM 方法)](https://xtls.github.io/config/inbounds/shadowsocks.html)
- [3X-UI (GitHub,xray 面板)](https://github.com/MHSanaei/3x-ui)
- [chinadns-ng(GitHub,本包 DNS 组件,官方预编译)](https://github.com/zfl9/chinadns-ng)
- [17mon/china_ip_list(chnroute.txt 来源)](https://github.com/17mon/china_ip_list)
- [EdgeOS 3.0 概览(Straus Blog)](https://ostrich.kyiv.ua/2025/08/17/overview-of-the-new-edgerouter-os-v3-0/)
