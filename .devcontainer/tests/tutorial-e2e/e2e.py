#!/usr/bin/env python3
"""Drive a learnr2 tutorial in headless Chromium the way a student would.

Run by run.sh inside the student image; see that script for the whole
story. Four subcommands, each one browser session:

  full     Open the tutorial, submit the student-info form, answer every
           question section by section (clicking Continue as a student
           must), click "Download My Answers", save the JSON.
  partial  No browser. Copy an answers file with the last N answers set to
           null, the shape of a file from an unfinished attempt.
  finish   A FRESH browser (empty localStorage) opens the restore page
           learnr2::load_tutorial() wrote for the partial file, which
           forwards to the tutorial with the restored answers submitted.
           Check exactly those answers are back, answer the rest, download.
  load     A FRESH browser opens the bare tutorial and uses the page's own
           "Load Answers" button (the no-R path) with the full file, checks
           everything is restored, downloads again.

Selectors and storage keys mirror learnr2's inst/extdata/quiz/quiz.js:
widgets are `.learnr2-question[data-learnr2-question]` (payload = base64
JSON with `id` and `type`), state lives in localStorage under
"learnr2-<page URL without hash>#<id>", a submitted reflection saves
{value|image, submitted: true}, and a Continue button
(`.learnr2-continue`) is disabled while any widget above it is pending.
"""

import argparse
import json
import re
import sys

from playwright.sync_api import TimeoutError as PWTimeout
from playwright.sync_api import sync_playwright

Q = ".learnr2-question-rendered"
INFO = ".learnr2-info-rendered"
NAME = "Test Student"
EMAIL = "student@example.com"
STUDENT_ID = "e2e-001"
TEXT = "This is a test answer written by the tutorial-e2e workflow."
INTEGER = "95"

# JS helpers evaluated in the page. decode() mirrors quiz.js's
# decodeBase64Json (plain base64 of UTF-8 JSON); the fallback handles a
# URL-safe alphabet in case that ever changes.
JS_PRELUDE = """
const pageUrl = window.location.href.split('#')[0];
const decode = (s) => {
  const bytes = (b64) => Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  let raw;
  try { raw = bytes(s); }
  catch (e) { raw = bytes(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - s.length % 4) % 4)); }
  return JSON.parse(new TextDecoder('utf-8').decode(raw));
};
const stateOf = (id) => {
  const raw = localStorage.getItem('learnr2-' + pageUrl + '#' + id);
  return raw ? JSON.parse(raw) : null;
};
const submitted = (st) => !!(st && st.submitted && !st.editing);
"""

JS_QUESTIONS = JS_PRELUDE + """
return Array.from(document.querySelectorAll('.learnr2-question[data-learnr2-question]')).map((n, i) => {
  const d = decode(n.getAttribute('data-learnr2-question'));
  return { i, id: d.id, type: d.type || 'single', visible: n.getClientRects().length > 0,
           state: stateOf(d.id) };
});
"""

JS_INFO_LOCKED = """() => {
  const n = document.querySelector('.learnr2-info-rendered input[id$="-name"]');
  return !!(n && n.disabled);
}"""

JS_PASTE_IMAGE = """async (el) => {
  const canvas = document.createElement('canvas');
  canvas.width = 320; canvas.height = 200;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, 320, 200);
  ctx.fillStyle = '#1f6feb'; ctx.fillRect(20, 20, 280, 60);
  ctx.fillStyle = '#000000'; ctx.font = '20px sans-serif';
  ctx.fillText('learnr2 (e2e screenshot)', 30, 140);
  const blob = await new Promise(r => canvas.toBlob(r, 'image/png'));
  const file = new File([blob], 'screenshot.png', { type: 'image/png' });
  const dt = new DataTransfer();
  dt.items.add(file);
  el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
  return true;
}"""


def log(msg):
    print(f"[e2e] {msg}", flush=True)


def fail(msg):
    raise AssertionError(msg)


def questions(page):
    """Every question on the page, in document order, with its saved state."""
    return page.evaluate("() => {" + JS_QUESTIONS + "}")


