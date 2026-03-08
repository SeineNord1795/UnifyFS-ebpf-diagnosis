#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# 可调参数（按需改）
# -----------------------------
REPO_URL="hhttps://github.com/SeineNord1795/spath.git"
WORK_DIR="$HOME/spath"
INSTALL_DIR="$HOME/.local/unifyfs/stack/gcc-debug"
BUILD_DIR="$WORK_DIR/build-gcc-debug"

# 是否更新源码：1=更新(默认) 0=不更新
UPDATE_REPO="${UPDATE_REPO:-1}"

# 并行编译线程数：默认用全部核心
JOBS="${JOBS:-$(nproc)}"

# -----------------------------
# 小工具函数
# -----------------------------
log() { echo -e "\033[1;32m[build_spath]\033[0m $*"; }
die() { echo -e "\033[1;31m[build_spath][FATAL]\033[0m $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "找不到命令：$1（请先安装）"
}

# -----------------------------
# 前置检查
# -----------------------------
need_cmd git
need_cmd cmake
need_cmd make

log "WORK_DIR      = $WORK_DIR"
log "BUILD_DIR     = $BUILD_DIR"
log "INSTALL_DIR   = $INSTALL_DIR"
log "UPDATE_REPO   = $UPDATE_REPO"
log "JOBS          = $JOBS"

mkdir -p "$INSTALL_DIR"

# -----------------------------
# 下载 / 更新源码
# -----------------------------
if [[ ! -d "$WORK_DIR/.git" ]]; then
  log "未检测到源码目录，开始克隆：$REPO_URL"
  git clone "$REPO_URL" "$WORK_DIR"
else
  log "检测到已有源码目录：$WORK_DIR"
  if [[ "$UPDATE_REPO" == "1" ]]; then
    log "更新源码（git pull）"
    git -C "$WORK_DIR" fetch --all --prune
    git -C "$WORK_DIR" pull --rebase
  else
    log "跳过源码更新（UPDATE_REPO=0）"
  fi
fi

# -----------------------------
# 配置 & 构建 & 安装
# -----------------------------
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

log "配置 CMake（Debug + eBPF/Tracing 友好）"
cmake "$WORK_DIR" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_SHARED_LIBS=ON \
  -DMPI=ON \
  -DENABLE_TESTS=OFF \
  -DSPATH_EBPF_FRIENDLY:BOOL=ON

log "开始编译（make -j$JOBS）"
make -j"$JOBS"

log "开始安装（make install）"
make install

# -----------------------------
# 简单验证
# -----------------------------
log "验证安装结果"
if [[ -d "$INSTALL_DIR/lib" ]]; then
  ls -lah "$INSTALL_DIR/lib" | grep -E "spath" || true
fi
if [[ -d "$INSTALL_DIR/lib64" ]]; then
  ls -lah "$INSTALL_DIR/lib64" | grep -E "spath" || true
fi

if [[ -d "$INSTALL_DIR/include" ]]; then
  ls -lah "$INSTALL_DIR/include" | grep -E "spath" || true
fi

log "完成：spath 已安装到 $INSTALL_DIR"