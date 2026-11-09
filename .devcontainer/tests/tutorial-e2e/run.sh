#!/usr/bin/env bash
# Tutorial end-to-end test, run INSIDE the pinned student image (see
# .github/workflows/tutorial-e2e.yml). It does what a student does with the
# Orientation tutorial, minus the VS Code window, which nothing headless can
# drive:
#
#   1. learnr2::run_tutorial() serves the tutorial on learnr2's fixed port
#      (the image's pre-rendered copy, re-rendered only if stale).
#   2. A headless browser submits the student-info form, answers every
#      question (text, the integer one, the screenshot-only one) clicking
#      Continue as it goes, and downloads the answers  -> A.json
#   3. The last few answers are blanked to make an unfinished file -> P.json
#   4. learnr2::load_tutorial(P.json) writes its restore page.
#   5. A FRESH browser opens that page, lands on the tutorial with the
#      restored answers submitted, finishes the rest, downloads  -> B.json
#   6. A FRESH browser uses the page's own "Load Answers" button with A.json
#      (the no-R path) and downloads again                        -> C.json
#   7. learnr2::check_submission() confirms every file's fingerprint and that
#      B and C say they were loaded from A.
#
# Why this shape: a student cannot download a partial file through the UI
# (each Continue waits for the answers above it), so "90% then the rest"
# is produced by blanking a complete file. That is also what a file from a
# tutorial that has since gained questions looks like, which load_tutorial()
# documents handling. What this does NOT cover: anything in the VS Code
# layer (the R Tutorials extension, port forwarding, the browser tab).
#
# Runs as root in a container job, so Playwright's apt step needs no sudo.
# Locally: docker run --rm -v "$PWD":/w -w /w ghcr.io/ppbds/devcontainer:<pin> \
#            bash .devcontainer/tests/tutorial-e2e/run.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="${TUTORIAL_E2E_OUT:-/tmp/tutorial-e2e}"
# The image pre-renders every tutorial here (prerender_tutorials() in the
# Dockerfile); learnr2 reuses that render when its stamp is current.
root="${TUTORIAL_E2E_CACHE:-/home/rstudio/.cache/R/learnr2}"
pkg="${TUTORIAL_E2E_PACKAGE:-vscode.tutorials}"
name="${TUTORIAL_E2E_TUTORIAL:-orientation}"
leave="${TUTORIAL_E2E_LEAVE:-3}"
playwright_version="${PLAYWRIGHT_VERSION:-1.64.1}"
port=7446
url="http://127.0.0.1:$port/$pkg/$name/"

mkdir -p "$out"
step() { printf '\n== %s\n' "$*"; }

step "Playwright $playwright_version + Chromium"
venv=/tmp/tutorial-e2e-venv
uv venv -q --python /usr/bin/python3 "$venv"
uv pip install -q --python "$venv/bin/python" "playwright==$playwright_version"
# --with-deps runs apt-get for Chromium's libraries and fonts. The image
# ships no package lists, and one CI run saw "no installation candidate"
# for every package when apt's own update hiccuped, so refresh the lists
# with retries first and give the install itself a second try.
for attempt in 1 2 3; do
  if apt-get update -qq >>"$out/playwright-install.log" 2>&1; then break; fi
  echo "apt-get update failed (attempt $attempt); retrying"; sleep 15
done
installed=false
for attempt in 1 2; do
  if "$venv/bin/playwright" install --with-deps chromium >>"$out/playwright-install.log" 2>&1; then installed=true; break; fi
  echo "playwright install failed (attempt $attempt)"; sleep 15
done
if [ "$installed" != true ]; then
  tail -40 "$out/playwright-install.log"
  exit 1
fi
py="$venv/bin/python"

if [ -n "${TUTORIAL_E2E_LEARNR2:-}" ]; then
  # Development knob (workflow_dispatch input "learnr2"): install a learnr2
  # from GitHub over the baked one, to prove the test against a learnr2 the
  # image does not ship yet. The default run tests the image as students
  # get it. The cached render goes stale (its stamp records the learnr2
  # version), so run_tutorial() re-renders the tutorial first.
  step "Installing learnr2 from $TUTORIAL_E2E_LEARNR2 over the baked copy (development knob)"
  Rscript -e "pak::pkg_install('$TUTORIAL_E2E_LEARNR2', ask = FALSE)" >"$out/learnr2-install.log" 2>&1 \
    || { tail -30 "$out/learnr2-install.log"; exit 1; }
fi

