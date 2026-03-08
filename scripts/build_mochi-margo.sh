#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# 可调参数（按需改）
# -----------------------------
REPO_URL="https://github.com/SeineNord1795/mochi-margo.git"
WORK_DIR="$HOME/mochi-margo"
INSTALL_DIR="$HOME/.local/unifyfs/stack/gcc-debug"
BUILD_DIR="$WORK_DIR/build-gcc-debug"

UPDATE_REPO="${UPDATE_REPO:-1}"
JOBS="${JOBS:-$(nproc)}"

# -----------------------------
# 小工具函数
# -----------------------------
log() { echo -e "\033[1;32m[build_margo]\033[0m $*"; }
die() { echo -e "\033[1;31m[build_margo][FATAL]\033[0m $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "找不到命令：$1"
}

# -----------------------------
# 前置检查
# -----------------------------
need_cmd git
need_cmd cmake
need_cmd make
need_cmd pkg-config

log "WORK_DIR    = $WORK_DIR"
log "BUILD_DIR   = $BUILD_DIR"
log "INSTALL_DIR = $INSTALL_DIR"
log "JOBS        = $JOBS"

mkdir -p "$INSTALL_DIR"

# -----------------------------
# 下载或更新源码
# -----------------------------
if [[ ! -d "$WORK_DIR/.git" ]]; then
  log "克隆仓库..."
  git clone "$REPO_URL" "$WORK_DIR"
else
  log "检测到已有源码"
  if [[ "$UPDATE_REPO" == "1" ]]; then
    git -C "$WORK_DIR" pull --rebase
  else
    log "跳过更新"
  fi
fi

# -----------------------------
# 关键部分：让 CMake 找到你手动安装的依赖
# -----------------------------
export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig:$INSTALL_DIR/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export CMAKE_PREFIX_PATH="$INSTALL_DIR:${CMAKE_PREFIX_PATH:-}"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib64:${LD_LIBRARY_PATH:-}"

log "PKG_CONFIG_PATH = $PKG_CONFIG_PATH"
log "CMAKE_PREFIX_PATH = $CMAKE_PREFIX_PATH"

# -----------------------------
# 配置构建
# -----------------------------
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

log "CMake 配置（Debug + eBPF 友好）"

cmake "$WORK_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_SHARED_LIBS=ON \
  -DENABLE_TESTS=OFF \
  -DMARGO_EBPF_FRIENDLY=ON \
  -DMARGO_FORCE_NO_OPTIMIZATION=ON

log "开始编译"
make -j"$JOBS"

log "安装"
make install

# -----------------------------
# 简单验证
# -----------------------------
log "检查安装结果"
if [[ -d "$INSTALL_DIR/lib" ]]; then
  ls "$INSTALL_DIR/lib" | grep margo || true
fi

log "完成：mochi-margo 安装到 $INSTALL_DIR"