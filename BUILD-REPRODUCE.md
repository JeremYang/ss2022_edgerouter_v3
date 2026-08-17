# sslocal 交叉编译复现说明 (shadowsocks-rust v1.24.0 for mipsel)

本目录 `config/shadowsocks/bin/sslocal` 是 **shadowsocks-rust v1.24.0** 的静态
MIPS32r2 小端二进制,支持 Shadowsocks 2022 (SIP022) 与旧协议,以及 `redir`
(透明代理) 模式。本文档记录完整复现过程(在 macOS x86_64 上完成)。

## 产物

```
$ file sslocal
ELF 32-bit LSB pie executable, MIPS, MIPS32 rel2 version 1 (SYSV), static-pie linked, stripped
$ ls -l sslocal
11523612 bytes (11.5 MB)
$ strings sslocal | grep 2022-blake3
2022-blake3-aes-128-gcm 2022-blake3-aes-256-gcm 2022-blake3-chacha20-poly1305
```

无动态解释器(PT_INTERP 不存在),完全静态;MIPS32r2 指令集,MT7621 (MIPS1004Kc r2) 直接运行。

## 环境

- 主机:macOS 12.7 x86_64(Intel)
- Zig 0.13.0(macOS x86_64,https://ziglang.org/download/0.13.0/zig-macos-x86_64-0.13.0.tar.xz)
  - 作用:交叉 C 编译器 + 链接器(自带 clang/lld/musl libc)
- Rust nightly + `-Z build-std`(因为 `mipsel-unknown-linux-musl` 无预编译 std)
  - rustup 安装 nightly,`rustup component add rust-src`
- musl 1.2.5(mipsel,用 zig 交叉编译,提供 libc.a/crt)

## 步骤

### 1. musl 交叉编译(用 zig)

```sh
./configure --target=mipsel-linux-musl --prefix=$PREFIX/musl-mipsel \
  CC="zig cc -target mipsel-linux-musl" \
  AR="zig ar" RANLIB="zig ranlib"
make -j4 && make install
```

### 2. 自定义 Rust target JSON

```sh
rustc -Z unstable-options --print target-spec-json --target mipsel-unknown-linux-musl \
  > mipsel-unknown-linux-musl.json
```
(新 nightly 已无 `musl-root` 字段;crt/libc 由链接器驱动 zig cc 提供,无需修改 JSON。)

### 3. 链接器包装脚本(关键)

rustc 会给 musl 目标传 `-nodefaultlibs -lgcc_s -Wl,-Bdynamic` 等,与 zig 的静态
musl 不兼容。包装脚本 `mipsel-zig-cc` 做以下归一化:

- 去掉 `--target=*` / `-target` 参数(统一为 `-target mipsel-linux-musl`,
  zig 0.13 不识别 Rust 的 `mipsel-unknown-linux-musl` triple)
- 去掉 `-nodefaultlibs`、`-lgcc_s`、`-Wl,-Bdynamic`
  (让 zig 自己链接 musl libc + compiler-rt + libunwind)
- 追加 `-msoft-float`(MT7621 无 FPU;Rust std 也是 soft-float)
- 追加 `-lunwind`(提供 `_Unwind_*` 符号,std backtrace 需要)

```sh
#!/bin/sh
export ZIG_LOCAL_CACHE_DIR=... ZIG_GLOBAL_CACHE_DIR=...
ZIG=/path/to/zig
out=(); skip=0
for a in "$@"; do
  [ "$skip" = 1 ] && { skip=0; continue; }
  case "$a" in
    --target=*|-target=*) continue ;;
    -target) skip=1; continue ;;
    -Wl,-Bdynamic|-Bdynamic) continue ;;
    -lgcc_s|-nodefaultlibs) continue ;;
    *) out+=("$a") ;;
  esac
done
exec "$ZIG" cc -target mipsel-linux-musl -O2 -static -msoft-float -lunwind "${out[@]}"
```

同样准备 `mipsel-zig-ar` = `zig ar`、`mipsel-zig-ranlib` = `zig ranlib`。

### 4. 编译 shadowsocks-rust

```sh
git clone --branch v1.24.0 https://github.com/shadowsocks/shadowsocks-rust.git
cd shadowsocks-rust

export CC_mipsel_unknown_linux_musl=/path/to/mipsel-zig-cc
export AR_mipsel_unknown_linux_musl=/path/to/mipsel-zig-ar
export RUSTFLAGS="-C linker=/path/to/mipsel-zig-cc -C link-self-contained=no"

cargo +nightly build --release \
  --target mipsel-unknown-linux-musl.json \
  -Z build-std=std,panic_abort \
  -Z json-target-spec \
  --features "local-redir aead-cipher-2022" \
  --bin sslocal
```

产物:`target/mipsel-unknown-linux-musl/release/sslocal`

特性说明:
- `local-redir`:让 `sslocal --protocol redir` 可用(透明代理)
- `aead-cipher-2022`:SIP022 的 2022-blake3-* 密码

## 验证

- `file sslocal` → 静态 MIPS32 rel2
- 无 `PT_INTERP`
- `strings sslocal | grep 2022-blake3` 确认 2022 密码
- 上路由器后第一件事:`/config/shadowsocks/bin/sslocal --version`

## 其他组件说明

- `chinadns-ng`(DNS 组件,**官方预编译**,无需自行编译):
  直接使用官方 release 的 mipsel 静态二进制:
  https://github.com/zfl9/chinadns-ng/releases
  `chinadns-ng@mipsel-linux-musl@mips32+soft_float@fast+lto`(2025.08.09,284KB)
  - 替代旧的 chinadns + pdnsd:`trust-dns tcp://8.8.8.8` 承担 pdnsd 的 TCP-DNS 角色
  - IP 分流用 `ipset-name4 chnroute`(init 脚本从 chnroute.txt 载入 ipset)
  - 说明:项目源码使用 Zig ≤0.10 的协程 API(`@asyncCall`),本地交叉编译需要
    很老的 zig,直接用官方预编译二进制最稳妥
- `chinadns` / `pdnsd`(旧组件):仅当 chinadns-ng 缺失时兜底,沿用原仓库二进制;
  pdnsd 仅需 GLIBC_2.8 符号,EdgeOS 3.0.1 的 glibc 2.24 兼容
- `chnroute.txt`(国内 IP 表):来源 [17mon/china_ip_list](https://github.com/17mon/china_ip_list)
  (IPIP.net 维护),随包提供 2026-08 数据;路由器上可用
  `update-chnroute.sh` 在线更新
