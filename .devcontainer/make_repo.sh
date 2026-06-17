#!/usr/bin/env bash
#
# make_repo.sh — create your personal work repo from a Codespace launched off
# codespace-starter.
#
#   Usage:  bash .devcontainer/make_repo.sh <repo-name>
#
# Safe to re-run: skips the login if you're already signed in, and clones your
# repo instead of recreating it if it already exists from a past session.
#
set -euo pipefail

repo="${1:-}"
if [[ -z "$repo" ]]; then
  echo "Usage: bash .devcontainer/make_repo.sh <repo-name>" >&2
  exit 2
fi

# 1. Drop the built-in, repo-scoped token so gh/git act as *you*, not as the
#    codespace-starter Codespace. Codespaces may populate either name, and that
#    token deliberately cannot create repositories — which is the whole problem
#    this script exists to solve.
unset GITHUB_TOKEN GH_TOKEN

# 2. Make that permanent for every new terminal in this Codespace, so future
#    pushes keep using your login instead of the built-in token.
if ! grep -qxF 'unset GITHUB_TOKEN GH_TOKEN' "$HOME/.bashrc" 2>/dev/null; then
  echo 'unset GITHUB_TOKEN GH_TOKEN' >> "$HOME/.bashrc"
fi

# 3. Sign in as yourself — only if not already signed in. The hostname,
#    protocol, and "use the browser" answers are all chosen for you; the only
#    thing you do by hand is click Authorize in the browser. That step cannot
#    be scripted (it is GitHub's security boundary).
if ! gh auth status >/dev/null 2>&1; then
  echo "→ Sign in to GitHub: authorize in the browser/code prompt, then come back here."
  gh auth login --hostname github.com --git-protocol https --web
fi
gh auth setup-git    # route `git push` through your login

# 4. Create the repo — or clone it if it already exists from a past session.
cd /workspaces
if [[ -d "$repo/.git" ]]; then
  echo "→ /workspaces/$repo is already here."
elif gh repo view "$repo" >/dev/null 2>&1; then
  echo "→ '$repo' already exists on GitHub — cloning it."
  gh repo clone "$repo" "$repo"
else
  gh repo create "$repo" --private --clone
fi

# 5. Switch VS Code into your new repo. A script runs in a child process, so it
#    cannot change your *terminal's* directory — but it can move your *editor*,
#    which is what actually matters in a Codespace. New terminals you open will
#    then start in your repo.
echo "✅ Ready: /workspaces/$repo"
if command -v code >/dev/null 2>&1; then
  code -r "/workspaces/$repo"
else
  echo "   Open it with:  File → Open Folder → /workspaces/$repo"
fi
