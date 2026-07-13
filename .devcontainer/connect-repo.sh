#!/usr/bin/env bash
#
# connect-repo.sh — create (or connect to) your personal work repo from a
# Codespace launched off codespace-starter. If a repo by the given name already
# exists on your GitHub account, it's cloned; otherwise it's created.
#
#   Usage:  .devcontainer/connect-repo.sh <repo-name>
#
# Safe to re-run: skips the login if you're already signed in, and clones your
# repo instead of recreating it if it already exists from a past session.
#
set -euo pipefail

# --help / -h: explain (without running) the git/GitHub commands this script
# issues, so you can learn what's happening and do it by hand. Kept before any
# of the side-effecting steps below so `--help` never changes anything.
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'HELP'
connect-repo.sh — create or connect to your GitHub work repo

This script just automates a few GitHub steps so you can start fast. There is
no magic here: below is every command it runs, what it means, and how you could
do the exact same thing yourself with `gh` (the GitHub CLI) and `git`. You'll
use these commands all term, so it's worth understanding them.

  1. ACT AS YOU, NOT AS THE CODESPACE
         unset GITHUB_TOKEN GH_TOKEN
     A Codespace starts with a built-in token that can only touch
     codespace-starter and can't create repos. Clearing it makes `gh` and
     `git` use YOUR GitHub login instead.

  2. SIGN IN TO GITHUB AS YOURSELF (once per Codespace)
         gh auth login --hostname github.com --git-protocol https --web
     Opens a browser sign-in. Click Authorize, then come back.

  3. MAKE `git push` AUTHENTICATE AS YOU
         git config --global credential.helper store
         # then save your token (shown by `gh auth token`) into ~/.git-credentials
     Stores your token so pushes — from the terminal AND the VS Code Source
     Control panel — go out as you, not as the built-in Codespace token.

  4. CREATE A NEW REPO, OR CONNECT TO ONE THAT EXISTS
     New repo on your account (doesn't exist yet):
         gh repo create <name> --public --clone
     Existing repo — yours, or an org's / someone else's via owner/<name>:
         gh repo clone <name>          # your own
         gh repo clone owner/<name>    # an org / another user (needs read access)
     Either way you end up with the repo at /workspaces/<name>.

After that, you work in /workspaces/<name> and save with the normal git cycle:
         git add -A
         git commit -m "describe what you changed"
         git push

The script also drops your terminal into the new folder and smooths a couple of
Codespace quirks, but steps 1–4 above are the whole GitHub story. Run them by
hand any time you'd rather not use the script.

  Usage:  .devcontainer/connect-repo.sh <repo-name>
HELP
  exit 0
fi

repo="${1:-}"
if [[ -z "$repo" ]]; then
  echo "Usage: .devcontainer/connect-repo.sh <repo-name>" >&2
  echo "       .devcontainer/connect-repo.sh owner/<repo-name>  (connect to an org/other repo)" >&2
  echo "       .devcontainer/connect-repo.sh --help   (explains the git commands it runs)" >&2
  exit 2
fi

# Split the argument into the REMOTE ref gh resolves and the LOCAL folder name.
# For a bare "name" they're identical (the original behavior). For "owner/name"
# we clone the remote owner/name but keep the local folder a plain basename, so
# everything below — the marker, the auto-cd guard (step 2b), `cd` — stays
# slash-free and unchanged.
remote="$repo"          # <name>  OR  owner/<name>
dir="${repo##*/}"       # basename only
if [[ -z "$dir" || "$dir" == "." || "$dir" == ".." ]]; then
  echo "Invalid repo name: '$repo'" >&2
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
  # connect-repo.sh, but validate so a corrupted file can't cd us off target.
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
  # NODE_NO_WARNINGS=1: when gh opens the device-login URL it runs the
  # Codespaces browser-opener (Node), which prints a scary-looking
  # `url.parse()` DeprecationWarning. That's upstream noise, not a problem
  # here — suppress it so students aren't alarmed mid-sign-in.
  NODE_NO_WARNINGS=1 gh auth login --hostname github.com --git-protocol https --web
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

# 4. Create the repo — or clone it if it already exists (yours, an org's, or a
#    past session's). Clone the REMOTE ref into the basename DIR.
cd /workspaces
if [[ -d "$dir/.git" ]]; then
  echo "→ /workspaces/$dir is already here."
elif gh repo view "$remote" >/dev/null 2>&1; then
  echo "→ '$remote' already exists on GitHub — cloning it."
  gh repo clone "$remote" "$dir"
elif [[ "$repo" == */* ]]; then
  # owner/name that doesn't exist: don't try to create in someone else's
  # namespace (it would just fail with a confusing permission error).
  echo "→ '$remote' not found, and we won't create a repo under '${repo%%/*}'." >&2
  exit 1
else
  gh repo create "$remote" --public --clone
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
echo "$dir" > "$HOME/.student_repo"

# 6. Best-effort: ask VS Code to switch the Explorer to the new repo. Codespaces
#    often ignores this from a script (the window can snap back to the home
#    repo), so it's a convenience only — File → Open Folder is the manual
#    fallback, documented in STUDENT_WORKFLOW.md.
if command -v code >/dev/null 2>&1; then
  code -r "/workspaces/$dir" >/dev/null 2>&1 || true
fi

# 7. Put THIS terminal in the repo too. Steps 2b and 6 only fix NEW terminals
#    and the Explorer; the terminal that ran this script is still sitting in
#    codespace-starter, so `claude`/`codex` typed right now would write to the
#    launcher — invisibly, since the Explorer shows the repo. A script can't cd
#    its parent shell, so we replace this shell with a fresh one rooted in the
#    repo. Only when attached to a terminal (skip in non-interactive/CI runs).
#    Must be LAST: exec never returns. `exit` later drops back to the launcher.
if [[ -t 1 ]]; then
  cd "/workspaces/$dir"
  exec bash
fi
