#!/usr/bin/env bash
#
# make_repo.sh — create your personal work repo from a Codespace launched off
# codespace-starter.
#
#   Usage:  .devcontainer/make_repo.sh <repo-name>
#
# Safe to re-run: skips the login if you're already signed in, and clones your
# repo instead of recreating it if it already exists from a past session.
#
set -euo pipefail

repo="${1:-}"
if [[ -z "$repo" ]]; then
  echo "Usage: .devcontainer/make_repo.sh <repo-name>" >&2
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

# 2b. Make every NEW terminal open in your work repo, not this launcher. A
#     terminal that starts in /workspaces/codespace-starter leaves `claude`,
#     `codex`, etc. running here, so the files they create land in the
#     launcher — invisibly, since the Explorer is showing your repo. We append
#     a guard to ~/.bashrc (runs at each shell start) that cd's into the repo
#     recorded in ~/.student_repo (written in step 5). Scoped to the launcher
#     dir and gated on the repo existing, so it never overrides where you've
#     deliberately navigated. Idempotent via the sentinel in the marker line.
if ! grep -qF 'codespace-starter:auto-cd' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'BASHRC'

# codespace-starter:auto-cd — open new terminals in your work repo, not the launcher.
if [[ $PWD == /workspaces/codespace-starter && -r $HOME/.student_repo ]]; then
  __sr=$(cat "$HOME/.student_repo" 2>/dev/null) || true
  # Only a plain repo name (no slashes, not . or ..) — the marker is written by
  # make_repo.sh, but validate so a corrupted file can't cd us off target.
  if [[ -n ${__sr:-} && $__sr != */* && $__sr != . && $__sr != .. && -d /workspaces/$__sr ]]; then
    cd "/workspaces/$__sr"
  fi
  unset __sr
fi
BASHRC
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
  gh repo create "$repo" --public --clone
fi

# NOTE: we deliberately do NOT seed a .vscode/settings.json into the new repo.
# The devcontainer's settings (arf R console, autosave, git.autofetch off, …)
# are applied at the Codespace's *Machine* scope, which DOES carry over to any
# folder the student opens in this Codespace — verified by launching an R
# console in a fresh repo with no settings file and seeing /usr/local/bin/arf
# run. (The earlier "git fetch automatically?" prompt was Restricted Mode, now
# handled by disabling Workspace Trust in welcome.sh — not a missing copy.) So
# a seeded file was pure redundancy, and worse: it left a confusing settings
# file in an otherwise-empty new repo.

# 5. Record that this student now has a work repo, so the welcome banner
#    switches from "create a project" to "here's your project." postAttachCommand
#    always runs in the codespace-starter folder, so the banner can't detect the
#    move by directory — it reads this marker instead.
echo "$repo" > "$HOME/.student_repo"

# 6. Best-effort: ask VS Code to switch the Explorer to the new repo. Codespaces
#    often ignores this from a script (the window can snap back to the home
#    repo), so it's a convenience only — File → Open Folder is the manual
#    fallback, documented in STUDENT_WORKFLOW.md.
if command -v code >/dev/null 2>&1; then
  code -r "/workspaces/$repo" >/dev/null 2>&1 || true
fi

# 7. Put THIS terminal in the repo too. Steps 2b and 6 only fix NEW terminals
#    and the Explorer; the terminal that ran this script is still sitting in
#    codespace-starter, so `claude`/`codex` typed right now would write to the
#    launcher — invisibly, since the Explorer shows the repo. A script can't cd
#    its parent shell, so we replace this shell with a fresh one rooted in the
#    repo. Only when attached to a terminal (skip in non-interactive/CI runs).
#    Must be LAST: exec never returns. `exit` later drops back to the launcher.
if [[ -t 1 ]]; then
  cd "/workspaces/$repo"
  exec bash
fi
