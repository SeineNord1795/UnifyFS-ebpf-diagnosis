#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# install.sh - build & install UnifyFS (autotools) after bootstrap.sh
# 优化版：借鉴官方 install-sh 稳健做法
# ------------------------------------------------------------

# 默认参数（可用环境变量覆盖）
DEPS_PREFIX="${DEPS_PREFIX:-$HOME/.local/unifyfs/stack/gcc-debug}"
UNIFYFS_PREFIX="${UNIFYFS_PREFIX:-$HOME/.local/unifyfs/unifyfs-gcc-debug}"
BUILD_DIR="${BUILD_DIR:-$PWD/build-unifyfs-gcc-debug}"
JOBS="${JOBS:-$(nproc)}"

ENABLE_PRELOAD="${ENABLE_PRELOAD:-1}"
ENABLE_MPI_MOUNT="${ENABLE_MPI_MOUNT:-0}"
ENABLE_FORTRAN="${ENABLE_FORTRAN:-auto}"
ENABLE_PMI="${ENABLE_PMI:-auto}"
ENABLE_PMIX="${ENABLE_PMIX:-auto}"
WITH_SPATH="${WITH_SPATH:-auto}"
WITH_GOTCHA="${WITH_GOTCHA:-1}"
WITHOUT_HDF5="${WITHOUT_HDF5:-auto}"
DISABLE_FORTIFY="${DISABLE_FORTIFY:-1}"

# -----------------------------
# 工具函数
# -----------------------------
log() { echo -e "\033[1;32m[install_unifyfs]\033[0m $*"; }
die() { echo -e "\033[1;31m[install_unifyfs][FATAL]\033[0m $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

have_pkg() {
    PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}" \
        pkg-config --exists "$1" >/dev/null 2>&1
}

# -----------------------------
# 检查工具
# -----------------------------
need_cmd make
need_cmd gcc
need_cmd pkg-config
[[ -d "$DEPS_PREFIX" ]] || die "DEPS_PREFIX 不存在: $DEPS_PREFIX"

log "依赖前缀: $DEPS_PREFIX"
log "UnifyFS 安装前缀: $UNIFYFS_PREFIX"
log "构建目录: $BUILD_DIR"

# -----------------------------
# 环境变量
# -----------------------------
export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:$DEPS_PREFIX/lib64/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$DEPS_PREFIX/lib:$DEPS_PREFIX/lib64:${LD_LIBRARY_PATH:-}"
export CPATH="$DEPS_PREFIX/include:${CPATH:-}"
export LIBRARY_PATH="$DEPS_PREFIX/lib:$DEPS_PREFIX/lib64"

# Debug + eBPF flags
BASE_CFLAGS="-O0 -g -fno-omit-frame-pointer"
BASE_CXXFLAGS="-O0 -g -fno-omit-frame-pointer"
BASE_FCFLAGS="-O0 -g -fno-omit-frame-pointer"

FORTIFY_OFF_FLAGS=""
if [[ "$DISABLE_FORTIFY" == "1" ]]; then
    FORTIFY_OFF_FLAGS="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
    log "Fortify: 已禁用"
else
    log "Fortify: 未禁用"
fi

export CFLAGS="${CFLAGS:-$BASE_CFLAGS} ${FORTIFY_OFF_FLAGS}"
export CXXFLAGS="${CXXFLAGS:-$BASE_CXXFLAGS} ${FORTIFY_OFF_FLAGS}"
export FCFLAGS="${FCFLAGS:-$BASE_FCFLAGS} ${FORTIFY_OFF_FLAGS}"
export CPPFLAGS="${CPPFLAGS:-} -I$DEPS_PREFIX/include ${FORTIFY_OFF_FLAGS}"
export LDFLAGS="${LDFLAGS:-} -L$DEPS_PREFIX/lib -L$DEPS_PREFIX/lib64"

# -----------------------------
# 构建 configure 选项
# -----------------------------
cfg_opts=("--prefix=$UNIFYFS_PREFIX")

# GOTCHA
if [[ "$WITH_GOTCHA" == "1" ]]; then
    cfg_opts+=("--with-gotcha=$DEPS_PREFIX")
else
    cfg_opts+=("--without-gotcha")
fi

# SPATH
if [[ "$WITH_SPATH" == "1" ]] || { [[ "$WITH_SPATH" == "auto" ]] && have_pkg spath; }; then
    cfg_opts+=("--with-spath=$DEPS_PREFIX")
    log "启用: SPATH (--with-spath)"
else
    log "不启用: SPATH"
fi

# Fortran
if [[ "$ENABLE_FORTRAN" == "1" ]] || { [[ "$ENABLE_FORTRAN" == "auto" ]] && command -v gfortran >/dev/null 2>&1; }; then
    cfg_opts+=("--enable-fortran")
    log "启用: Fortran (--enable-fortran)"
else
    log "不启用: Fortran"
fi

# PMI / PMIx
pmix_ok=0
pmi_ok=0
have_pkg pmix && pmix_ok=1
have_pkg pmi2 && pmi_ok=1

[[ "$ENABLE_PMIX" == "1" || ( "$ENABLE_PMIX" == "auto" && $pmix_ok -eq 1 ) ]] && cfg_opts+=("--enable-pmix") && log "启用: PMIx (--enable-pmix)"
[[ "$ENABLE_PMI" == "1" || ( "$ENABLE_PMI" == "auto" && $pmi_ok -eq 1 ) ]] && cfg_opts+=("--enable-pmi") && log "启用: PMI2 (--enable-pmi)"

# HDF5
if [[ "$WITHOUT_HDF5" == "1" ]] || { [[ "$WITHOUT_HDF5" == "auto" ]] && ! have_pkg hdf5; }; then
    cfg_opts+=("--without-hdf5")
    log "禁用: HDF5 (--without-hdf5)"
else
    log "启用: HDF5"
fi

# Preload / MPI mount
[[ "$ENABLE_PRELOAD" == "1" ]] && cfg_opts+=("--enable-preload") && log "启用: preload (--enable-preload)"
[[ "$ENABLE_MPI_MOUNT" == "1" ]] && cfg_opts+=("--enable-mpi-mount") && log "启用: MPI transparent mount (--enable-mpi-mount)"

# -----------------------------
# 创建构建目录（稳健）
# -----------------------------
mkdir -p "$BUILD_DIR"
log "构建目录已创建: $BUILD_DIR"

# -----------------------------
# 运行 autogen.sh
# -----------------------------
if [[ -x "$PWD/autogen.sh" ]]; then
    log "运行 ./autogen.sh"
    ./autogen.sh
else
    log "未发现 autogen.sh，可跳过（release tarball）"
fi

# -----------------------------
# 进入构建目录并 configure
# -----------------------------
pushd "$BUILD_DIR" >/dev/null
log "运行 configure..."
"$PWD/../configure" "${cfg_opts[@]}"

log "开始 make -j$JOBS"
make -j"$JOBS"

log "开始 make install"
make install
popd >/dev/null

# -----------------------------
# 完成提示
# -----------------------------
log "安装完成 ✅"
log "已安装到: $UNIFYFS_PREFIX"
log "运行时示例: export LD_LIBRARY_PATH=$UNIFYFS_PREFIX/lib:$UNIFYFS_PREFIX/lib64:\$LD_LIBRARY_PATH"
[[ "$ENABLE_PRELOAD" == "1" ]] && log "preload 库示例: export LD_PRELOAD=$UNIFYFS_PREFIX/lib/libunifyfs_preload_gotcha.so"