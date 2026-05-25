#!/usr/bin/env bash
# =============================================================================
# 一键同步上游仓库脚本（Git Bash / Linux / macOS）
# =============================================================================
# 用途：从上游仓库（upstream）拉取最新代码，合并到当前分支，并推送到 origin。
# 适用：仓库已脱离 fork 关系（standalone）后仍需追踪原项目更新。
#
# 默认上游：https://github.com/ZhuLinsen/daily_stock_analysis.git
#
# 用法：
#   一键同步（merge）：
#       bash scripts/sync-upstream.sh
#   或：
#       ./scripts/sync-upstream.sh
#
#   使用 rebase 替代 merge：
#       ./scripts/sync-upstream.sh --rebase
#
#   指定上游分支（默认自动 main -> master）：
#       ./scripts/sync-upstream.sh --branch develop
#
#   只同步不推送：
#       ./scripts/sync-upstream.sh --no-push
#
#   覆盖默认上游 URL：
#       ./scripts/sync-upstream.sh --upstream-url https://github.com/xxx/yyy.git
# =============================================================================

set -euo pipefail

# 默认上游仓库地址
DEFAULT_UPSTREAM_URL="https://github.com/ZhuLinsen/daily_stock_analysis.git"

UPSTREAM_URL=""
UPSTREAM_BRANCH=""
USE_REBASE=0
NO_PUSH=0

# ---------- 颜色输出 ----------
if [[ -t 1 ]]; then
    C_INFO=$'\033[36m'
    C_OK=$'\033[32m'
    C_WARN=$'\033[33m'
    C_ERR=$'\033[31m'
    C_RESET=$'\033[0m'
else
    C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_RESET=""
fi

log_info()  { echo "${C_INFO}[INFO]${C_RESET}  $*"; }
log_ok()    { echo "${C_OK}[OK]${C_RESET}    $*"; }
log_warn()  { echo "${C_WARN}[WARN]${C_RESET}  $*"; }
log_err()   { echo "${C_ERR}[ERROR]${C_RESET} $*" >&2; }

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebase)         USE_REBASE=1; shift ;;
        --no-push)        NO_PUSH=1; shift ;;
        --branch)         UPSTREAM_BRANCH="${2:-}"; shift 2 ;;
        --upstream-url)   UPSTREAM_URL="${2:-}"; shift 2 ;;
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            log_err "未知参数: $1"
            exit 1 ;;
    esac
done

# ---------- 1. 校验 git 仓库 ----------
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_err "当前目录不是 git 仓库"
    exit 1
fi

# ---------- 2. 检查工作区是否干净 ----------
if [[ -n "$(git status --porcelain)" ]]; then
    log_err "工作区存在未提交的改动，请先 commit 或 stash 后重试："
    git status --short
    exit 1
fi

# ---------- 3. 当前分支 ----------
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
log_info "当前分支: ${CURRENT_BRANCH}"

# ---------- 4. 处理 upstream remote ----------
EXISTING_UPSTREAM="$(git remote get-url upstream 2>/dev/null || true)"
EFFECTIVE_URL="${UPSTREAM_URL:-$DEFAULT_UPSTREAM_URL}"

if [[ -z "${EXISTING_UPSTREAM}" ]]; then
    log_info "添加 upstream remote: ${EFFECTIVE_URL}"
    git remote add upstream "${EFFECTIVE_URL}"
    log_ok "upstream remote 添加成功"
else
    if [[ -n "${UPSTREAM_URL}" && "${UPSTREAM_URL}" != "${EXISTING_UPSTREAM}" ]]; then
        log_warn "已存在 upstream (${EXISTING_UPSTREAM})，更新为: ${UPSTREAM_URL}"
        git remote set-url upstream "${UPSTREAM_URL}"
    else
        log_info "upstream remote: ${EXISTING_UPSTREAM}"
    fi
fi

# ---------- 5. 拉取上游 ----------
log_info "fetch upstream ..."
git fetch upstream --prune

# ---------- 6. 确定上游分支 ----------
if [[ -z "${UPSTREAM_BRANCH}" ]]; then
    for b in main master; do
        if git rev-parse --verify --quiet "upstream/${b}" >/dev/null; then
            UPSTREAM_BRANCH="${b}"
            break
        fi
    done
    if [[ -z "${UPSTREAM_BRANCH}" ]]; then
        log_err "未找到 upstream/main 或 upstream/master，请通过 --branch 指定"
        exit 1
    fi
fi
log_info "上游分支: upstream/${UPSTREAM_BRANCH}"

# ---------- 7. 显示落后情况 ----------
BEHIND_COUNT="$(git rev-list --count "HEAD..upstream/${UPSTREAM_BRANCH}" 2>/dev/null || echo 0)"
if [[ "${BEHIND_COUNT}" -eq 0 ]]; then
    log_ok "已经是最新，无需同步"
    exit 0
fi
log_info "上游领先 ${BEHIND_COUNT} 个提交"

# ---------- 8. 合并/rebase ----------
if [[ "${USE_REBASE}" -eq 1 ]]; then
    log_info "执行 rebase upstream/${UPSTREAM_BRANCH} -> ${CURRENT_BRANCH} ..."
    if ! git rebase "upstream/${UPSTREAM_BRANCH}"; then
        log_err "rebase 冲突，请手动解决后 git rebase --continue"
        exit 1
    fi
else
    log_info "执行 merge upstream/${UPSTREAM_BRANCH} -> ${CURRENT_BRANCH} ..."
    if ! git merge "upstream/${UPSTREAM_BRANCH}" --no-edit; then
        log_err "merge 冲突，请手动解决后重新提交"
        exit 1
    fi
fi
log_ok "已同步 upstream/${UPSTREAM_BRANCH} 到本地 ${CURRENT_BRANCH}"

# ---------- 9. 推送 origin ----------
if [[ "${NO_PUSH}" -eq 1 ]]; then
    log_warn "已跳过 push（--no-push 已开启）"
else
    log_info "push 到 origin/${CURRENT_BRANCH} ..."
    if [[ "${USE_REBASE}" -eq 1 ]]; then
        git push origin "${CURRENT_BRANCH}" --force-with-lease
    else
        git push origin "${CURRENT_BRANCH}"
    fi
    log_ok "已推送到 origin/${CURRENT_BRANCH}"
fi

echo ""
log_ok "上游同步完成！"
