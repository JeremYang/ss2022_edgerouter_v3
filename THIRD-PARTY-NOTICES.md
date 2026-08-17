# 第三方组件许可证声明 (Third-Party Notices)

本项目分发/引用了以下第三方组件。各组件版权归其原作者所有,并各自适用其许可证。
本项目(脚本、文档)采用 MIT 许可证,与下列组件的许可证相互独立。

| 组件 | 版本/来源 | 许可证 | 源码 |
|---|---|---|---|
| `bin/sslocal`(shadowsocks-rust) | v1.24.0,交叉编译(见 BUILD-REPRODUCE.md) | **MIT** | https://github.com/shadowsocks/shadowsocks-rust |
| `bin/chinadns-ng` | 2025.08.09,官方预编译 mipsel 静态二进制 | **AGPL-3.0** | https://github.com/zfl9/chinadns-ng |
| `bin/chinadns`(旧) | 来自 izerosoul/shadowsocks_erx(v1.3.2 修改版) | 原仓库未声明许可证 | https://github.com/izerosoul/shadowsocks_erx |
| `bin/pdnsd`(旧) | pdnsd 1.2.9 | **GPL-2.0** | https://sources.debian.org/src/pdnsd/ |
| `conf/chnroute.txt` | 17mon/china_ip_list 数据(2026-08) | 数据版权归原作者 | https://github.com/17mon/china_ip_list |
| `install.sh` / `etc/init.d/shadowsocks` | 基于 izerosoul/shadowsocks_erx 思路重写 | 本项目 MIT | https://github.com/izerosoul/shadowsocks_erx |

## 说明

1. **chinadns-ng (AGPL-3.0)**:本项目仅分发其官方预编译二进制并保持源码链接;
   本项目的脚本/文档与 chinadns-ng 源码无衍生关系。若你分发修改版 chinadns-ng,
   须遵守 AGPL-3.0(提供修改后的源码)。
2. **旧组件 chinadns / pdnsd**:仅作为 chinadns-ng 缺失时的兜底,建议优先使用 chinadns-ng。
3. **chnroute.txt**:来自 17mon/china_ip_list,仅用于路由器本地 DNS 分流,随包分发时请保留出处。
4. 若你以二进制形式再分发本项目,请一并保留本文件。

## 上游致谢

- 方案思路参考:[izerosoul/shadowsocks_erx](https://github.com/izerosoul/shadowsocks_erx)
- Shadowsocks 2022 协议:[SIP022](https://shadowsocks.org/doc/sip022.html) / [EIH 规范](https://github.com/Shadowsocks-NET/shadowsocks-specs/blob/main/2022-2-shadowsocks-2022-extensible-identity-headers.md)
