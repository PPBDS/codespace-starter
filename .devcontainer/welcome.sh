#!/usr/bin/env bash
#
# welcome.sh — the "your Codespace is ready" banner.
#
# Run by a hook at the end of ~/.bashrc (installed by setup.sh from
# onCreateCommand), so it prints in the FIRST terminal Codespaces opens, and
# only there: later terminals start clean (David, 2026-10-05). Two markers
# make it quiet:
#   - ~/.student_repo (written by connect-repo): the student has a repo, so
#     there is nothing to say; connect-repo reports the connected repo itself.
#   - ~/.config/codespace-starter/banner-shown: the banner has been printed
#     once in this Codespace. It is touched TEN SECONDS after printing, from
#     a detached background sleep, not immediately — the same trick the
#     devcontainers base uses for its first-run notice — so that if VS Code
#     silently relaunches the first terminal a few seconds in (it does that
#     when extensions contribute environment variables, and the relaunch
#     wipes the scrollback), the re-run .bashrc prints the banner again
#     instead of leaving a blank terminal. Any terminal opened later than
#     that is clean. (Tests shorten the delay via
#     CODESPACE_STARTER_BANNER_DELAY.)
#
# Why .bashrc and not a postAttachCommand (the design until 2026-10): a
# postAttach terminal is a SECOND terminal beside the one Codespaces opens on
# its own, and the default one carried a relaunch warning no setting could
# suppress. See setup.sh for the history. Because this now runs on every
# shell start it must be fast and quiet: two guarded reads, no installs, no
# network.
#
# `-u` and `pipefail` but deliberately NOT `-e`: a failed provenance read must
# not rob the student of the banner. Steps guard themselves.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # codespace-starter/.devcontainer
marker="$HOME/.student_repo"
shown="$HOME/.config/codespace-starter/banner-shown"

# Once connect-repo has run, or once the banner has had its one showing,
# there is nothing to say.
[[ -f "$marker" || -f "$shown" ]] && exit 0

# Schedule the "shown" marker (see the header for why it is delayed). The
# doubled parentheses detach the sleeper from the interactive shell's job
# control so the student never sees a "[1]+ Done" line. Best-effort: if the
# directory can't be made, the banner simply shows again next time.
mkdir -p "$(dirname "$shown")" 2>/dev/null && \
  ( ( sleep "${CODESPACE_STARTER_BANNER_DELAY:-10}"; touch "$shown" ) >/dev/null 2>&1 & )

# The banner advertises the short command ONLY if the wrapper really landed
# (setup.sh is deliberately non-fatal, so a failed install there must not
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
if [[ -n "$img" ]]; then
  printf '\n   %s%s\n' "$img" "${upd:+ · setup updated ${upd}}"
fi

cat <<BANNER

════════════════════════════════════════════════════════════
   ✅  YOUR CODESPACE IS READY

   Start your own project (creates a new repo):

       ${cmd} <insert-repo-name>
════════════════════════════════════════════════════════════

BANNER
