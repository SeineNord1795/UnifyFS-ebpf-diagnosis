#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# build_libfabric.sh
# - Debug + eBPF friendly
# - 健壮化处理，支持自动更新源码
# ============================================================

# -----------------------------
# 可调参数（环境变量覆盖）
# -----------------------------
REPO_URL="${REPO_URL:-https://github.com/ofiwg/libfabric.git}"
WORK_DIR="${WORK_DIR:-$HOME/libfabric}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/unifyfs/stack/gcc-debug}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build-gcc-debug}"
LIBFABRIC_REF="${LIBFABRIC_REF:-}"    # 可选 tag/branch/commit
LIBFABRIC_PROVIDER_MODE="${LIBFABRIC_PROVIDER_MODE:-yes}"  # yes 或 dl
UPDATE_REPO="${UPDATE_REPO:-1}"
JOBS="${JOBS:-$(nproc)}"

# -----------------------------
# 工具函数
# -----------------------------
log()  { echo -e "\033[1;32m[build_libfabric]\033[0m $*"; }
die()  { echo -e "\033[1;31m[build_libfabric][FATAL]\033[0m $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "找不到命令：$1"; }

# -----------------------------
# 前置检查
# -----------------------------
need_cmd git
need_cmd autoreconf
need_cmd make
need_cmd pkg-config

log "REPO_URL      = $REPO_URL"
log "WORK_DIR      = $WORK_DIR"
log "BUILD_DIR     = $BUILD_DIR"
log "INSTALL_DIR   = $INSTALL_DIR"
log "LIBFABRIC_REF = ${LIBFABRIC_REF:-'默认最新'}"
log "PROVIDER_MODE = $LIBFABRIC_PROVIDER_MODE"
log "UPDATE_REPO   = $UPDATE_REPO"
log "JOBS          = $JOBS"

mkdir -p "$INSTALL_DIR"

# -----------------------------
# 下载/更新源码
# -----------------------------
if [[ ! -d "$WORK_DIR/.git" ]]; then
    log "未检测到源码目录，克隆：$REPO_URL -> $WORK_DIR"
    git clone "$REPO_URL" "$WORK_DIR"
else
    log "检测到已有源码目录：$WORK_DIR"
    if [[ "$UPDATE_REPO" == "1" ]]; then
        log "更新源码"
        git -C "$WORK_DIR" fetch --all --tags
        git -C "$WORK_DIR" pull --rebase
    else
        log "跳过源码更新"
    fi
fi

if [[ -n "$LIBFABRIC_REF" ]]; then
    log "切换到指定版本/分支/commit: $LIBFABRIC_REF"
    git -C "$WORK_DIR" checkout "$LIBFABRIC_REF"
fi

# -----------------------------
# 环境变量配置
# -----------------------------
export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig:$INSTALL_DIR/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib64:${LD_LIBRARY_PATH:-}"

export CFLAGS="${CFLAGS:-} -O0 -g3 -ggdb3 -fno-omit-frame-pointer -fno-optimize-sibling-calls"
export CXXFLAGS="${CXXFLAGS:-} -O0 -g3 -ggdb3 -fno-omit-frame-pointer -fno-optimize-sibling-calls"
export LDFLAGS="${LDFLAGS:-} -Wl,--build-id -rdynamic"

# -----------------------------
# autogen + 构建目录
# -----------------------------
log "运行 autogen.sh"
cd "$WORK_DIR"
./autogen.sh

log "准备构建目录（清空重建）：$BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# -----------------------------
# 配置 + 构建
# -----------------------------
log "配置 libfabric (Debug + providers: tcp/udp/rxm/shm ; disable sockets ; mode=$LIBFABRIC_PROVIDER_MODE)"
"$WORK_DIR/configure" \
    --prefix="$INSTALL_DIR" \
    --enable-debug \
    --disable-static \
    --enable-sockets=no \
    --enable-tcp="$LIBFABRIC_PROVIDER_MODE" \
    --enable-udp="$LIBFABRIC_PROVIDER_MODE" \
    --enable-rxm="$LIBFABRIC_PROVIDER_MODE" \
    --enable-shm="$LIBFABRIC_PROVIDER_MODE"

log "make -j$JOBS"
make -j"$JOBS"

log "make install -> $INSTALL_DIR"
make install

# -----------------------------
# 安装验证
# -----------------------------
log "验证安装"
test -f "$INSTALL_DIR/include/rdma/fabric.h" && echo "  OK: include/rdma/fabric.h"
test -f "$INSTALL_DIR/bin/fi_info" && echo "  OK: bin/fi_info"

if [[ -x "$INSTALL_DIR/bin/fi_info" ]]; then
    log "fi_info: 列出可用 provider（过滤 tcp/udp/shm/rxm）"
    "$INSTALL_DIR/bin/fi_info" -l 2>/dev/null | egrep -i "tcp|udp|shm|rxm" || true
fi

log "libfabric 构建和安装完成！"