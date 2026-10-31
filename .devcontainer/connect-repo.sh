#!/usr/bin/env bash
#
# connect-repo.sh — create (or connect to) your personal work repo from a
# Codespace launched off codespace-starter. If a repo by the given name already
# exists on your GitHub account, it's cloned; otherwise it's created.
#
#   Usage:  connect-repo [--no-agents] <repo-name>
#   (setup.sh installs the `connect-repo` wrapper on PATH at Codespace
#   create; invoking .devcontainer/connect-repo.sh directly works too)
#
# By default the new repo gets a copy of AGENTS.md (guidance on how AI
# assistants should work with students in this course); --no-agents skips it.
#
# DESIGN (2026-10-30). This script is a transcript of the commands a student
# learns to run by hand in the GitHub tutorials, with an "already done?" check
# in front of each one. Three paths must end in the SAME state: this script,
# the by-hand commands, and a dotfiles repo plus the Codespaces user secret
# GH_TOKEN (which do the identity work at Codespace creation). When dotfiles
# have done that work, every check here passes and the script reduces to
# `gh repo create`. Everything it writes outside the repo lives in ONE place,
# ~/.config/codespace-starter — a shell snippet in bashrc.d/ and the repo
# marker — plus, only when nothing better exists, ~/.git-credentials. It
# never edits ~/.bashrc: setup.sh appended one block there at create that
# sources bashrc.d/*.sh, and that block is the starter's only mark on the
# file. Each step prints the COMMAND it is about to run — the same command a
# student learns to type in the GitHub tutorials — or a "skipped:" line with
# the reason, so every run doubles as a demonstration of what connect-repo
# automates.
#
# Safe to re-run: skips the sign-in if you're already signed in, leaves a
# credential setup that already works alone, and clones your repo instead of
# recreating it if it already exists from a past session.
#
set -euo pipefail

# Resolve this script's directory NOW, before anything cd's elsewhere. The
# script is normally invoked by a RELATIVE path (.devcontainer/connect-repo.sh)
# and later cd's to /workspaces — after that, a relative BASH_SOURCE no longer
# resolves. (This bit a student: step 4b died with "cd: .devcontainer: No such
# file or directory", and set -e then killed every remaining step.)
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Where everything the starter writes to your home directory lives (see the
# DESIGN note above). setup.sh created the directory at Codespace create.
state_dir="$HOME/.config/codespace-starter"
bashrc_d="$state_dir/bashrc.d"
marker="$state_dir/student-repo"

# Split out the --no-agents flag (position-independent) from the repo name.
no_agents=false
positional=()
for arg in "$@"; do
  case "$arg" in
    --no-agents) no_agents=true ;;
    *)           positional+=("$arg") ;;
  esac
done
set -- ${positional+"${positional[@]}"}

# --help / -h: explain (without running) the git/GitHub commands this script
# issues, so you can learn what's happening and do it by hand. Kept before any
# of the side-effecting steps below so `--help` never changes anything.
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'HELP'
connect-repo — create or connect to your GitHub work repo

