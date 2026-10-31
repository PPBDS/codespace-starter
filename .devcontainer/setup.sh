#!/usr/bin/env bash
#
# setup.sh — one-time per-Codespace installs, run from devcontainer.json's
# onCreateCommand. That hook runs at PREBUILD time (or at create, when no
# prebuild is available), so everything here is in place before the first
# terminal ever opens. Its output goes to the hidden creation log, which is
# fine: this script prints nothing a student needs to see. The student-facing
# "your Codespace is ready" banner is welcome.sh, which the bashrc.d snippet
# installed below runs in the first terminal.
#
# WHAT IT LEAVES BEHIND (2026-10-30 consolidation): everything the starter adds
# to the student's home directory lives in ONE place, ~/.config/codespace-starter:
#   bashrc.d/10-prompt.sh   the short prompt
#   bashrc.d/20-banner.sh   the hook that runs welcome.sh
#   (connect-repo later adds 30-github-token.sh and the student-repo
#   marker; welcome.sh adds banner-shown)
# plus ONE block appended to ~/.bashrc that sources bashrc.d/*.sh, and the
# `connect-repo` wrapper in ~/.local/bin. Nothing else is written to ~/.bashrc
# by any starter script, so the file reads: the image's own lines, our one
# block, then whatever the student's dotfiles append. Snippet files are
# rewritten whole on every run (no sentinels needed); only the .bashrc block
# is guarded, so it is appended exactly once.
#
# History: until 2026-10 all of this lived in welcome.sh under a
# postAttachCommand, which created a SECOND terminal ("Codespaces: Welcome!")
# next to the one Codespaces opens on its own. Students asked why there were
# two, the default one carried a "⚠ extensions want to relaunch" warning no
# setting could suppress, and the image needed a first-run notice to bridge
# the gap before postAttach fired. Printing the banner from .bashrc in the
# terminal that exists anyway removes all three problems at once. Until
# 2026-10-30 the prompt and banner blocks were appended to ~/.bashrc directly,
# and connect-repo appended two more; three writers to one file made it hard
# to tell the student's lines from ours, hence bashrc.d.
#
# `-u` and `pipefail` but deliberately NOT `-e`: best-effort. A failure in one
# step must not abort the others. Every step is idempotent, so re-running
# (a container rebuild, a manual invocation) is safe.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # codespace-starter/.devcontainer
bashrc="$HOME/.bashrc"
state_dir="$HOME/.config/codespace-starter"
bashrc_d="$state_dir/bashrc.d"

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

mkdir -p "$bashrc_d"

# 2. A short terminal prompt: just the current folder name + "$", e.g.
#    "my-class-work $". The default devcontainers/Codespaces prompt is long
#    ("@user ➜ /workspaces/full/path (branch) $") — too much for beginners. It
#    rebuilds PS1 on every render via PROMPT_COMMAND, so we override BOTH
#    (clear PROMPT_COMMAND, set PS1). Our block sits at the END of ~/.bashrc,
#    where last-word-wins. We keep the folder name on purpose: it reinforces
#    "which repo am I in?". (A student's own dotfiles install runs AFTER this, at Codespace
#    create, so a dotfiles PS1 appended below our block wins — as it should.)
cat > "$bashrc_d/10-prompt.sh" <<'SNIPPET'
# codespace-starter — a short prompt for beginners: the current folder name + $.
PROMPT_COMMAND=''
PS1='\W \$ '
SNIPPET

# 3. The banner hook: every interactive shell runs welcome.sh, and welcome.sh
#    decides whether to print — once per Codespace (its own "shown" marker,
#    delayed ten seconds to survive a VS Code relaunch of the first
#    terminal) and never after connect-repo (the student-repo marker). All of
#    that logic lives in welcome.sh so this hook stays a one-liner. Gated on an
#    interactive shell WITH a terminal on stdout (-t 1): the devcontainer
#    tooling probes the user's environment by spawning an interactive login
#    shell (userEnvProbe, default loginInteractiveShell) — with only the
#    interactive test, that invisible probe shell printed the banner and
#    burned its one showing before the student's first real terminal opened
#    (2026-10-05, v1.1.7 rollout). The base image's first-run hook uses the
#    same -t 1 guard for the same reason. The R console (arf) is launched
#    directly, not via bash, so it never sees this; task terminals are
#    non-interactive. CODESPACE_STARTER_BANNER_FORCE=1 bypasses the tty test
#    for the CI tests, which run bash -i without a pty. The path is baked in
#    absolute via %q so the hook keeps working from any folder the student
#    switches to.
{
  printf '# codespace-starter — the "your Codespace is ready" banner, shown once (see .devcontainer/welcome.sh).\n'
  # shellcheck disable=SC2016  # the ${…} is meant literally: it is evaluated by the student's shell, not here
  printf 'if [[ $- == *i* && ( -t 1 || -n ${CODESPACE_STARTER_BANNER_FORCE:-} ) && -r %q ]]; then bash %q; fi\n' "$here/welcome.sh" "$here/welcome.sh"
} > "$bashrc_d/20-banner.sh"

# 4. The ONE block in ~/.bashrc: source every snippet in bashrc.d, in name
#    order. Appended once (sentinel), at the end of the file as it stands at
#    create. Written so a student who runs `cat ~/.bashrc` can see where the
#    starter's lines stop and theirs begin. The glob stays literal when the
#    directory is empty, and -r then fails, so an empty bashrc.d is harmless.
if ! grep -qF 'codespace-starter:bashrc.d' "$bashrc" 2>/dev/null; then
  cat >> "$bashrc" <<'BASHRC'

# codespace-starter:bashrc.d — everything codespace-starter adds to your shell,
# one file per thing, in ~/.config/codespace-starter/bashrc.d. Nothing of the
# starter's is below this block; your own additions belong after it.
for __f in "$HOME"/.config/codespace-starter/bashrc.d/*.sh; do
  [[ -r $__f ]] && . "$__f"
done
unset __f
BASHRC
fi
