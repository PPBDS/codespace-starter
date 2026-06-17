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

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the .devcontainer dir

cat <<BANNER

════════════════════════════════════════════════════════════
   ✅  YOUR CODESPACE IS READY

   Start your own project (creates + opens a new repo):
       bash ${here}/make_repo.sh <repo-name>

   Full guide: .devcontainer/STUDENT_WORKFLOW.md (opening now)
════════════════════════════════════════════════════════════

BANNER

# Open the guide once per Codespace, so students land on instructions the first
# time without it reopening every time they resume.
marker="$HOME/.welcomed"
guide="$here/STUDENT_WORKFLOW.md"
if [[ ! -f "$marker" && -f "$guide" ]] && command -v code >/dev/null 2>&1; then
  code "$guide" || true
  touch "$marker"
fi
