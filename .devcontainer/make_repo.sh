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
#    protocol, and "use the browser" answers are chosen for you; the only manual
#    step is clicking Authorize in the browser (GitHub's security boundary).
if ! gh auth status >/dev/null 2>&1; then
  echo "→ Sign in to GitHub: authorize in the browser/code prompt, then come back here."
  gh auth login --hostname github.com --git-protocol https --web
fi

# 3b. Make `git push` authenticate as YOU — from BOTH the terminal AND the VS
#     Code Source Control panel. The panel runs git in an environment where the
#     built-in, repo-scoped GITHUB_TOKEN is still set; a normal gh credential
#     helper would defer to that token and you'd get "Write access not granted"
#     on your own repo. So we write your personal token into git's credential
#     *store* file (which ignores env vars) and reset the helper list so the
#     store is the only helper git consults — overriding the Codespaces helper.
token="$(gh auth token)"
git config --global --replace-all credential.helper ""    # clear inherited (Codespaces) helpers
git config --global --add         credential.helper store
printf 'https://x-access-token:%s@github.com\n' "$token" > "$HOME/.git-credentials"
chmod 600 "$HOME/.git-credentials"

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

# 5. Record that this student now has a work repo, so the welcome banner
#    switches from "create a project" to "here's your project." postAttachCommand
#    always runs in the codespace-starter folder, so the banner can't detect the
#    move by directory — it reads this marker instead.
echo "$repo" > "$HOME/.student_repo"

# 6. Success banner. Opening the repo as the VS Code workspace is what makes the
#    Source Control panel act on YOUR repo — but Codespaces won't let a script
#    reliably switch the workspace folder, so the dependable path is the menu.
cat <<BANNER

════════════════════════════════════════════════════════════
   🎉  Created your repo: $repo   (/workspaces/$repo)

   👉 Open it:  File → Open Folder → /workspaces/$repo
      (the editor may switch on its own; if not, use that menu)

   Then, working inside your repo:
   • Save your work:    commit + push  (Source Control panel, left)
   • Publish a graphic: see .devcontainer/STUDENT_WORKFLOW.md
════════════════════════════════════════════════════════════

BANNER

# 7. Best-effort: ask VS Code to switch to the new repo. Codespaces often
#    ignores this from a script (the window can snap back to the home repo), so
#    it's a convenience only — the File → Open Folder step above is the guarantee.
if command -v code >/dev/null 2>&1; then
  code -r "/workspaces/$repo" >/dev/null 2>&1 || true
fi
