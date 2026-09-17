#!/usr/bin/env bash
#
# welcome.sh — the "your Codespace is ready" signal.
#
# Wired to postAttachCommand (NOT postStartCommand). This matters: in
# Codespaces, postStartCommand output is routed to the hidden creation log, so
# a banner there is invisible to students. postAttachCommand runs in a visible
# terminal, and because the lifecycle order is postCreate → postStart →
# postAttach, it fires only after the slow `pak` install has finished — so the
# banner doubles as a genuine "setup is done" signal.
#
# Note: `-u` and `pipefail` but deliberately NOT `-e`. This is a best-effort
# banner/onboarding script; a failure in the Workspace Trust config step below
# (e.g. node missing, unwritable settings) must NOT abort the script and rob the
# student of the "your Codespace is ready" banner. Steps guard themselves.
set -uo pipefail

# Disable VS Code Workspace Trust for this Codespace. Without this, a repo a
# student opens via File → Open Folder starts in Restricted Mode (VS Code hasn't
# "trusted" that folder): they get a "do you trust the authors?" prompt, and
# Restricted Mode can suppress settings/features. Disabling trust lets the
# Codespace's Machine-scope settings (arf console, autosave, git settings, …)
# apply cleanly to whatever folder the student opens — which is exactly why
# connect-repo no longer needs to seed a per-repo .vscode/settings.json (see its
# NOTE). A Codespace is an isolated, managed container GitHub already
# auto-trusts, so turning the check off is safe. It's an application-scoped
# setting, so it must live in VS Code's *user* settings — it can't go in
# devcontainer/workspace settings (those are ignored for it).
#
# TIMING: this runs at postAttachCommand, AFTER the first window has attached
# and already shown the trust prompts — so on its own it only helps later
# folder opens. Since image v1.1.5 the same file is BAKED into the image, so
# the prompts never fire; this write is belt-and-suspenders for older images
# and self-heals if the file is ever removed. Idempotent: skips when the key is
# present. (An earlier version of this comment blamed Restricted Mode for the
# "run git fetch automatically?" popup — wrong: that popup fires whenever
# git.autofetch is not `true`; see the comment on that setting in
# devcontainer.json.)
user_settings="$HOME/.vscode-remote/data/User/settings.json"
if command -v node >/dev/null 2>&1 && ! grep -qs 'workspace.trust.enabled' "$user_settings"; then
  mkdir -p "$(dirname "$user_settings")"
  node -e '
    const fs = require("fs"), p = process.argv[1];
    let o = {};
    try { o = JSON.parse(fs.readFileSync(p, "utf8") || "{}"); } catch (e) {}
    o["security.workspace.trust.enabled"] = false;
    fs.writeFileSync(p, JSON.stringify(o, null, 2) + "\n");
  ' "$user_settings"
fi

# NOTE: the R Tutorials extension (PPBDS.vscode-r-tutorials) is NOT installed
# here. An attach-time `code --install-extension` (tried, 2026-07) leaves the
# Activity Bar icon missing until the student reloads the window — and the
# first attempt silently installed nothing (the code CLI treats a path
# without a .vsix suffix as a marketplace identifier). The extension is baked
# into the image instead (RT_EXT_VERSION in the PPBDS/devcontainers
# Dockerfile), pre-extracted from the Open VSX .vsix so the icon exists from
# first paint.

# Give students a short terminal prompt: just the current folder name + "$",
# e.g. "my-class-work $". The default devcontainers/Codespaces prompt is long
# ("@user ➜ /workspaces/full/path (branch) $") — too much for beginners. It
# rebuilds PS1 on every render via PROMPT_COMMAND, so we override BOTH (clear
# PROMPT_COMMAND, set PS1) at the END of ~/.bashrc, where last-word-wins. We
# keep the folder name on purpose: it reinforces "which repo am I in?" — the
# same orientation connect-repo's auto-cd is about. Applies to new terminals
# (bashrc runs at shell start). Idempotent via the sentinel.
if ! grep -qF 'codespace-starter:short-prompt' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'BASHRC'

# codespace-starter:short-prompt — short prompt for beginners (folder name + $).
PROMPT_COMMAND=''
PS1='\W \$ '
BASHRC
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # codespace-starter/.devcontainer
marker="$HOME/.student_repo"

# Students run `connect-repo <name>` — a wrapper in ~/.local/bin, which is
# already on PATH in every student shell (the image's tool installers append
# it to the profile, and Ubuntu's stock ~/.profile picks it up too). A wrapper,
# NOT a symlink: connect-repo.sh locates itself via BASH_SOURCE, and through a
# symlink it would resolve to ~/.local/bin and break; `exec` by absolute path
# keeps the real location. Rewritten on every attach (cheap, self-healing).
# The long-form `.devcontainer/connect-repo.sh` still works from the starter
# folder; the wrapper additionally works from ANY folder, including the
# student's own repo after they switch.
mkdir -p "$HOME/.local/bin"
printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$here/connect-repo.sh" \
  > "$HOME/.local/bin/connect-repo"
chmod +x "$HOME/.local/bin/connect-repo"

# The banner advertises the short command ONLY if the wrapper really landed
# (this script is deliberately non-fatal, so a failed install above must not
# leave the banner teaching a command that won't work — Copilot review, PR
# #50). Fallback is the long form, which always works from the starter folder.
cmd="connect-repo"
if [[ ! -x "$HOME/.local/bin/connect-repo" ]]; then
  cmd=".devcontainer/connect-repo.sh"
fi

# Provenance line, read LIVE from the launcher checkout so it can never drift
# from reality: the image pin straight from devcontainer.json, and the date of
# this repo's last commit — which also captures VS Code settings / script
# changes, i.e. "the setup state this Codespace was born from". Printed ABOVE
# the banner box on purpose (David, 2026-08-15): it is instructor-facing
# metadata, not student instructions. Both reads are guarded; on any failure
# the line is simply omitted, never an error.
img="$(grep -o 'ghcr\.io/ppbds/devcontainer:[0-9][0-9.]*' "$here/devcontainer.json" 2>/dev/null | head -1)"
upd="$(git -C "$here/.." log -1 --format='%cd' --date=format:'%Y-%m-%d' 2>/dev/null)"
prov=""
if [[ -n "$img" ]]; then
  prov="   ${img}${upd:+ · setup updated ${upd}}"
fi

# postAttachCommand always runs in the codespace-starter folder (not the
# student's open folder), so we can't detect progress by directory. connect-repo.sh
# drops a marker once a repo has been created; until then, show the "how to
# start" banner. Once a repo exists there's nothing more to say — stay silent
# (no returning banner; the short prompt already shows which folder you're in).
if [[ ! -f "$marker" ]]; then
  [[ -n "$prov" ]] && printf '\n%s\n' "$prov"
  cat <<BANNER

════════════════════════════════════════════════════════════
   ✅  YOUR CODESPACE IS READY

   Start your own project (creates a new repo):

       ${cmd} <insert-repo-name>
════════════════════════════════════════════════════════════

BANNER
fi