def wait_ready(page):
    page.wait_for_selector(Q, state="attached")
    page.wait_for_selector(INFO, state="attached")
    # Widgets render synchronously once quiz.js runs; the progressive reveal
    # and TOC locks follow in the same tick. A short settle keeps the first
    # visibility read honest.
    page.wait_for_timeout(300)


def submit_info(page):
    form = page.locator(INFO).first
    # Inputs are id'd "<form id>-<field key>"; the form id has varied across
    # learnr2 versions, the suffix has not.
    form.locator('input[id$="-name"]').fill(NAME)
    form.locator('input[id$="-email"]').fill(EMAIL)
    sid = form.locator('input[id$="-id"]')
    if sid.count():
        sid.fill(STUDENT_ID)
    form.locator(".learnr2-controls .learnr2-submit").click()
    page.wait_for_function(JS_INFO_LOCKED)
    log("student info submitted")


def wait_submitted(page, qid):
    page.wait_for_function(
        "(id) => {" + JS_PRELUDE + " return submitted(stateOf(id)); }", arg=qid
    )


def answer_question(page, index, qid):
    node = page.locator(Q).nth(index)
    image_only = node.locator(".learnr2-image-paste").count() > 0 and \
        node.locator(".learnr2-answers.d-none").count() > 0
    if image_only:
        node.locator(".learnr2-image-paste").evaluate(JS_PASTE_IMAGE)
        node.locator(".learnr2-image-paste-preview").wait_for(state="visible")
        kind = "image"
    else:
        box = node.locator("textarea.learnr2-text-input, input.learnr2-text-input").first
        is_input = box.evaluate("e => e.tagName === 'INPUT'")
        box.fill(INTEGER if is_input else TEXT)
        kind = "integer" if is_input else "text"
    node.locator(".learnr2-controls .learnr2-submit").click()
    wait_submitted(page, qid)
    log(f"answered {qid} ({kind})")


def walk(page):
    """Answer every visible pending question, click Continue, repeat until
    no Continue button is left (the last section is open). Returns the ids
    answered, in order."""
    answered = []
    for _ in range(2000):
        for q in questions(page):
            if q["visible"] and not (q["state"] and q["state"].get("submitted") and not q["state"].get("editing")):
                answer_question(page, q["i"], q["id"])
                answered.append(q["id"])
        cont = page.locator(".learnr2-continue")
        if cont.count() == 0:
            return answered
        # quiz.js re-evaluates the gate on a zero-delay timeout after any
        # Submit click, so give it a moment before concluding it is stuck.
        try:
            page.wait_for_function(
                "() => { const b = document.querySelector('.learnr2-continue'); return !b || !b.disabled; }",
                timeout=5000,
            )
        except PWTimeout:
            note = page.locator(".learnr2-continue-note").first.inner_text()
            fail(f"Continue is locked but nothing visible is pending: {note!r}")
        if cont.count() == 0:
            return answered
        cont.first.click()
        page.wait_for_timeout(50)
    fail("walk() did not reach the last section")


def download(page, path):
    error = page.locator(".learnr2-download-error:not(.d-none)")
    with page.expect_download() as dl:
        page.locator(".learnr2-download-answers-btn").first.click()
        confirm = page.locator(".learnr2-confirm-dialog-confirm")
        try:
            confirm.wait_for(state="visible", timeout=1500)
            log("download asked about unanswered questions; confirming")
            confirm.click()
        except PWTimeout:
            if error.count():
                fail(f"download blocked: {error.first.inner_text()!r}")
    dl.value.save_as(path)
    log(f"downloaded {dl.value.suggested_filename} -> {path}")
    return read(path)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def write(path, data):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)


