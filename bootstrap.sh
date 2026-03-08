#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# UnifyFS Dependency Bootstrap (Manual build_*.sh runner)
# - Runs scripts in a fixed dependency order
# - Skips openpa by default
# - Robust logging, traps, and helpful diagnostics
# ==============================================================================

# -----------------------------
# Pretty output (no external deps)
# -----------------------------
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[31m'
  GRN=$'\033[32m'
  YLW=$'\033[33m'
  BLU=$'\033[34m'
  MAG=$'\033[35m'
  CYN=$'\033[36m'
  RST=$'\033[0m'
else
  BOLD='' DIM='' RED='' GRN='' YLW='' BLU='' MAG='' CYN='' RST=''
fi

ts() { date +"%Y-%m-%d %H:%M:%S"; }

log()   { printf "%s %s[%sbootstrap%s]%s %s\n" "$(ts)" "${BOLD}${CYN}" "${MAG}" "${CYN}" "${RST}" "$*"; }
ok()    { printf "%s %s[%s OK %s]%s %s\n" "$(ts)" "${BOLD}${GRN}" "${GRN}" "${GRN}" "${RST}" "$*"; }
warn()  { printf "%s %s[%sWARN%s]%s %s\n" "$(ts)" "${BOLD}${YLW}" "${YLW}" "${RST}" "$*" >&2; }
die()   { printf "%s %s[%sFAIL%s]%s %s\n" "$(ts)" "${BOLD}${RED}" "${RED}" "${RST}" "$*" >&2; exit 1; }

# -----------------------------
# Trap: show where it failed
# -----------------------------
CURRENT_STEP=""
on_err() {
  local exit_code=$?
  local line_no=${1:-"?"}
  die "在步骤 ${BOLD}${CURRENT_STEP:-unknown}${RST} 失败（exit=${exit_code}，line=${line_no}）。请查看上方日志定位原因。"
}
trap 'on_err $LINENO' ERR

# -----------------------------
# Locate project root & scripts dir
# -----------------------------
# This script is expected to live in repo root: <repo>/bootstrap.sh
SCRIPT_SELF="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_SELF")" && pwd)"
SCRIPTS_DIR="${ROOT_DIR}/scripts"

[[ -d "$SCRIPTS_DIR" ]] || die "找不到 scripts/ 目录：${SCRIPTS_DIR}"

# -----------------------------
# Args
# -----------------------------
DRY_RUN=0
FROM_STEP=""

usage() {
  cat <<EOF
用法：
  ./bootstrap.sh [--dry-run] [--from <step>]

参数：
  --dry-run        只打印将要执行的命令，不实际运行
  --from <step>    从指定步骤开始（可用：gotcha argobots libfabric mercury spath mochi-margo）
  -h, --help       显示帮助

示例：
  ./bootstrap.sh
  ./bootstrap.sh --dry-run
  ./bootstrap.sh --from libfabric
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --from) FROM_STEP="${2:-}"; [[ -n "$FROM_STEP" ]] || die "--from 需要一个步骤名"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1（用 -h 查看帮助）" ;;
  esac
done

# -----------------------------
# Step definitions (order matters)
# NOTE: openpa intentionally excluded.
# -----------------------------
declare -a STEPS=(
  "gotcha:scripts/build_gotcha.sh"
  "argobots:scripts/build_argobots.sh"
  "libfabric:scripts/build_libfabric.sh"
  "mercury:scripts/build_mercury.sh"
  "spath:scripts/build_spath.sh"
  "mochi-margo:scripts/build_mochi-margo.sh"
)

# Validate FROM_STEP if provided
if [[ -n "$FROM_STEP" ]]; then
  found=0
  for item in "${STEPS[@]}"; do
    step="${item%%:*}"
    [[ "$step" == "$FROM_STEP" ]] && found=1 && break
  done
  [[ $found -eq 1 ]] || die "--from 的步骤名无效：${FROM_STEP}"
fi

# -----------------------------
# Helpers
# -----------------------------
ensure_executable() {
  local path="$1"
  [[ -f "$path" ]] || die "缺少脚本：${path}"
  if [[ ! -x "$path" ]]; then
    warn "脚本不可执行：${path}"
    warn "正在尝试自动修复：chmod +x ${path}"
    chmod +x "$path" || die "chmod 失败：${path}"
  fi
}

run_step() {
  local idx="$1"
  local total="$2"
  local name="$3"
  local relpath="$4"

  local path="${ROOT_DIR}/${relpath}"
  ensure_executable "$path"

  CURRENT_STEP="$name"

  # fancy header
  printf "\n%s%s══════════════════════════════════════════════════════════════════════%s\n" \
    "${BOLD}${BLU}" "" "${RST}"
  printf "%s%s▶ [%d/%d] %s%s\n" "${BOLD}${BLU}" "" "$idx" "$total" "$name" "${RST}"
  printf "%s%s   script: %s%s%s\n" "${DIM}${BLU}" "" "${RST}${BOLD}" "$path" "${RST}"
  printf "%s%s══════════════════════════════════════════════════════════════════════%s\n" \
    "${BOLD}${BLU}" "" "${RST}"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "(dry-run) 将执行：bash ${path}"
    return 0
  fi

  # Run with a clean, predictable working dir (repo root)
  ( cd "$ROOT_DIR" && bash "$path" )

  ok "完成：$name"
}

# -----------------------------
# Main
# -----------------------------
log "项目根目录：${BOLD}${ROOT_DIR}${RST}"
log "脚本目录：${BOLD}${SCRIPTS_DIR}${RST}"
log "模式：$([[ $DRY_RUN -eq 1 ]] && echo "${YLW}dry-run${RST}" || echo "${GRN}execute${RST}")"
[[ -n "$FROM_STEP" ]] && log "从步骤开始：${BOLD}${FROM_STEP}${RST}"

total="${#STEPS[@]}"
start=1
if [[ -n "$FROM_STEP" ]]; then
  i=1
  for item in "${STEPS[@]}"; do
    step="${item%%:*}"
    [[ "$step" == "$FROM_STEP" ]] && start="$i" && break
    ((i++))
  done
fi

# Run all steps
i=1
for item in "${STEPS[@]}"; do
  if (( i < start )); then
    step="${item%%:*}"
    warn "跳过（--from 生效）：$step"
    ((i++))
    continue
  fi

  name="${item%%:*}"
  rel="${item#*:}"
  run_step "$i" "$total" "$name" "$rel"
  ((i++))
done

printf "\n%s%s✅ 全部依赖构建流程执行完毕（openpa 已跳过）。%s\n" "${BOLD}${GRN}" "" "${RST}"
printf "%s%s接下来你可以在根目录运行：%s./autogen.sh && ./configure ... && make -j%s\n\n" \
  "${DIM}${CYN}" "" "${RST}${BOLD}" "$(nproc 2>/dev/null || echo 4)" "${RST}"