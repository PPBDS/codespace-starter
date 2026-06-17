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
set -uo pipefail

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
   📂  Your project repo:  ${repo}

   Open it:  File → Open Folder → /workspaces/${repo}
   Save:     commit + push  (Source Control panel, left)
   Guide:    ${guide}

   Type \`clear\` to remove this banner.
════════════════════════════════════════════════════════════

BANNER
else
  cat <<BANNER

════════════════════════════════════════════════════════════
   ✅  YOUR CODESPACE IS READY

   Start your own project (creates a new repo):
       bash ${here}/make_repo.sh <repo-name>

   Full guide: ${guide}

   Type \`clear\` to remove this banner.
════════════════════════════════════════════════════════════

BANNER
fi