This script just automates a few GitHub steps so you can start fast. There is
no magic here: below is every command it runs, what it means, and how you could
do the exact same thing yourself with `gh` (the GitHub CLI) and `git`. You'll
use these commands all term, so it's worth understanding them. Each step is
skipped when it has already been done — by you, by an earlier run, or by a
dotfiles repo and a GH_TOKEN secret of your own.

  1. ACT AS YOU, NOT AS THE CODESPACE
         unset GITHUB_TOKEN
     A Codespace starts with a built-in token that can only touch
     codespace-starter and can't create repos. Clearing it makes `gh` and
     `git` use YOUR GitHub login instead. (Skipped when you have a GH_TOKEN
     secret: `gh` prefers that to the built-in token anyway.)

  2. SIGN IN TO GITHUB AS YOURSELF (once per Codespace)
         gh auth login --hostname github.com --git-protocol https --web --clipboard=false
     Opens a browser sign-in. Click Authorize, then come back. (Skipped when
     `gh auth status` already says you are signed in.)

  3. MAKE `git push` AUTHENTICATE AS YOU
         git config --global credential.helper store
         # then save your token (shown by `gh auth token`) into ~/.git-credentials
     Stores your token so pushes — from the terminal AND the VS Code Source
     Control panel — go out as you, not as the built-in Codespace token.
     This file is the one thing here you would do differently by hand: the
     usual command is `gh auth setup-git`, which makes git ask `gh` for the
     password. That works in the terminal, but the Source Control panel's
     git still carries the built-in token, which `gh` would hand over — so
     the Sync button needs the file (or a GH_TOKEN secret, see the Dotfiles
     tutorial). (Skipped when a GH_TOKEN secret plus a `gh auth
     git-credential` helper in your Git config already do this.)

  4. CREATE A NEW REPO, OR CONNECT TO ONE THAT EXISTS
     New repo on your account (doesn't exist yet):
         gh repo create <name> --public --clone
     Existing repo — yours, or an org's / someone else's via owner/<name>:
         gh repo clone <name>          # your own
         gh repo clone owner/<name>    # an org / another user (needs read access)
     Either way you end up with the repo at /workspaces/<name>.

  5. ADD AI-ASSISTANT GUIDANCE (default; skip with --no-agents)
     Copies AGENTS.md into your new repo. It tells AI assistants (GitHub
     Copilot, Antigravity, and friends) how to work with you in this course:
     short, narrated steps and brief answers. Pass --no-agents if you'd
     rather work without it.

After that, you work in /workspaces/<name> and save with the normal git cycle:
         git add -A
         git commit -m "describe what you changed"
         git push

The script also drops your terminal into the new folder and smooths a couple of
Codespace quirks, but steps 1–4 above are the whole GitHub story. Run them by
hand any time you'd rather not use the script. Everything the script writes
outside your repo is in ~/.config/codespace-starter (and ~/.git-credentials
when step 3 runs); `ls ~/.config/codespace-starter/bashrc.d` shows the shell
snippets it added.

  Usage:  connect-repo [--no-agents] <repo-name>
HELP
  exit 0
fi

repo="${1:-}"
if [[ -z "$repo" ]]; then
  echo "Usage: connect-repo [--no-agents] <repo-name>" >&2
  echo "       connect-repo owner/<repo-name>  (connect to an org/other repo)" >&2
  echo "       connect-repo --help   (explains the git commands it runs)" >&2
  exit 2
fi

# Split the argument into the REMOTE ref gh resolves and the LOCAL folder name.
# For a bare "name" they're identical (the original behavior). For "owner/name"
# we clone the remote owner/name but keep the local folder a plain basename, so
# everything below — the marker, `cd` — stays slash-free and unchanged.
remote="$repo"          # <name>  OR  owner/<name>
dir="${repo##*/}"       # basename only
if [[ -z "$dir" || "$dir" == "." || "$dir" == ".." ]]; then
  echo "Invalid repo name: '$repo'" >&2
  exit 2
fi

mkdir -p "$bashrc_d"

# Every step announces itself: the command it runs (so a student sees the
# real gh/git commands each time), or why it was skipped.
run()  { printf '→ %s\n' "$1"; }
skip() { printf '→ skipped: %s\n' "$1"; }

# 1. Drop the built-in, repo-scoped token so gh and git act as *you*, not as
#    the codespace-starter Codespace. That token deliberately cannot create
#    repositories — which is the whole problem this script exists to solve.
#    Needed when there is no GH_TOKEN: an env GITHUB_TOKEN beats the hosts.yml
#    login that step 3 creates. Skipped when GH_TOKEN is set: gh prefers
#    GH_TOKEN over GITHUB_TOKEN, so the built-in token is already out of the
#    picture, in this shell and in every other.
#    GH_TOKEN itself is never touched (2026-10-29): Codespaces never sets it,
#    and the Dotfiles tutorial stores the student's own PAT as the Codespaces
#    user secret GH_TOKEN. Unsetting it would log a graduated student out of
#    every later terminal.
if [[ -z "${GH_TOKEN:-}" ]]; then
  run "unset GITHUB_TOKEN   (the built-in token acts as the Codespace, not as you; also in every new terminal)"
  unset GITHUB_TOKEN
else
  skip "unset GITHUB_TOKEN — your GH_TOKEN secret already takes precedence"
fi

# 1b. A GH_TOKEN that GitHub rejects (expired, revoked, mistyped) is worse than
#     none: gh keeps preferring it, so a browser sign-in below could not help.
#     Say so and stop, instead of failing later with a confusing 401.
if [[ -n "${GH_TOKEN:-}" ]] && ! gh auth status >/dev/null 2>&1; then
  echo "✗ GH_TOKEN is set in this Codespace, but GitHub rejects it (expired or revoked?)." >&2
  echo "  gh and git will keep using it until it is fixed. Update or delete the GH_TOKEN" >&2
  echo "  secret at https://github.com/settings/codespaces, then create a new Codespace." >&2
  exit 1
fi

# 2. Make step 1 permanent for every new terminal in this Codespace, so later
#    gh and git commands keep using your login instead of the built-in token.
#    A file in bashrc.d, not a line in ~/.bashrc (see DESIGN). Skipped, like
#    step 1, when GH_TOKEN is set. (Announced as part of step 1's line.)
if [[ -z "${GH_TOKEN:-}" ]]; then
  cat > "$bashrc_d/30-github-token.sh" <<'SNIPPET'
# codespace-starter — written by connect-repo. A Codespace starts every terminal
# with a built-in GITHUB_TOKEN that acts as the Codespace, not as you, and can
# only read codespace-starter. Dropping it makes gh and git use your own sign-in.
unset GITHUB_TOKEN
SNIPPET
fi

# 3. Sign in as yourself — only if not already signed in. The hostname,
#    protocol, and "use the browser" answers are chosen for you; the only manual
#    step is clicking Authorize in the browser (GitHub's security boundary).
#    Already signed in means either a GH_TOKEN secret (dotfiles graduate) or a
#    hosts.yml login from an earlier run in this Codespace.
if gh auth status >/dev/null 2>&1; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    skip "gh auth login — already signed in as you via your GH_TOKEN secret"
  else
    skip "gh auth login — already signed in as you earlier in this Codespace"
  fi
else
  run "gh auth login --hostname github.com --git-protocol https --web --clipboard=false"
  echo "   Authorize in the browser/code prompt, then come back here."
  # NODE_NO_WARNINGS=1: when gh opens the device-login URL it runs the
  # Codespaces browser-opener (Node), which prints a scary-looking
  # `url.parse()` DeprecationWarning. That's upstream noise, not a problem
  # here — suppress it so students aren't alarmed mid-sign-in.
  NODE_NO_WARNINGS=1 gh auth login --hostname github.com --git-protocol https --web --clipboard=false
fi

# 3b. Make `git push` authenticate as YOU — from BOTH the terminal AND the VS
#     Code Source Control panel. The panel runs git in an environment where the
#     built-in, repo-scoped GITHUB_TOKEN is still set; a normal gh credential
#     helper would defer to that token and you'd get "Write access not granted"
#     on your own repo. So we write your personal token into git's credential
#     *store* file (which ignores env vars) and reset the helper list so the
#     store is the only helper git consults — overriding the Codespaces helper.
#
#     SKIPPED when both halves of the dotfiles setup are present: a GH_TOKEN
#     secret AND a `gh auth git-credential` helper in your Git config. Then gh
#     answers git's password requests with GH_TOKEN, which it prefers over
#     GITHUB_TOKEN even inside the panel's environment — the same end state,
#     reached at Codespace creation, and clobbering it would undo the
#     student's own work. Either half alone is not enough (the helper without
#     GH_TOKEN would hand the panel the built-in token), so then we still
#     write the store.
if [[ -n "${GH_TOKEN:-}" ]] && git config --get-all credential.helper 2>/dev/null | grep -q 'gh auth git-credential'; then
  skip "git config credential.helper — your gitconfig already sends git to gh, and gh has your GH_TOKEN"
else
  run "git config --global credential.helper store   (+ your token into ~/.git-credentials, so the Source Control pane's Sync button pushes as you; by hand you would run 'gh auth setup-git' — see --help)"
  token="$(gh auth token)"
  git config --global --replace-all credential.helper ""    # clear inherited (Codespaces) helpers
  git config --global --add         credential.helper store
  printf 'https://x-access-token:%s@github.com\n' "$token" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
fi

# 4. Create the repo — or clone it if it already exists (yours, an org's, or a
#    past session's). Clone the REMOTE ref into the basename DIR.
cd /workspaces
if [[ -d "$dir/.git" ]]; then
  skip "gh repo create/clone — /workspaces/$dir is already here"
elif gh repo view "$remote" >/dev/null 2>&1; then
  run "gh repo clone $remote $dir   ('$remote' already exists on GitHub)"
  gh repo clone "$remote" "$dir"
elif [[ "$repo" == */* ]]; then
  # owner/name that doesn't exist: don't try to create in someone else's
  # namespace (it would just fail with a confusing permission error).
  echo "→ '$remote' not found, and we won't create a repo under '${repo%%/*}'." >&2
  exit 1
else
  run "gh repo create $remote --public --clone"
  gh repo create "$remote" --public --clone
fi

# 4b. Copy the AI-assistant guidance into the repo (default; --no-agents
#     skips). AGENTS.md tells the AI tools students use (GitHub Copilot via
#     the chat.useAgentsMdFile setting in devcontainer.json, Antigravity and
#     other CLIs natively) to tutor rather than solve. It must sit at the
#     root of the STUDENT'S repo — AI tools read instruction files from the
#     folder they run in, which is this repo once the Explorer has switched to
#     it (step 6). Only copied when absent, so an instructor-updated or
#     student-edited copy is never clobbered. The canonical version lives at
#     .devcontainer/AGENTS.md in codespace-starter; edit it THERE.
if ! $no_agents && [[ ! -e "/workspaces/$dir/AGENTS.md" ]]; then
  if [[ -f "$script_dir/AGENTS.md" ]]; then
    run "cp codespace-starter/.devcontainer/AGENTS.md /workspaces/$dir/   (how AI assistants work with you in this course; --no-agents skips)"
    cp "$script_dir/AGENTS.md" "/workspaces/$dir/AGENTS.md"
  fi
fi

# NOTE: we deliberately do NOT seed a .vscode/settings.json into the new repo.
# The devcontainer's settings (arf R console, autosave, git.autofetch, …) are
# applied at the Codespace's *Machine* scope, which DOES carry over to any
# folder the student opens in this Codespace — verified by launching an R
# console in a fresh repo with no settings file and seeing /usr/local/bin/arf
# run. So a seeded file was pure redundancy, and worse: it left a confusing
# settings file in an otherwise-empty new repo. (An earlier version of this
# note blamed Restricted Mode for the "git fetch automatically?" prompt and
# claimed welcome.sh disabled Workspace Trust; both were wrong — see
# devcontainer.json's git.autofetch and Workspace Trust comments.)

# 5. Record that this student now has a work repo, so the welcome banner
#    (welcome.sh, run from bashrc.d in every new terminal) stops printing.
#    welcome.sh runs from the launcher checkout regardless of the current
#    folder, so it can't detect progress by directory — it reads this marker
#    instead.
echo "$dir" > "$marker"

# 6. Ask VS Code to switch the Explorer to the new repo. Reliable in practice
#    since about 2026-10 (David: not seen it fail in weeks); earlier Codespaces
#    sometimes ignored it from a script and the window snapped back to the
#    home repo. Kept best-effort: File → Open Folder is the manual fallback,
#    documented in STUDENT_WORKFLOW.md.
if command -v code >/dev/null 2>&1; then
  code -r "/workspaces/$dir" >/dev/null 2>&1 || true
fi

# 6b. Say, in one line, what is now connected to what — the whole point of
#     this script. The path is where the student works; the URL is the GitHub
#     repo it saves to (read from git so it is never wrong about the owner —
#     an owner/<name> argument clones someone else's repo). Normalized to a
#     plain https://github.com/<owner>/<repo> web URL: a pre-existing clone
#     (step 4 accepts one as is) may have a token in its URL
#     (https://TOKEN@github.com/…) or be an SSH remote (git@github.com:…) —
#     the first must never reach the terminal scrollback (Copilot, PR #54).
origin="$(git -C "/workspaces/$dir" remote get-url origin 2>/dev/null || true)"
origin="${origin%.git}"
origin="$(printf '%s' "$origin" | sed -E 's#^[a-z+]+://[^@/]*@#https://#; s#^git@([^:]+):#https://\1/#')"
printf '\n   ✅  Connected: /workspaces/%s%s\n\n' "$dir" "${origin:+  →  ${origin}}"

# 7. Put THIS terminal in the repo too. Step 6 switches the Explorer, and NEW
#    terminals then open in the repo on their own (verified 2026-10-30: with
#    the Explorer on the repo, a fresh terminal starts there with no help —
#    which is why the old "auto-cd" .bashrc hook that cd'd new terminals out
#    of the launcher was removed that day as dead code). But the terminal that
#    ran this script is still sitting in codespace-starter, so `claude`/`codex`
#    typed right now would write to the launcher — invisibly, since the
#    Explorer shows the repo. A script can't cd its parent shell, so we replace
#    this shell with a fresh one rooted in the repo. Only when attached to a
#    terminal (skip in non-interactive/CI runs). Must be LAST: exec never
#    returns. `exit` later drops back to the launcher.
if [[ -t 1 ]]; then
  cd "/workspaces/$dir"
  exec bash
fi
