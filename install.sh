#!/bin/bash
# install.sh - shadowsocks (Shadowsocks 2022 / SIP022) for EdgeRouter X
# Client: shadowsocks-rust sslocal (statically linked mipsel; supports both
#         SIP022 2022 ciphers and the legacy protocol).
# Adapted for EdgeOS 3.0.x (kernel 4.14.54-UBNT, Debian 9 userland,
# iptables-legacy). Also works on EdgeOS 1.x/2.x.
#
# Usage: copy this whole directory to /tmp on the router, then:
#   sudo bash install.sh
set -e

# ---------------------------------------------------------------------------
# 1. Collect configuration
# ---------------------------------------------------------------------------
echo "Please input your shadowsocks 2022 configuration step by step."
echo "Just press ENTER if you use default config."
echo
read -p "server address (default: changeme.fuckgfw.com):" ss_server
[ -z "${ss_server}" ] && ss_server="changeme.fuckgfw.com"
read -p "server port (default: 8388):" ss_port
[ -z "${ss_port}" ] && ss_port="8388"

echo
echo "Shadowsocks 2022 (SIP022) methods:"
echo "  1) 2022-blake3-chacha20-poly1305  (only if server is shadowsocks-rust/sing-box;"
echo "                                     xray/3X-UI 服务端不支持此方法!)"
echo "  2) 2022-blake3-aes-128-gcm        (16-byte key, software AES slower on MIPS)"
echo "  3) 2022-blake3-aes-256-gcm        (32-byte key, xray/3X-UI 服务端选这个)"
echo "  4) legacy: chacha20-ietf-poly1305 (old protocol, for transition only)"
echo
echo ">>> 如果你的 VPS 是 3X-UI/xray,请选 3 (aes-256-gcm);"
echo ">>> 服务端是 shadowsocks-rust 才选 1 (chacha20-poly1305)。"
read -p "method number (default: 1):" ss_method_no
case "${ss_method_no:-1}" in
  2) ss_method="2022-blake3-aes-128-gcm" ;;
  3) ss_method="2022-blake3-aes-256-gcm" ;;
  4) ss_method="chacha20-ietf-poly1305" ;;
  *) ss_method="2022-blake3-chacha20-poly1305" ;;
esac

# For 2022 methods the password MUST be a base64-encoded fixed-size PSK.
if [ "$ss_method" != "chacha20-ietf-poly1305" ]; then
  case "$ss_method" in
    *aes-128-gcm) keylen=16 ;;
    *)            keylen=32 ;;
  esac
  echo
  echo "For method '$ss_method' the password must be base64 of exactly $keylen bytes."
  echo "Generate one locally:  openssl rand -base64 $keylen"
  read -p "password (base64 PSK):" ss_password
  if [ -z "$ss_password" ]; then
    echo "ERROR: password required for 2022 methods." >&2
    exit 1
  fi
  # 双密钥格式 "身份密钥:主密钥"(3X-UI/xray 多用户,EIH 要求):
  # 跳过整体长度校验,每个部分由 shadowsocks-rust 自行校验
  if echo "$ss_password" | grep -q ':'; then
    echo "dual-key format detected (identity:main), skip length check"
  else
    decoded_len=$(echo -n "$ss_password" | base64 -d 2>/dev/null | wc -c)
    if ! echo -n "$ss_password" | base64 -d >/dev/null 2>&1; then
      decoded_len=$(echo -n "$ss_password" | openssl base64 -d -A 2>/dev/null | wc -c)
    fi
    if [ "$decoded_len" != "$keylen" ]; then
      echo "WARNING: decoded key length is $decoded_len bytes, expected $keylen."
      echo "The server will reject a mismatched key."
    fi
  fi
else
  read -p "password (default: ss_password):" ss_password
  [ -z "${ss_password}" ] && ss_password="ss_password"
fi

echo
echo "Please input your ISP dns or public dns you want to use"
read -p "(default: 114.114.114.114):" public_dns
[ -z "${public_dns}" ] && public_dns="114.114.114.114"
echo
echo "---------------------------"
echo "ss_server= $ss_server"
echo "ss_port= $ss_port"
echo "ss_method= $ss_method"
echo "password= ${ss_password:0:8}... (masked)"
echo "public_dns= $public_dns"
echo "---------------------------"
echo

# ---------------------------------------------------------------------------
# 2. Write shadowsocks.json into /config (survives firmware upgrades, backed up
#    with config backups)
# ---------------------------------------------------------------------------
mkdir -p /config/shadowsocks/conf
cat > /config/shadowsocks/conf/shadowsocks.json <<-EOF
{
    "server":"$ss_server",
    "server_port":$ss_port,
    "local_address":"0.0.0.0",
    "local_port":1080,
    "password":"$ss_password",
    "timeout":300,
    "method":"$ss_method"
}
EOF
echo "write /config/shadowsocks/conf/shadowsocks.json success"

# ---------------------------------------------------------------------------
# 3. Copy binaries / init script
#   平台自动识别:
#     uname -m = mips   → ER-X / ER-X-SFP / EP-R6 / ER-10X(MIPS32 小端)
#     uname -m = mips64 → ER-4 / ER-6P / ER-12 / ER-12P(Octeon MIPS64 内核,
#                         o32 大端用户空间 → 使用 mips 大端二进制)
# ---------------------------------------------------------------------------
BINDIR=$(dirname "$0")/config/shadowsocks/bin
ARCH_MACHINE=$(uname -m)
case "$ARCH_MACHINE" in
  mips)   SS_ARCH=mipsel ;;
  mips64) SS_ARCH=mips ;;
  *)
    echo "ERROR: unsupported architecture: $ARCH_MACHINE (expect mips or mips64)" >&2
    exit 1
    ;;
