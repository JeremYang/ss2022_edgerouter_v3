#!/bin/sh
# /config/shadowsocks/bin/update-chnroute.sh
# 从 17mon/china_ip_list(IPIP.net 维护)更新 chnroute.txt(国内 IP 段表)。
#
# 用法(路由器上):
#   sudo sh /config/shadowsocks/bin/update-chnroute.sh
# 可加进 crontab 定期更新,例如每周一 03:00:
#   0 3 * * 1 sh /config/shadowsocks/bin/update-chnroute.sh >> /var/log/chnroute_update.log 2>&1
#
# 说明:路由器自身的 curl 会走 SS 透明代理(OUTPUT 链),SS 正常时可直接访问 GitHub。

URL="https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt"
# 备用镜像(17mon 原站)
URL2="https://raw.githubusercontent.com/gaoyifan/china-operator-ip/ip-lists/china.txt"
TMP=/tmp/chnroute.txt.new
CHNROUTE=/config/shadowsocks/conf/chnroute.txt

fetch() {
	curl -fsSL --connect-timeout 10 --max-time 120 -o "$TMP" "$1" 2>/dev/null
}

if ! fetch "$URL"; then
	echo "[$(date '+%F %T')] primary source failed, trying backup..."
	fetch "$URL2" || { echo "[$(date '+%F %T')] both sources failed, keep old list"; exit 1; }
fi

# 校验:必须是纯 CIDR 列表且不少于 1000 条,防止抓到错误内容
N=$(grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$' "$TMP")
if [ "$N" -lt 1000 ]; then
	echo "[$(date '+%F %T')] invalid list ($N entries), keep old list"
	exit 1
fi

cp "$TMP" "$CHNROUTE"
echo "[$(date '+%F %T')] chnroute.txt updated: $N entries"

# 重载:重建 chinadns-ng 用的 chnroute ipset 并重启 DNS 相关服务
if [ -x /config/shadowsocks/bin/chinadns-ng ]; then
	/etc/init.d/shadowsocks restart
fi

exit 0
