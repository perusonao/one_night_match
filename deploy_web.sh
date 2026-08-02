#!/usr/bin/env bash
#
# deploy_web.sh — ONE NIGHT MATCH を Web ビルドして GitHub Pages (gh-pages) へ配信する。
#
# 使い方:
#   ./deploy_web.sh
#
# 動作:
#   1. flutter build web --release（GitHub Pages のプロジェクトサイト用に base-href を自動設定）
#   2. 一時 worktree で gh-pages ブランチを更新（ビルド成果物のみを配置）
#   3. origin へ push
#
# main などソースブランチのファイルには一切触れません。
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# --- リポジトリ名から base-href を決定（例: /one_night_match/） ---
REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
BASE_HREF="/${REPO_NAME}/"
PAGES_BRANCH="gh-pages"
WORKTREE_DIR="$(mktemp -d)"

echo "==> flutter build web (base-href=${BASE_HREF})"
flutter pub get
flutter build web --release --base-href "${BASE_HREF}" --no-web-resources-cdn

echo "==> gh-pages ブランチを更新"
# 既存の gh-pages（ローカル/リモート）を取得。無ければ orphan で新規作成。
git fetch origin "${PAGES_BRANCH}" >/dev/null 2>&1 || true
if git show-ref --verify --quiet "refs/remotes/origin/${PAGES_BRANCH}"; then
  git worktree add -B "${PAGES_BRANCH}" "${WORKTREE_DIR}" "origin/${PAGES_BRANCH}"
else
  git worktree add --orphan -B "${PAGES_BRANCH}" "${WORKTREE_DIR}"
fi

# 旧ファイルを掃除して新しいビルドを配置（.git は残す）
find "${WORKTREE_DIR}" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -a build/web/. "${WORKTREE_DIR}/"
touch "${WORKTREE_DIR}/.nojekyll"   # Jekyll 処理を無効化（_ 始まりファイル対策）

echo "==> commit & push"
(
  cd "${WORKTREE_DIR}"
  git add -A
  if git diff --cached --quiet; then
    echo "変更なし。push をスキップします。"
  else
    STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    git commit -q -m "Deploy web build to GitHub Pages (${STAMP})"
    for i in 1 2 3 4; do
      git push -u origin "${PAGES_BRANCH}" && break
      sleep $((2 ** i))
    done
  fi
)

# 後片付け（gh-pages ブランチ自体は残す）
git worktree remove "${WORKTREE_DIR}" --force

echo
echo "完了。数分後に以下で公開されます（初回のみ Settings > Pages で gh-pages を有効化）:"
echo "  https://$(git remote get-url origin | sed -E 's#(https?://[^/]+/|git@[^:]+:)##; s#\.git$##; s#/#.github.io/#')/"
