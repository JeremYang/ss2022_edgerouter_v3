#!/bin/sh
# /config/scripts/post-config.d/50-ss-rules.sh
# EdgeOS 每次 commit / 开机后运行;重挂被 commit 清掉的 iptables 规则。
# SYSTEMCTL_SKIP_REDIRECT=1:绕过 40-systemd 钩子直接执行 init 脚本
# (否则会被重定向成 systemctl start,对已 active 的 oneshot 单元是空操作,
#  规则不会被重新挂上)。

[ -x /config/shadowsocks/bin/sslocal ] || exit 0
[ -f /config/shadowsocks/conf/shadowsocks.json ] || exit 0

# 显式 stop 后(标记文件存在)不自动拉起
[ -f /tmp/ss-manually-stopped ] && exit 0

# EdgeOS 3.x(systemd):服务处于非 active 状态时不拉起
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
	systemctl is-active --quiet shadowsocks || exit 0
fi

SYSTEMCTL_SKIP_REDIRECT=1 /etc/init.d/shadowsocks start >/dev/null 2>&1

exit 0