step "learnr2 in this image"
learnr2_version="$(Rscript -e "cat(as.character(utils::packageVersion('learnr2')))")"
has_load="$(Rscript -e "cat(if (exists('load_tutorial', asNamespace('learnr2'))) 'yes' else 'no')")"
echo "learnr2 $learnr2_version, load_tutorial(): $has_load"
legacy=()
if [ "$has_load" != yes ]; then
  # The restore half of this test (load_tutorial(), the page's Load Answers
  # button, fingerprints, package/tutorial fields in the file) needs
  # learnr2 >= 0.1.3.9013. An image that bakes an older learnr2 still gets
  # the first half -- a student answers everything and downloads -- and the
  # run PASSES with a warning annotation, so the image is not held hostage
  # to a test. The restore steps switch on by themselves once an image
  # release bakes a newer learnr2 (the course-package refresh pulls HEAD).
  echo "::warning title=tutorial-e2e: restore steps skipped::image bakes learnr2 $learnr2_version, which has no load_tutorial(); only the answer-and-download half ran. The next image release (learnr2 >= 0.1.3.9013) enables the restore steps."
  legacy=(--legacy)
fi

# open = TRUE is what makes run_tutorial() serve and block; its default is
# interactive(), which is FALSE under Rscript, so without it the process
# renders and exits. The browser option swallows the open-a-tab step.
step "Serve $pkg/$name on :$port with learnr2::run_tutorial() (browser suppressed)"
Rscript -e "options(browser = function(url) message('browser suppressed; would open ', url)); learnr2::run_tutorial('$name', package = '$pkg', output_dir = '$root', open = TRUE)" \
  >"$out/server.log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT
# A stale cache means a Quarto render first, which can take a few minutes.
for _ in $(seq 1 120); do
  if curl -fsS -o /dev/null "$url"; then break; fi
  if ! kill -0 "$server" 2>/dev/null; then
    echo "the learnr2 server exited before serving:"; cat "$out/server.log"; exit 1
  fi
  sleep 5
done
curl -fsS -o /dev/null "$url" || { echo "no answer from $url after 10 minutes:"; cat "$out/server.log"; exit 1; }
grep -E 'as rendered|Rendering|Opening' "$out/server.log" || true

step "1. A student answers every question and downloads (A.json)"
"$py" "$here/e2e.py" --package "$pkg" --tutorial "$name" --shots "$out" "${legacy[@]}" \
  full --url "$url" --out "$out/A.json"

if [ "$has_load" != yes ]; then
  printf '\nTUTORIAL E2E OK (answer + download only): %s/%s on learnr2 %s; restore steps skipped, see the warning above.\n' "$pkg" "$name" "$learnr2_version"
  exit 0
fi

step "2. Blank the last $leave answers to make an unfinished file (P.json)"
"$py" "$here/e2e.py" partial --answers "$out/A.json" --out "$out/P.json" --leave "$leave"

step "3. learnr2::load_tutorial(P.json) writes the restore page"
restore="$(Rscript -e "cat(learnr2::load_tutorial('$out/P.json', output_dir = '$root', open = FALSE))" 2>"$out/load_tutorial.log")"
cat "$out/load_tutorial.log"
grep -q '^Restored [0-9]* answer' "$out/load_tutorial.log" || { echo "load_tutorial() did not report restoring anything"; exit 1; }
if grep -qi 'warning' "$out/load_tutorial.log"; then echo "load_tutorial() warned; see above"; exit 1; fi
case "$restore" in
  "$root"/*) ;;
  *) echo "restore page '$restore' is outside the served root '$root'"; exit 1 ;;
esac
restore_url="http://127.0.0.1:$port/${restore#"$root"/}"
curl -fsS -o /dev/null "$restore_url" || { echo "restore page not served at $restore_url"; exit 1; }

step "4. Fresh browser opens the restore page, finishes the last $leave, downloads (B.json)"
"$py" "$here/e2e.py" --package "$pkg" --tutorial "$name" --shots "$out" \
  finish --restore-url "$restore_url" --tutorial-url "$url" \
  --answers "$out/A.json" --partial "$out/P.json" --out "$out/B.json"

step "5. Fresh browser uses the page's Load Answers button with A.json, downloads (C.json)"
"$py" "$here/e2e.py" --package "$pkg" --tutorial "$name" --shots "$out" \
  load --url "$url" --answers "$out/A.json" --out "$out/C.json"

step "6. learnr2::check_submission() on A, B and C"
Rscript -e "
a <- learnr2::check_submission('$out/A.json')
stopifnot(identical(a\$fingerprint, 'valid'), is.null(a\$loaded_from), identical(a\$name, 'Test Student'))
for (f in c('$out/B.json', '$out/C.json')) {
  r <- learnr2::check_submission(f)
  stopifnot(identical(r\$fingerprint, 'valid'), !is.null(r\$loaded_from), identical(r\$name, 'Test Student'))
}
cat('check_submission: A fresh and valid; B and C valid and loaded from A\n')
"

printf '\nTUTORIAL E2E OK: %s/%s (files in %s)\n' "$pkg" "$name" "$out"
