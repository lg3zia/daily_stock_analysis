# =============================================================================
# 一键同步上游仓库脚本（Windows PowerShell）
# =============================================================================
# 用途：从上游仓库（upstream）拉取最新代码，合并到当前分支，并推送到 origin。
# 适用：仓库已脱离 fork 关系（standalone）后仍需追踪原项目更新。
#
# 用法：
#   首次使用（自动添加 upstream remote）：
#       ./scripts/sync-upstream.ps1 -UpstreamUrl https://github.com/原作者/原仓库.git
#
#   已配置 upstream 后（直接同步）：
#       ./scripts/sync-upstream.ps1
#
#   使用 rebase 替代 merge：
#       ./scripts/sync-upstream.ps1 -Rebase
#
#   指定上游分支（默认 main，自动回退 master）：
#       ./scripts/sync-upstream.ps1 -UpstreamBranch develop
#
#   只同步不推送：
#       ./scripts/sync-upstream.ps1 -NoPush
# =============================================================================

[CmdletBinding()]
param(
    [string]$UpstreamUrl = "",
    [string]$UpstreamBranch = "",
    [switch]$Rebase,
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"

# 默认上游仓库地址
$DefaultUpstreamUrl = "https://github.com/ZhuLinsen/daily_stock_analysis.git"

function Write-Info($msg)    { Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-WarnMsg($msg) { Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# 1. 校验当前在 git 仓库中
try {
    $null = git rev-parse --is-inside-work-tree 2>$null
} catch {
    Write-Err "当前目录不是 git 仓库"
    exit 1
}

# 2. 检查工作区是否干净
$dirty = git status --porcelain
if ($dirty) {
    Write-Err "工作区存在未提交的改动，请先 commit 或 stash 后重试："
    git status --short
    exit 1
}

# 3. 获取当前分支
$currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
Write-Info "当前分支: $currentBranch"

# 4. 处理 upstream remote
$existingUpstream = git remote get-url upstream 2>$null
if (-not $existingUpstream) {
    $effectiveUrl = if ($UpstreamUrl) { $UpstreamUrl } else { $DefaultUpstreamUrl }
    Write-Info "添加 upstream remote: $effectiveUrl"
    git remote add upstream $effectiveUrl
    Write-Ok "upstream remote 添加成功"
} else {
    if ($UpstreamUrl -and $UpstreamUrl -ne $existingUpstream) {
        Write-WarnMsg "已存在 upstream ($existingUpstream)，与传入的 URL 不一致，更新为: $UpstreamUrl"
        git remote set-url upstream $UpstreamUrl
    } else {
        Write-Info "upstream remote: $existingUpstream"
    }
}

# 5. 拉取上游
Write-Info "fetch upstream ..."
git fetch upstream --prune

# 6. 确定上游分支
if (-not $UpstreamBranch) {
    $candidates = @("main", "master")
    foreach ($b in $candidates) {
        $exists = git rev-parse --verify --quiet "upstream/$b" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $UpstreamBranch = $b
            break
        }
    }
    if (-not $UpstreamBranch) {
        Write-Err "未找到 upstream/main 或 upstream/master，请通过 -UpstreamBranch 参数指定"
        exit 1
    }
}
Write-Info "上游分支: upstream/$UpstreamBranch"

# 7. 合并上游
$strategy = if ($Rebase) { "rebase" } else { "merge" }
Write-Info "执行 $strategy upstream/$UpstreamBranch -> $currentBranch ..."

if ($Rebase) {
    git rebase "upstream/$UpstreamBranch"
} else {
    git merge "upstream/$UpstreamBranch" --no-edit
}

if ($LASTEXITCODE -ne 0) {
    Write-Err "$strategy 过程中发生冲突，请手动解决后重新提交"
    exit 1
}

Write-Ok "已同步 upstream/$UpstreamBranch 到本地 $currentBranch"

# 8. 推送到 origin
if ($NoPush) {
    Write-WarnMsg "已跳过 push（-NoPush 已开启）"
} else {
    Write-Info "push 到 origin/$currentBranch ..."
    if ($Rebase) {
        git push origin $currentBranch --force-with-lease
    } else {
        git push origin $currentBranch
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Err "push 失败"
        exit 1
    }
    Write-Ok "已推送到 origin/$currentBranch"
}

Write-Host ""
Write-Ok "上游同步完成！"