def check_file(d, label, expect_package, expect_tutorial, legacy=False):
    if legacy:
        # learnr2 < 0.1.3.9013 recorded neither the tutorial's identity nor
        # a fingerprint; the answers and the student info are all there is.
        if not d.get("answers"):
            fail(f"{label}: no answers")
        if d.get("info", {}).get("name") != NAME or d.get("info", {}).get("email") != EMAIL:
            fail(f"{label}: student info not recorded: {d.get('info')}")
        log(f"{label}: legacy file, {len(d['answers'])} answers, "
            f"{sum(a['answer'] is None for a in d['answers'])} unanswered")
        return
    if d.get("package") != expect_package or d.get("tutorial") != expect_tutorial:
        fail(f"{label}: package/tutorial = {d.get('package')}/{d.get('tutorial')}, "
             f"expected {expect_package}/{expect_tutorial}")
    if not isinstance(d.get("version"), str) or not d["version"]:
        fail(f"{label}: no package version recorded")
    if d.get("info", {}).get("name") != NAME or d.get("info", {}).get("email") != EMAIL:
        fail(f"{label}: student info not recorded: {d.get('info')}")
    if not re.fullmatch(r"[0-9a-f]{64}", d.get("fingerprint") or ""):
        fail(f"{label}: fingerprint missing or malformed: {d.get('fingerprint')!r}")
    if not d.get("answers"):
        fail(f"{label}: no answers")
    log(f"{label}: {expect_package} {d['version']} / {expect_tutorial}, "
        f"{len(d['answers'])} answers, {sum(a['answer'] is None for a in d['answers'])} unanswered")


def answers_by_id(d):
    return {a["id"]: a["answer"] for a in d["answers"]}


def with_browser(args, fn):
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        context = browser.new_context(accept_downloads=True, viewport={"width": 1280, "height": 900})
        context.set_default_timeout(30000)
        page = context.new_page()
        page.on("pageerror", lambda e: log(f"PAGE ERROR: {e}"))
        try:
            fn(page)
        except Exception:
            if args.shots:
                shot = f"{args.shots}/{args.command}-failure.png"
                try:
                    page.screenshot(path=shot, full_page=True)
                    log(f"screenshot of the failure: {shot}")
                except Exception as e:  # the page may be gone
                    log(f"could not take a screenshot: {e}")
            raise
        finally:
            browser.close()


def cmd_full(args):
    def run(page):
        page.goto(args.url)
        wait_ready(page)
        total = len(questions(page))
        log(f"{total} questions on the page")
        submit_info(page)
        answered = walk(page)
        if len(answered) != total:
            fail(f"answered {len(answered)} of {total} questions")
        d = download(page, args.out)
        check_file(d, "A", args.package, args.tutorial, legacy=args.legacy)
        missing = [a["id"] for a in d["answers"] if a["answer"] is None]
        if missing:
            fail(f"A has unanswered questions after a full run: {missing}")
        images = [a["id"] for a in d["answers"] if isinstance(a["answer"], str) and a["answer"].startswith("data:image/")]
        log(f"screenshot answers recorded for: {images}")
        if not args.legacy and d.get("loadedFrom") is not None:
            fail("A claims to be loaded from an earlier file, but this was a fresh run")
    with_browser(args, run)


def cmd_partial(args):
    d = read(args.answers)
    if args.leave < 1 or args.leave >= len(d["answers"]):
        fail(f"--leave must be between 1 and {len(d['answers']) - 1}")
    blanked = []
    for a in d["answers"][-args.leave:]:
        a["answer"] = None
        blanked.append(a["id"])
    write(args.out, d)
    log(f"blanked the last {args.leave} answers: {blanked}")


def cmd_finish(args):
    full = read(args.answers)
    partial = read(args.partial)
    expected_restored = {a["id"] for a in partial["answers"] if a["answer"] is not None}
    expected_left = [a["id"] for a in partial["answers"] if a["answer"] is None]

    def run(page):
        page.goto(args.restore_url)
        # The restore page stores the answers, then forwards to the tutorial.
        page.wait_for_url(lambda u: "learnr2-restore" not in u)
        if page.url.split("#")[0] != args.tutorial_url:
            fail(f"restore page forwarded to {page.url}, expected {args.tutorial_url}")
        wait_ready(page)
        restored = {q["id"] for q in questions(page) if q["state"] and q["state"].get("submitted")}
        if restored != expected_restored:
            fail(f"restored {sorted(restored)}\nexpected {sorted(expected_restored)}")
        log(f"{len(restored)} answers restored by load_tutorial()")
        if not page.evaluate(JS_INFO_LOCKED):
            fail("student info form was not restored as submitted")
        if page.locator(".learnr2-continue").count() == 0:
            fail("the page opened fully unlocked, but the last answers are missing")
        answered = walk(page)
        if answered != expected_left:
            fail(f"finishing answered {answered}, expected exactly the blanked {expected_left}")
        d = download(page, args.out)
        check_file(d, "B", args.package, args.tutorial)
        before, after = answers_by_id(full), answers_by_id(d)
        for qid in expected_restored:
            if after[qid] != before[qid]:
                fail(f"B changed restored answer {qid}")
        missing = [k for k, v in after.items() if v is None]
        if missing:
            fail(f"B still has unanswered questions: {missing}")
        lf = d.get("loadedFrom") or {}
        if lf.get("fingerprint") != full["fingerprint"] or lf.get("name") != NAME:
            fail(f"B's loadedFrom does not point at A: {lf}")
        if d["fingerprint"] == full["fingerprint"]:
            fail("B's fingerprint equals A's, but its answers differ")
    with_browser(args, run)


