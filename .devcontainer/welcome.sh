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
launchpad="$(dirname "$here")"                          # the codespace-starter launchpad folder
guide="$here/STUDENT_WORKFLOW.md"

# postAttachCommand runs with the currently-open folder as its working
# directory, so $PWD tells us where the student is. On the launchpad
# (codespace-starter) we nudge them to create a repo; once they've moved into
# their own repo we switch to a "you're set up, here's how to save" banner.
if [[ "${PWD:-$launchpad}" == "$launchpad" ]]; then
  cat <<BANNER

════════════════════════════════════════════════════════════
   ✅  YOUR CODESPACE IS READY

   Start your own project (creates + opens a new repo):
       bash ${here}/make_repo.sh <repo-name>

   Full guide: ${guide}

   Type \`clear\` to remove this banner.
════════════════════════════════════════════════════════════

BANNER
else
  repo="$(basename "${PWD}")"
  cat <<BANNER

════════════════════════════════════════════════════════════
   📂  You're working in:  ${repo}

   Save your work:     commit + push  (Source Control panel, left)
   Publish a graphic:  see ${guide}

   Type \`clear\` to remove this banner.
════════════════════════════════════════════════════════════

BANNER
fi