esac
echo "platform: $ARCH_MACHINE -> binaries: .$SS_ARCH"

mkdir -p /config/shadowsocks/bin
cp -f "$BINDIR"/sslocal.$SS_ARCH /config/shadowsocks/bin/sslocal
cp -f "$BINDIR"/chinadns-ng.$SS_ARCH /config/shadowsocks/bin/chinadns-ng 2>/dev/null || true
# 旧版兜底组件(chinadns/pdnsd)仅 mipsel 平台提供
cp -f "$BINDIR"/chinadns.$SS_ARCH "$BINDIR"/pdnsd.$SS_ARCH /config/shadowsocks/bin/ 2>/dev/null || true
cp -f "$BINDIR"/ss-monitor.sh "$BINDIR"/update-chnroute.sh /config/shadowsocks/bin/
cp -f "$BINDIR"/ss-ctl /config/shadowsocks/bin/ 2>/dev/null || true
chmod 755 /config/shadowsocks/bin/*

# ss-ctl 快捷方式:可见走马灯输出控制服务(sudo ss-start / ss-stop / ...)
mkdir -p /usr/bin
for a in start stop restart status; do
  ln -sf /config/shadowsocks/bin/ss-ctl /usr/bin/ss-$a
done
cp -f "$(dirname "$0")/config/shadowsocks/conf/pdnsd.conf" /config/shadowsocks/conf/
cp -f "$(dirname "$0")/config/shadowsocks/conf/chinadns-ng.conf" /config/shadowsocks/conf/
cp -f "$(dirname "$0")/config/shadowsocks/conf/chnroute.txt" /config/shadowsocks/conf/ 2>/dev/null || true
chmod 755 /config/shadowsocks/bin/*

# init script
sed "s/ISPDNS=114.114.114.114/ISPDNS=$public_dns/" "$(dirname "$0")/etc/init.d/shadowsocks" > /etc/init.d/shadowsocks
chmod 755 /etc/init.d/shadowsocks
echo "copy files ok"

# ---------------------------------------------------------------------------
# 4. DNS: point dnsmasq at chinadns via the vyatta config tree (persists in
#    config.boot, survives reboots AND config commits - unlike editing
#    /etc/dnsmasq.conf which vyatta regenerates)
# ---------------------------------------------------------------------------
VYATTA_CFG=/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper
if [ -x "$VYATTA_CFG" ]; then
  echo "setting service dns forwarding options via config tree"
  "$VYATTA_CFG" begin
  "$VYATTA_CFG" set service dns forwarding options "server=127.0.0.1#5301"
  "$VYATTA_CFG" set service dns forwarding options "no-resolv"
  "$VYATTA_CFG" commit
  "$VYATTA_CFG" save
else
  echo "vyatta-cfg-cmd-wrapper not found; falling back to direct dnsmasq edit"
  dnscfg=/etc/dnsmasq.conf
  [ 0 == `grep "^log-facility" $dnscfg|wc -l` ] && echo log-facility=/var/log/dnsmasq.log >> $dnscfg
  [ 0 == `grep "^cache-size" $dnscfg|wc -l` ] && echo cache-size=1000 >> $dnscfg
  [ 0 == `grep "^no-resolv" $dnscfg|wc -l` ] && echo no-resolv >> $dnscfg
  [ 0 == `grep "^server" $dnscfg|wc -l` ] && echo server=127.0.0.1#5301 >> $dnscfg
  /etc/init.d/dnsmasq restart
fi

# ---------------------------------------------------------------------------
# 5. Auto-start on boot: EdgeOS-native post-config.d (runs at boot and after
#    every commit; re-adds iptables rules that commits may wipe)
# ---------------------------------------------------------------------------
mkdir -p /config/scripts/post-config.d
cp -f "$(dirname "$0")/config/scripts/post-config.d/50-ss-rules.sh" /config/scripts/post-config.d/
chmod +x /config/scripts/post-config.d/50-ss-rules.sh

# also keep /etc/rc.local entry as a belt-and-braces fallback
sed -i "s/^exit 0//" /etc/rc.local
[ 0 == `grep shadowsocks /etc/rc.local|wc -l` ] && echo /etc/init.d/shadowsocks start >> /etc/rc.local
echo exit 0 >> /etc/rc.local
echo "auto start ok"

# ---------------------------------------------------------------------------
# 6. Start service
#    EdgeOS 3.x boots systemd (PID1); /etc/init.d/* start is auto-redirected
#    to systemctl via /lib/lsb/init-functions.d/40-systemd, so we must create
#    the systemd unit. EdgeOS 1.x/2.x use sysvinit - run the script directly.
# ---------------------------------------------------------------------------
if [ -d /run/systemd/system ]; then
  echo "systemd detected, installing shadowsocks.service"
  mkdir -p /etc/systemd/system
  cp -f "$(dirname "$0")/etc/systemd/system/shadowsocks.service" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable shadowsocks >/dev/null 2>&1 || true
  systemctl restart shadowsocks 2>/dev/null || systemctl start shadowsocks
else
  [ `/etc/init.d/shadowsocks status|grep "is running"|wc -l` -gt 0 ] && /etc/init.d/shadowsocks stop
  /etc/init.d/shadowsocks start
fi

echo
echo "Installation done."
echo "If this is a Shadowsocks 2022 upgrade, make sure your VPS server also"
echo "runs a 2022-capable server (shadowsocks-rust / sing-box / xray) with the"
echo "SAME method and base64 password."
echo "Socks5 proxy: 127.0.0.1:1080 | transparent proxy: tcp via 1081"
