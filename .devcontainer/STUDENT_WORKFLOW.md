# Student workflow

This Codespace is your **workshop** — it already has R, Python (with the usual
data-science libraries), Quarto, the AI assistants, and all the right settings. But this `codespace-starter` repo isn't
*yours*, so you won't save your work here. Instead, you'll make your **own
repo** and work in it. The tools travel with the Codespace, so your repo needs
no setup of its own.

## 1. Create or connect to your repo (one command)

In the terminal:

```bash
.devcontainer/connect-repo.sh my-class-work
```

(Use any name in place of `my-class-work`.) The first time, a browser prompt
asks you to **authorize** — click through it, then come back. The script then:

- signs you in as yourself,
- creates a new public repo under your GitHub account — or, if a repo by that
  name already exists on your account, **connects to it** (clones it) instead, and
- downloads it into the Codespace at `/workspaces/<name>`.

Then **open your repo as the workspace**: **File → Open Folder →
`/workspaces/<name>`**. (The editor may switch on its own; if it doesn't, use
that menu — it's the reliable way.) Once it's open, the Explorer, the Source
Control panel, and your terminal all act on *your* repo.

You only authorize once per Codespace.

> **Why the authorize step?** A Codespace starts with a limited login that can
> only touch `codespace-starter`. Authorizing signs you in as *you*, so you can
> create and save to your own repos.

## 2. Do your work and save it

Write code, knit Quarto docs — all as normal. To save to GitHub:

1. Click the **Source Control** icon in the left sidebar.
2. Type a short message describing what you did.
3. Click **✓ Commit**, then **Sync Changes** (or **Publish Branch** the first time).

> **Saving = committing + pushing.** That's the only thing that makes your work
> permanent. A Codespace is temporary; unpushed work can be lost.

## 3. Publish a graphic to the web

Once you're working in your own repo, you have two easy options.

**A. A whole page (rendered Quarto doc):**

```bash
quarto publish gh-pages
```

This renders your `.qmd` and publishes it as a GitHub Pages site under your
repo. The first time, you may need to turn on Pages in your repo's
**Settings → Pages**.

**B. Just the image, fastest possible:** your repo is already public, so just
commit the image, push, and it's live at:

```
https://raw.githubusercontent.com/<your-username>/<your-repo>/main/plot.png
```

## Handy to know

- **Work in *your* repo's folder, not `codespace-starter`.** If you're editing
  files under `/workspaces/codespace-starter`, you're in the workshop, not your
  project — re-run `connect-repo` or use **File → Open Folder**.
- **Coming back later:** reopen the *same* Codespace and everything is still
  there. If you start a **fresh** Codespace, just run `connect-repo my-class-work`
  again — it notices your repo already exists and clones it instead of erroring.
- **Connecting to someone else's repo** (an org or another user — e.g. an
  assignment repo): pass `owner/name`, like
  `.devcontainer/connect-repo.sh PPBDS/some-assignment`. It clones into
  `/workspaces/some-assignment`. (You need read access to a private one.)
- **If `git push` ever says "Author identity unknown":**
  ```bash
  git config --global user.name "Your Name"
  git config --global user.email "you@example.com"
  ```

## What's in your workshop (and when to use what)

Everything here is already installed. A quick map of what to reach for — and
note that **all of it publishes to a plain static website** (GitHub Pages): the
interactive pieces run in the browser, so you never need a server.

**Languages & documents**
- **R + the tidyverse + Quarto** — the core. Do your analysis and write it up in
  a `.qmd`; render to HTML/PDF or publish a website with `quarto publish gh-pages`.
- **Python** (pandas, numpy, scikit-learn, statsmodels, matplotlib/seaborn) — if
  you'd rather use Python, in a `.qmd` Python chunk or a Jupyter notebook. Need
  another package? `pip install <name>` works.

**Make it interactive (still a static site)**
- **Interactive charts / maps / tables** — `plotly`, `leaflet`, `DT` (R) or
  `plotly`, `altair`, `folium`, `itables` (Python). Drop them in a `.qmd` for
  zoomable charts, pannable maps, and sortable tables.
- **Quarto dashboards & websites** — `format: dashboard` for a dashboard layout;
  Quarto websites for multi-page sites.
- **Observable** — `{ojs}` cells put reactive JavaScript (Observable Plot, D3)
  in a `.qmd`; the `observable` command builds standalone data-app projects.
- **Shinylive** — a full Shiny app (R or Python) that runs entirely in the
  browser via WebAssembly, so even reactive apps publish to GitHub Pages.

**Help while you work**
- **AI assistants in the terminal** — `claude`, `codex`, `agy`, `aider`. Sign in
  (or set an API key) and ask for coding help. (They're terminal tools by
  design — they work on every device, even a tablet.)
- **`connect-repo.sh`** — create or connect to your work repo (run `--help` to
  see exactly what it does).
