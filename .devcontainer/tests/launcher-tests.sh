#!/usr/bin/env bash
#
# launcher-tests.sh — CI tests for the launcher scripts (setup.sh, welcome.sh
# and the connect-repo wrapper). Run INSIDE the student image (see
# .github/workflows/launcher-tests.yml), where setup.sh's $HOME side effects
# (wrapper install, .bashrc appends) land in a throwaway container home.
#
# Also runnable locally — but ONLY with a sandbox HOME, or it will edit your
# real ~/.bashrc:   HOME=$(mktemp -d) bash .devcontainer/tests/launcher-tests.sh
#
# Scope: everything testable without a GitHub login. connect-repo's real work
# (gh auth, repo creation, the closing "Connected:" line) is deliberately out
# of scope — that stays a manual check in a live Codespace.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # .devcontainer
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
ok()   { echo "  ok: $*"; }

# ---- setup.sh: wrapper + two .bashrc blocks, idempotent --------------------
rm -f "$HOME/.student_repo"
if ! bash "$here/setup.sh"; then
  fail "setup.sh exited non-zero"
fi
bash "$here/setup.sh" >/dev/null 2>&1 || true   # second run must be a no-op

wrapper="$HOME/.local/bin/connect-repo"
if [[ -x "$wrapper" ]]; then
  ok "wrapper installed and executable"
else
  fail "wrapper missing or not executable at $wrapper"
fi

n="$(grep -cF 'codespace-starter:short-prompt' "$HOME/.bashrc" 2>/dev/null || true)"
if [[ "$n" -eq 1 ]]; then
  ok "prompt block appended exactly once after two runs"
else
  fail "prompt block count in .bashrc is $n, expected 1"
fi

n="$(grep -cF 'codespace-starter:banner' "$HOME/.bashrc" 2>/dev/null || true)"
if [[ "$n" -eq 1 ]]; then
  ok "banner hook appended exactly once after two runs"
else
  fail "banner hook count in .bashrc is $n, expected 1"
fi

# Retired side effects must stay retired (one-terminal design, 2026-10).
if grep -qs 'workspace.trust' "$HOME/.vscode-remote/data/User/settings.json"; then
  fail "a trust setting was written again (dead code — see devcontainer.json)"
else
  ok "no trust setting written"
fi

# ---- welcome.sh with no markers: banner ---------------------------------
# The "shown" marker is normally touched 10 s after printing; the tests set
# the delay to 0 so it lands immediately, and clear it before every run that
# expects a banner.
shown="$HOME/.config/codespace-starter/banner-shown"
export CODESPACE_STARTER_BANNER_DELAY=0
# The hook also requires a terminal on stdout (so the devcontainer env probe's
# invisible interactive shell never consumes the one showing); CI has no pty,
# so the tests opt out of that one test explicitly. The probe case itself is
# tested below by NOT setting it.
export CODESPACE_STARTER_BANNER_FORCE=1
rm -f "$shown"
if ! out="$(bash "$here/welcome.sh")"; then
  fail "welcome.sh exited non-zero"
fi

if grep -q "YOUR CODESPACE IS READY" <<<"$out"; then
  ok "banner shows READY"
else
  fail "banner missing 'YOUR CODESPACE IS READY'"
fi

if grep -q "connect-repo <insert-repo-name>" <<<"$out"; then
  ok "banner shows the short command"
else
  fail "banner missing 'connect-repo <insert-repo-name>'"
fi

if grep -q "ghcr.io/ppbds/devcontainer:" <<<"$out"; then
  ok "provenance line names the image pin"
else
  fail "provenance line missing (devcontainer.json pin unreadable?)"
fi

# Retired lines must stay retired (redesign, 2026-08-15).
if grep -q "STUDENT_WORKFLOW" <<<"$out"; then
  fail "banner links the guide again (removed in redesign)"
else
  ok "banner has no guide link"
fi
if grep -q "remove this banner" <<<"$out"; then
  fail "banner mentions 'clear' again (removed in redesign)"
else
  ok "banner has no clear-hint"
fi

# ---- banner once: the "shown" marker ------------------------------------
# Printing must schedule the marker (delay 0 here, so it lands at once), and
# the marker must silence every later run — this is "banner only in the
# first terminal" (David, 2026-10-05).
sleep 1
if [[ -f "$shown" ]]; then
  ok "shown marker written after the banner printed"
