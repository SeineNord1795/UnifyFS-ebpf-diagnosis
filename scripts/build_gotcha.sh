#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# build_gotcha.sh
# - Debug + eBPF friendly
# - 健壮化处理，支持自动更新源码
# ============================================================

# -----------------------------
# 可调参数（环境变量可覆盖）
# -----------------------------
REPO_URL="${REPO_URL:-https://github.com/SeineNord1795/GOTCHA.git}"
WORK_DIR="${WORK_DIR:-$HOME/GOTCHA}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/unifyfs/stack/gcc-debug}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build-gcc-debug}"
UPDATE_REPO="${UPDATE_REPO:-1}"
JOBS="${JOBS:-$(nproc)}"

# -----------------------------
# 工具函数
# -----------------------------
log()  { echo -e "\033[1;32m[build_gotcha]\033[0m $*"; }
die()  { echo -e "\033[1;31m[build_gotcha][FATAL]\033[0m $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "找不到命令：$1"; }

# -----------------------------
# 前置检查
# -----------------------------
need_cmd git
need_cmd cmake
need_cmd make
need_cmd pkg-config

log "REPO_URL      = $REPO_URL"
log "WORK_DIR      = $WORK_DIR"
log "BUILD_DIR     = $BUILD_DIR"
log "INSTALL_DIR   = $INSTALL_DIR"
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
        git -C "$WORK_DIR" fetch --all --prune
        git -C "$WORK_DIR" pull --rebase
    else
        log "跳过源码更新"
    fi
fi

# -----------------------------
# 环境变量配置
# -----------------------------
export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig:$INSTALL_DIR/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib64:${LD_LIBRARY_PATH:-}"

# Debug + eBPF 友好
export CFLAGS="-O0 -g -fno-omit-frame-pointer"
export CXXFLAGS="-O0 -g -fno-omit-frame-pointer"

# -----------------------------
# 构建目录 & 构建
# -----------------------------
log "准备构建目录（清空重建）：$BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

log "配置 CMake..."
CMAKE_ARGS=(
    "-DCMAKE_INSTALL_PREFIX=$INSTALL_DIR"
    "-DCMAKE_BUILD_TYPE=Debug"
    "-DCMAKE_C_FLAGS=$CFLAGS"
    "-DCMAKE_CXX_FLAGS=$CXXFLAGS"
    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
)

cmake "$WORK_DIR" "${CMAKE_ARGS[@]}"

log "开始构建（make -j$JOBS）"
make -j"$JOBS"

log "开始安装（make install）"
make install

# -----------------------------
# 安装验证
# -----------------------------
log "验证安装结果"
if [[ -f "$INSTALL_DIR/lib/libgotcha.so" || -f "$INSTALL_DIR/lib64/libgotcha.so" ]]; then
    log "GOTCHA 安装成功到 $INSTALL_DIR"
else
    die "安装失败：未找到 libgotcha.so"
fi