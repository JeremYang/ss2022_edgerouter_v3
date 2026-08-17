# ss-erx3 — Shadowsocks 2022 (SIP022) for Ubiquiti EdgeRouter X

> A complete Shadowsocks 2022 client package for the Ubiquiti EdgeRouter X (ER-X).
> Prebuilt static mipsel binaries: **shadowsocks-rust** (SS2022 + transparent proxy)
> and **chinadns-ng** (DNS anti-pollution). Works on EdgeOS **3.0.x (systemd)** and 1.x/2.x.

[中文版 README](./README.md)

## Features

- **Shadowsocks 2022 (SIP022)**: `2022-blake3-aes-128/256-gcm` and `2022-blake3-chacha20-poly1305`, resistant to active probing
- **Transparent proxy**: iptables REDIRECT — every device on the LAN proxies automatically (TCP)
- **SOCKS5 proxy**: `192.168.1.1:1080` (with UDP relay)
- **DNS anti-pollution**: chinadns-ng splits traffic by China IP ranges; foreign domains resolve via TCP DNS through the SS tunnel
- **One-command install**: `install.sh`; auto-start via systemd unit (EdgeOS 3.x) / rc.local + post-config.d
- **Updatable China IP list**: `update-chnroute.sh` (source: 17mon/china_ip_list)

## Layout

```
ss-erx3/
├── install.sh                              # interactive install script
├── UPGRADE-GUIDE.md                        # full guide (firmware upgrade / server setup / troubleshooting)
├── BUILD-REPRODUCE.md                      # cross-compilation how-to
├── THIRD-PARTY-NOTICES.md                  # component licenses
├── LICENSE                                 # MIT
├── etc/init.d/shadowsocks                  # service script
├── etc/systemd/system/shadowsocks.service  # systemd unit (EdgeOS 3.x)
└── config/shadowsocks/
    ├── bin/  sslocal · chinadns-ng · chinadns · pdnsd · update-chnroute.sh · ss-monitor.sh
    └── conf/ shadowsocks.json.example · chinadns-ng.conf · pdnsd.conf · chnroute.txt
```

## Quick Start

```bash
# 1) upload to the router
scp -r ss-erx3 admin@192.168.51.1:/tmp/

# 2) ssh to the router and run
cd /tmp/ss-erx3
sudo bash install.sh
```

### ⚠️ Read this first (summary of hard-won lessons, details in UPGRADE-GUIDE.md)

1. **Your server must support 2022**: shadowsocks-rust / sing-box / xray (**3X-UI**). shadowsocks-libev does **not** support it.
2. **xray / 3X-UI servers only support `2022-blake3-aes-128/256-gcm`** — not the chacha20-poly1305 variant. Use **aes-256-gcm** on both sides.
3. **Key format**: with xray multi-user (multiple 3X-UI Clients), the router config MUST use the **`clientA-key:clientB-key`** dual-key format (EIH requirement). A single key will connect and immediately drop.
4. **After install, DHCP must hand out the router itself (LAN IP) as client DNS**, otherwise client DNS gets poisoned and the transparent proxy times out on foreign sites:
   ```
   configure
   set service dhcp-server shared-network-name LAN subnet 192.168.51.0/24 dns-server 192.168.51.1
   commit && save
   ```
   Clients then reconnect Wi-Fi / run `ipconfig /renew`.

### Verify

```bash
curl -x socks5h://127.0.0.1:1080 -I https://www.google.com   # tunnel (expect 200)
dig @192.168.51.1 www.google.com                              # client DNS (real IP)
```

## Daily Use

```bash
sudo systemctl status/restart/stop shadowsocks   # EdgeOS 3.x (systemd)
sudo /etc/init.d/shadowsocks status              # compatible (redirects to systemctl)
```

Optional self-healing (check every 5 min, auto-restart on failure):
```
*/5 * * * * sh /config/shadowsocks/bin/ss-monitor.sh
```

Update the China IP list:
```bash
sudo sh /config/shadowsocks/bin/update-chnroute.sh
```

## Docs

- [UPGRADE-GUIDE.md](./UPGRADE-GUIDE.md) — complete guide from EdgeOS 1.10.11 to 3.0.1 + SS2022: firmware upgrade, server setup, key format, DHCP DNS, troubleshooting (includes real-world pitfalls)
- [BUILD-REPRODUCE.md](./BUILD-REPRODUCE.md) — full cross-compilation of sslocal / chinadns-ng for mipsel (Zig + Rust build-std)

## License & Credits

- This project's code (scripts, docs): **MIT** — see [LICENSE](./LICENSE)
- Third-party binaries keep their own licenses — see [THIRD-PARTY-NOTICES.md](./THIRD-PARTY-NOTICES.md)
- Install/service scripts are rewritten based on [izerosoul/shadowsocks_erx](https://github.com/izerosoul/shadowsocks_erx) — many thanks
- Upstream projects: [shadowsocks-rust](https://github.com/shadowsocks/shadowsocks-rust) · [chinadns-ng](https://github.com/zfl9/chinadns-ng) · [17mon/china_ip_list](https://github.com/17mon/china_ip_list)

## Disclaimer

For technical study and communication only. Users are responsible for complying with local laws and regulations.