else
  fail "shown marker missing after the banner printed: $shown"
fi
out_again="$(bash "$here/welcome.sh")"
if [[ -z "$out_again" ]]; then
  ok "welcome.sh is silent once the shown marker exists"
else
  fail "welcome.sh printed again despite the shown marker: $out_again"
fi

# ---- the .bashrc hook end to end ----------------------------------------
# An interactive bash with this HOME must print the banner from the hook
# setup.sh installed — this is the whole delivery path now that there is no
# postAttach terminal. (-i without a tty makes bash grumble on stderr about
# job control; that is noise, hence 2>/dev/null.) Then, with the marker it
# just wrote, a second interactive shell must be clean.
rm -f "$shown"
hook_out="$(bash -ic 'true' 2>/dev/null || true)"
if grep -q "YOUR CODESPACE IS READY" <<<"$hook_out"; then
  ok "first interactive shell prints the banner via the .bashrc hook"
else
  fail "interactive shell did not print the banner (hook broken?)"
fi
sleep 1
hook_out_2="$(bash -ic 'true' 2>/dev/null || true)"
if grep -q "YOUR CODESPACE IS READY" <<<"$hook_out_2"; then
  fail "second interactive shell printed the banner again"
else
  ok "second interactive shell is clean"
fi

# The env-probe case: an interactive shell WITHOUT a terminal on stdout (what
# userEnvProbe spawns) must neither print nor consume the one showing.
rm -f "$shown"
probe_out="$(CODESPACE_STARTER_BANNER_FORCE='' bash -ic 'true' 2>/dev/null || true)"
if grep -q "YOUR CODESPACE IS READY" <<<"$probe_out"; then
  fail "a non-tty interactive shell (env probe) printed the banner"
else
  ok "non-tty interactive shell (env probe) prints nothing"
fi
sleep 1
if [[ -f "$shown" ]]; then
  fail "the env-probe shell consumed the banner's one showing"
else
  ok "env-probe shell did not consume the one showing"
fi

# ---- wrapper ------------------------------------------------------------
# From a foreign directory: args must forward, and the real script must still
# self-locate (this is why it's an exec wrapper, not a symlink — see setup.sh).
if (cd /tmp && "$wrapper" --help | grep -q "connect-repo — create or connect"); then
  ok "wrapper --help works from a foreign directory"
else
  fail "wrapper --help failed from a foreign directory"
fi

# No-argument path: exit 2 with the short-form usage text.
rc=0
usage_out="$(cd /tmp && "$wrapper" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "no-arg run exits 2"
else
  fail "no-arg run exited $rc, expected 2"
fi
if grep -q "Usage: connect-repo " <<<"$usage_out"; then
  ok "usage text uses the short name"
else
  fail "usage text is not short-form: $usage_out"
fi

# ---- welcome.sh with marker: silence ------------------------------------
# connect-repo reports the connected repo itself; once its marker exists the
# banner must print nothing at all, in the hook and when run directly.
echo "test-repo" > "$HOME/.student_repo"
rm -f "$shown"
out2="$(bash "$here/welcome.sh")"
if [[ -z "$out2" ]]; then
  ok "welcome.sh is silent once the marker exists"
else
  fail "welcome.sh printed with the marker present: $out2"
fi
hook_out2="$(bash -ic 'true' 2>/dev/null || true)"
if grep -q "YOUR CODESPACE IS READY" <<<"$hook_out2"; then
  fail "interactive shell still prints the banner with the marker present"
else
  ok "interactive shell is quiet once the marker exists"
fi
rm -f "$HOME/.student_repo"

# ---- wrapper-install failure: banner must fall back to the long form ----
# Simulate the install failing by making $HOME/.local/bin a regular FILE
# (mkdir -p then fails even as root). setup.sh is non-fatal by design, so the
# banner must then advertise the long-form command instead of a
# `connect-repo` that doesn't exist (Copilot review, PR #50).
sandbox="$(mktemp -d)"
mkdir -p "$sandbox/.local"
: > "$sandbox/.local/bin"
HOME="$sandbox" bash "$here/setup.sh" >/dev/null 2>&1 || true
out3="$(HOME="$sandbox" bash "$here/welcome.sh" 2>/dev/null)"
if grep -qF ".devcontainer/connect-repo.sh <insert-repo-name>" <<<"$out3"; then
  ok "banner falls back to long form when wrapper install fails"
