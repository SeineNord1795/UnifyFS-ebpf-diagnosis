#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# build_mercury.txt (merged)
# - 默认启用 OFI (libfabric) + SM
# - Debug + -O0 + frame pointer：方便 eBPF/火焰图/栈回溯
# - 统一一个脚本：不再需要先跑 build_mercury.txt 再跑 build_mercury_ofi.txt
# ============================================================

# -----------------------------
# 可调参数（按需改 / 支持环境变量覆盖）
# -----------------------------
REPO_URL="${REPO_URL:-https://github.com/SeineNord1795/mercury.git}"
WORK_DIR="${WORK_DIR:-$HOME/mercury}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/unifyfs/stack/gcc-debug}"

# 构建目录（默认会清空重建，保证干净）
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build-gcc-debug}"

# 是否更新源码：1=更新(默认) 0=不更新
UPDATE_REPO="${UPDATE_REPO:-1}"

# 并行编译线程数：默认用全部核心
JOBS="${JOBS:-$(nproc)}"

# 是否启用 OFI（默认开启；设为 0 则不走 libfabric/OFI）
ENABLE_OFI="${ENABLE_OFI:-1}"

# -----------------------------
# 小工具函数
# -----------------------------
log() { echo -e "\033[1;32m[build_mercury]\033[0m $*"; }
die() { echo -e "\033[1;31m[build_mercury][FATAL]\033[0m $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "找不到命令：$1（请先安装）"; }

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
log "ENABLE_OFI    = $ENABLE_OFI"

mkdir -p "$INSTALL_DIR"

# -----------------------------
# 1) 下载 / 更新源码（带 submodule）
# -----------------------------
if [[ ! -d "$WORK_DIR/.git" ]]; then
  log "未检测到源码目录，开始克隆：$REPO_URL -> $WORK_DIR"
  git clone --recurse-submodules "$REPO_URL" "$WORK_DIR"
else
  log "检测到已有源码目录：$WORK_DIR"
  if [[ "$UPDATE_REPO" == "1" ]]; then
    log "更新源码（git fetch/pull + submodule update）"
    git -C "$WORK_DIR" fetch --all --prune
    git -C "$WORK_DIR" pull --rebase
    git -C "$WORK_DIR" submodule update --init --recursive
  else
    log "跳过源码更新（UPDATE_REPO=0）"
  fi
fi

# -----------------------------
# 2) OFI 模式下：硬检查 libfabric 是否存在
# -----------------------------
if [[ "$ENABLE_OFI" == "1" ]]; then
  if [[ ! -e "$INSTALL_DIR/lib64/libfabric.so" && ! -e "$INSTALL_DIR/lib/libfabric.so" ]]; then
    die "ENABLE_OFI=1 但在 $INSTALL_DIR 下没找到 libfabric.so（请先构建/安装 libfabric 到同一 prefix）"
  fi
fi

# -----------------------------
# 3) 环境：让 CMake / pkg-config 能找到依赖
# -----------------------------
export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig:$INSTALL_DIR/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib64:${LD_LIBRARY_PATH:-}"

# Debug + eBPF 友好：保留帧指针，禁用优化，保留符号
CFLAGS="-O0 -g -fno-omit-frame-pointer"
CXXFLAGS="-O0 -g -fno-omit-frame-pointer"

# -----------------------------
# 4) 配置 & 构建 & 安装
# -----------------------------
log "准备构建目录（清空重建）：$BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 统一的 CMake 选项：基础 Debug + 你的自定义开关
CMAKE_ARGS=(
  "-DCMAKE_INSTALL_PREFIX=$INSTALL_DIR"
  "-DCMAKE_PREFIX_PATH=$INSTALL_DIR"
  "-DCMAKE_BUILD_TYPE=Debug"
  "-DBUILD_SHARED_LIBS=ON"
  "-DCMAKE_C_FLAGS=$CFLAGS"
  "-DCMAKE_CXX_FLAGS=$CXXFLAGS"

  # 你原脚本里的“eBPF/Tracing 友好”与自定义开关
  "-DMERCURY_USE_SELF_FORWARD:BOOL=ON"
  "-DMERCURY_USE_BOOST_PP:BOOL=ON"
  "-DMERCURY_EBPF_FRIENDLY:BOOL=ON"

  # 共享内存通道（本机 client<->server 很常用）
  "-DMERCURY_USE_SM=ON"
  "-DNA_USE_SM=ON"
)

# OFI（libfabric）开关：只在 ENABLE_OFI=1 时追加
if [[ "$ENABLE_OFI" == "1" ]]; then
  CMAKE_ARGS+=(
    "-DMERCURY_USE_OFI=ON"
    "-DNA_USE_OFI=ON"
    "-DENABLE_NA_OFI=ON"
    "-DMERCURY_NA_OFI=ON"

    # 给 find_package / find_library 一点“暗示”
    "-DLIBFABRIC_ROOT=$INSTALL_DIR"
    "-Dlibfabric_DIR=$INSTALL_DIR"
    "-DFABRIC_ROOT=$INSTALL_DIR"
  )
else
  CMAKE_ARGS+=(
    "-DMERCURY_USE_OFI=OFF"
    "-DNA_USE_OFI=OFF"
  )
fi

log "配置 CMake"
cmake "$WORK_DIR" "${CMAKE_ARGS[@]}"

log "开始编译（make -j$JOBS）"
make -j"$JOBS"

log "开始安装（make install）"
make install

# -----------------------------
# 5) 简单验证（OFI/SM 宏是否生效）
# -----------------------------
log "验证安装结果（库文件）"
if [[ -d "$INSTALL_DIR/lib" ]]; then
  ls -lah "$INSTALL_DIR/lib" | grep -E "mercury|hg|na" || true
fi
if [[ -d "$INSTALL_DIR/lib64" ]]; then
  ls -lah "$INSTALL_DIR/lib64" | grep -E "mercury|hg|na" || true
fi

if [[ -f "$INSTALL_DIR/include/na_config.h" ]]; then
  log "验证 na_config.h（NA_HAS_*）"
  grep -nE 'NA_HAS_(OFI|BMI|SM)' "$INSTALL_DIR/include/na_config.h" || true
else
  log "未找到 $INSTALL_DIR/include/na_config.h（不同版本安装路径可能不同），跳过宏检查"
fi

log "完成：Mercury 已安装到 $INSTALL_DIR"