def cmd_load(args):
    full = read(args.answers)

    def run(page):
        page.goto(args.url)
        wait_ready(page)
        if any(q["state"] for q in questions(page)):
            fail("a fresh browser context already had saved answers")
        with page.expect_file_chooser() as fc:
            page.locator(".learnr2-load-answers").first.click()
        fc.value.set_files(args.answers)
        confirm = page.locator(".learnr2-confirm-dialog-confirm")
        confirm.wait_for(state="visible")
        message = page.locator(".learnr2-confirm-dialog-message").inner_text()
        log(f"Load Answers asks: {message!r}")
        if "dropped" in message.lower() or "not this one" in message.lower():
            fail("Load Answers would drop answers or thinks the file is for another tutorial")
        confirm.click()
        page.wait_for_load_state("load")
        wait_ready(page)
        qs = questions(page)
        not_restored = [q["id"] for q in qs if not (q["state"] and q["state"].get("submitted"))]
        if not_restored:
            fail(f"Load Answers left these unanswered: {not_restored}")
        log(f"all {len(qs)} answers restored by the Load Answers button")
        if not page.evaluate(JS_INFO_LOCKED):
            fail("student info form was not restored as submitted")
        answered = walk(page)
        if answered:
            fail(f"nothing should need answering after a full load, but answered {answered}")
        d = download(page, args.out)
        check_file(d, "C", args.package, args.tutorial)
        if answers_by_id(d) != answers_by_id(full):
            fail("C's answers differ from A's")
        if d["info"] != full["info"]:
            fail(f"C's info differs from A's: {d['info']} vs {full['info']}")
        lf = d.get("loadedFrom") or {}
        if lf.get("fingerprint") != full["fingerprint"]:
            fail(f"C's loadedFrom does not point at A: {lf}")
    with_browser(args, run)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--package", default="vscode.tutorials")
    p.add_argument("--tutorial", default="orientation")
    p.add_argument("--shots", help="directory for a screenshot when a browser step fails")
    p.add_argument("--legacy", action="store_true",
                   help="the page's learnr2 predates 0.1.3.9013: no tutorial identity or fingerprint in the file")
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("full")
    s.add_argument("--url", required=True)
    s.add_argument("--out", required=True)
    s.set_defaults(fn=cmd_full)

    s = sub.add_parser("partial")
    s.add_argument("--answers", required=True)
    s.add_argument("--out", required=True)
    s.add_argument("--leave", type=int, default=3)
    s.set_defaults(fn=cmd_partial)

    s = sub.add_parser("finish")
    s.add_argument("--restore-url", required=True)
    s.add_argument("--tutorial-url", required=True)
    s.add_argument("--answers", required=True, help="the full file (A)")
    s.add_argument("--partial", required=True, help="the blanked copy load_tutorial() was given (P)")
    s.add_argument("--out", required=True)
    s.set_defaults(fn=cmd_finish)

    s = sub.add_parser("load")
    s.add_argument("--url", required=True)
    s.add_argument("--answers", required=True)
    s.add_argument("--out", required=True)
    s.set_defaults(fn=cmd_load)

    args = p.parse_args(argv)
    try:
        args.fn(args)
    except AssertionError as e:
        log(f"FAILED ({args.command}): {e}")
        return 1
    log(f"{args.command}: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
