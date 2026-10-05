#!/usr/bin/env bash
#
# setup.sh — one-time per-Codespace installs, run from devcontainer.json's
# onCreateCommand. That hook runs at PREBUILD time (or at create, when no
# prebuild is available), so everything here is in place before the first
# terminal ever opens. Its output goes to the hidden creation log, which is
# fine: this script prints nothing a student needs to see. The student-facing
# "your Codespace is ready" banner is welcome.sh, which the .bashrc hook
# installed below runs in the first terminal.
#
# History: until 2026-10 all of this lived in welcome.sh under a
# postAttachCommand, which created a SECOND terminal ("Codespaces: Welcome!")
# next to the one Codespaces opens on its own. Students asked why there were
# two, the default one carried a "⚠ extensions want to relaunch" warning no
# setting could suppress, and the image needed a first-run notice to bridge
# the gap before postAttach fired. Printing the banner from .bashrc in the
# terminal that exists anyway removes all three problems at once.
#
# `-u` and `pipefail` but deliberately NOT `-e`: best-effort. A failure in one
# step must not abort the others. Every step is idempotent, so re-running
# (a container rebuild, a manual invocation) is safe.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # codespace-starter/.devcontainer
bashrc="$HOME/.bashrc"

# 1. The `connect-repo` wrapper in ~/.local/bin, which is already on PATH in
#    every student shell (the image's tool installers append it to the
#    profile, and Ubuntu's stock ~/.profile picks it up too). A wrapper, NOT a
#    symlink: connect-repo.sh locates itself via BASH_SOURCE, and through a
#    symlink it would resolve to ~/.local/bin and break; `exec` by absolute
#    path keeps the real location. The long-form `.devcontainer/connect-repo.sh`
#    still works from the starter folder; the wrapper additionally works from
#    ANY folder, including the student's own repo after they switch.
mkdir -p "$HOME/.local/bin"
printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$here/connect-repo.sh" \
  > "$HOME/.local/bin/connect-repo"
chmod +x "$HOME/.local/bin/connect-repo"

# 2. A short terminal prompt: just the current folder name + "$", e.g.
#    "my-class-work $". The default devcontainers/Codespaces prompt is long
#    ("@user ➜ /workspaces/full/path (branch) $") — too much for beginners. It
#    rebuilds PS1 on every render via PROMPT_COMMAND, so we override BOTH
#    (clear PROMPT_COMMAND, set PS1) at the END of ~/.bashrc, where last-word-
#    wins. We keep the folder name on purpose: it reinforces "which repo am I
#    in?" — the same orientation connect-repo's auto-cd is about. Idempotent
#    via the sentinel. (A student's own dotfiles install runs AFTER this, at
#    Codespace create, so a dotfiles PS1 appended there wins — as it should.)
if ! grep -qF 'codespace-starter:short-prompt' "$bashrc" 2>/dev/null; then
  cat >> "$bashrc" <<'BASHRC'

# codespace-starter:short-prompt — short prompt for beginners (folder name + $).
PROMPT_COMMAND=''
PS1='\W \$ '
BASHRC
fi

# 3. The banner hook: every interactive shell runs welcome.sh, which prints the
#    ready banner until connect-repo has been run (it reads ~/.student_repo
#    and prints nothing once that marker exists). Gated on an interactive
#    shell only — the R console (arf) is launched directly, not via bash, so
#    it never sees this; task terminals are non-interactive. VS Code may
#    silently relaunch the first terminal once extensions have activated
#    (the default behavior); that re-runs .bashrc and simply reprints the
#    banner, which is exactly what we want. The path is baked in absolute via
#    %q so the hook keeps working from any folder the student switches to.
#    Idempotent via the sentinel.
if ! grep -qF 'codespace-starter:banner' "$bashrc" 2>/dev/null; then
  {
    printf '\n# codespace-starter:banner — the "your Codespace is ready" banner (see .devcontainer/welcome.sh).\n'
    printf 'if [[ $- == *i* && -r %q ]]; then bash %q; fi\n' "$here/welcome.sh" "$here/welcome.sh"
  } >> "$bashrc"
fi
