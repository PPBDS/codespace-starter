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
# cleanly to whatever folder the student opens — which is exactly why make_repo
# no longer needs to seed a per-repo .vscode/settings.json (see its NOTE).
# (Same mechanism as Gemini's "untrusted folder" skip.) A Codespace is an
# isolated, managed container GitHub already auto-trusts, so turning the check
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

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # codespace-starter/.devcontainer
guide="$here/STUDENT_WORKFLOW.md"
marker="$HOME/.student_repo"

# postAttachCommand always runs in the codespace-starter folder (not the
# student's open folder), so the banner can't detect progress by directory.
# Instead, make_repo.sh drops a marker once a repo has been created; we key the
# banner off that — nudge to create one until it exists, then point at it.
if [[ -f "$marker" ]]; then
  repo="$(cat "$marker" 2>/dev/null || true)"
  cat <<BANNER

════════════════════════════════════════════════════════════
   📂  Your repo: ${repo}

   • Explorer shows ${repo}?  You're in it — commit & push via
     the Source Control panel (left).
   • If not:  File → Open Folder → /workspaces/${repo}

   Guide: ${guide}
   Type \`clear\` to remove this banner.
════════════════════════════════════════════════════════════

BANNER
else
  cat <<BANNER

════════════════════════════════════════════════════════════
   ✅  YOUR CODESPACE IS READY

   Start your own project (creates a new repo):
       .devcontainer/make_repo.sh <repo-name>

   Full guide: ${guide}

   Type \`clear\` to remove this banner.
════════════════════════════════════════════════════════════

BANNER
fi
