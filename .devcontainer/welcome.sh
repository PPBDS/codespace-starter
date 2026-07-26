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
# Restricted Mode can suppress settings/features — e.g. the "run git fetch
# automatically?" prompt reappears. Disabling trust lets the Codespace's
# Machine-scope settings (arf console, autosave, git.autofetch off, …) apply
# cleanly to whatever folder the student opens — which is exactly why
# connect-repo no longer needs to seed a per-repo .vscode/settings.json (see its
# NOTE). A Codespace is an isolated, managed container GitHub already
# auto-trusts, so turning the check
# off is safe. It's an application-scoped setting, so it must live in VS Code's
# *user* settings — it can't go in devcontainer/workspace settings (those are
# ignored for it). Idempotent: only written once.
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

# Install the R Tutorials extension from Open VSX, pinned by version. It is
# deliberately NOT in devcontainer.json's "extensions" list: that list is
# resolved by VS Code against the Microsoft Marketplace only (official VS Code
# cannot read Open VSX), and we publish this extension to Open VSX — the
# Marketplace publish flow is not worth the pain (David, 2026-07). Open VSX
# serves the .vsix at a stable versioned URL, and the `code` CLI (available at
# attach time, which is why this lives here and not in postCreate) installs it
# into the remote. The pin means no auto-update: to ship a new version,
# publish to Open VSX, then bump RT_VERSION here — a launcher-only change.
# Idempotent: skipped when this exact version is already installed, so it
# costs one grep on every re-attach and a ~seconds download on the first.
RT_VERSION="1.0.0"
if command -v code >/dev/null 2>&1 \
   && ! code --list-extensions --show-versions 2>/dev/null | grep -qi "^ppbds\.vscode-r-tutorials@${RT_VERSION}$"; then
  rt_vsix="$(mktemp -t rt-vsix-XXXXXX)"
  rt_url="https://open-vsx.org/api/PPBDS/vscode-r-tutorials/${RT_VERSION}/file/PPBDS.vscode-r-tutorials-${RT_VERSION}.vsix"
  if curl -fsSL -o "$rt_vsix" "$rt_url" && code --install-extension "$rt_vsix" >/dev/null 2>&1; then
    echo "→ Installed R Tutorials extension v${RT_VERSION}."
  else
    echo "! Could not install the R Tutorials extension (v${RT_VERSION}) — tutorials may not render. Re-attach to retry, or tell your instructor."
  fi
  rm -f "$rt_vsix"
fi

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
guide="$here/STUDENT_WORKFLOW.md"
marker="$HOME/.student_repo"

# postAttachCommand always runs in the codespace-starter folder (not the
# student's open folder), so we can't detect progress by directory. connect-repo.sh
# drops a marker once a repo has been created; until then, show the "how to
# start" banner. Once a repo exists there's nothing more to say — stay silent
# (no returning banner; the short prompt already shows which folder you're in).
if [[ ! -f "$marker" ]]; then
  cat <<BANNER

════════════════════════════════════════════════════════════
   ✅  YOUR CODESPACE IS READY

   Start your own project (creates a new repo):
       .devcontainer/connect-repo.sh <repo-name>

   Full guide: ${guide}

   Type \`clear\` to remove this banner.
════════════════════════════════════════════════════════════

BANNER
fi