else
  fail "banner did not fall back to the long form on wrapper failure"
fi
if grep -qF " connect-repo <insert-repo-name>" <<<"$out3"; then
  fail "banner still shows the short command despite failed wrapper install"
else
  ok "banner hides the short command on wrapper failure"
fi
rm -rf "$sandbox"

# ---- devcontainer.json wiring -------------------------------------------
# Guards the intent only (the effects are client behaviors, verified live).
# shellcheck disable=SC2016  # ${containerWorkspaceFolder} is literal JSON text, not a shell expansion
if grep -qF '"onCreateCommand": "bash ${containerWorkspaceFolder}/.devcontainer/setup.sh"' "$here/devcontainer.json"; then
  ok "onCreateCommand runs setup.sh"
else
  fail "onCreateCommand does not run setup.sh (nothing would install the banner hook)"
fi
# (environmentChangesIndicator is in this list because VS Code deleted the
# setting in 2025-10; re-adding it would be dead config.)
for key in postAttachCommand terminal.integrated.hideOnStartup terminal.integrated.environmentChangesRelaunch terminal.integrated.environmentChangesIndicator; do
  if grep -E "^\s*\"$key\"" "$here/devcontainer.json" >/dev/null; then
    fail "$key is set again (two startup terminals / dead relaunch config would return)"
  else
    ok "$key is not set"
  fi
done
# vscode-R 3.0 settings (image v1.1.7+): the 2.x keys are deprecated and
# r.plot.useHttpgd would silently lose to r.plot.backend; guard the rename.
for key in r.rterm.linux r.plot.useHttpgd; do
  if grep -E "^\s*\"$key\"" "$here/devcontainer.json" >/dev/null; then
    fail "$key is back (deprecated in vscode-R 3.0; use r.consolePath / r.plot.backend)"
  else
    ok "$key is not set (3.0 rename)"
  fi
done
if grep -qF '"r.consolePath": "/usr/local/bin/arf"' "$here/devcontainer.json" \
   && grep -qF '"r.plot.backend": "httpgd"' "$here/devcontainer.json" \
   && grep -qF '"rTutorials.closeWelcomeOnStartup": true' "$here/devcontainer.json"; then
  ok "3.0 console/plot settings + Welcome-tab close are set"
else
  fail "r.consolePath / r.plot.backend / rTutorials.closeWelcomeOnStartup missing"
fi
pinned="$(grep -oE '"reditorsupport\.r@[0-9]+\.[0-9]+\.[0-9]+"' "$here/devcontainer.json" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
if [[ -n "$pinned" ]]; then
  ok "vscode-R is version-pinned ($pinned)"
else
  fail "vscode-R is not version-pinned (an unpinned entry auto-updates and can break plots)"
fi
# Lockstep with the image (Copilot, PR #57): the pin must be the version the
# image BAKES — that .vsix is where the baked sess package came from, so any
# other version risks the "install sess?" prompt. Only checkable inside the
# image (CI); skipped on a laptop.
baked_dir="/home/rstudio/.vscode-remote/extensions"
if [[ -d "$baked_dir" && -n "$pinned" ]]; then
  if [[ -d "$baked_dir/reditorsupport.r-$pinned" ]]; then
    ok "image bakes the pinned vscode-R ($pinned)"
  else
    baked=""
    for d in "$baked_dir"/reditorsupport.r-*; do [[ -d "$d" ]] && baked+="${d##*/} "; done
    fail "pinned vscode-R $pinned is not what the image bakes: ${baked:-nothing}"
  fi
else
  ok "image lockstep check skipped (not running inside the image)"
fi
if grep -qF '"terminal.integrated.initialHint": false' "$here/devcontainer.json"; then
  ok "terminal initial hint (Copilot CLI ghost text) is off"
else
  fail "terminal.integrated.initialHint is not false (the Copilot CLI hint would return)"
fi

# ---- verdict ------------------------------------------------------------
if [[ "$fails" -gt 0 ]]; then
  echo "LAUNCHER TESTS: $fails failure(s)" >&2
  exit 1
fi
echo "LAUNCHER TESTS: all passed"
