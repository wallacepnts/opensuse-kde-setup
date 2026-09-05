#!/usr/bin/env python3
# Checks the documentation the way a reader would break it: dead links, dead
# anchors, commands that do not parse, and the two language versions drifting
# apart. Run it locally before committing; CI runs the same thing.
import glob
import os
import re
import subprocess
import sys

PAIRS = [
    ("README.md", "README.pt-BR.md"),
    ("docs/installation-guide.md", "docs/installation-guide.pt-BR.md"),
    ("docs/troubleshooting.md", "docs/troubleshooting.pt-BR.md"),
    ("docs/ssh-and-git.md", "docs/ssh-and-git.pt-BR.md"),
    ("docs/video-davinci.md", "docs/video-davinci.pt-BR.md"),
]
SWITCH = re.compile(
    r"^(\*\*English\*\* · \[Português\]\(|\[English\]\(.*\) · \*\*Português\*\*)", re.M
)
FENCE = re.compile(r"^```.*?^```", re.S | re.M)
# <N>, <id>, <game folder>… A leading letter keeps this away from the shell's
# own <<heredoc, <<<string and <(process) syntax.
PLACEHOLDER = re.compile(r"<[A-Za-z][^<>]*>")
MAX_LINE = 100

fails = []


def fail(where, msg):
    fails.append(f"{where}: {msg}")


def anchor(title):
    t = title.strip().lower().replace(" ", "-")
    return "".join(c for c in t if c.isalnum() or c in "-_")


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


docs = sorted(set(glob.glob("*.md") + glob.glob("docs/*.md")))
if not docs:
    sys.exit("no markdown found — run this from the repository root")

# Anchors of every document, so a cross-file link can be checked whole.
anchors = {
    p: {anchor(m) for m in re.findall(r"^#{2,3} (.+)$", read(p), re.M)} for p in docs
}

for path in docs:
    text = read(path)
    base = os.path.dirname(path)
    # Markdown shown inside a fence is an example, not a live reference.
    prose = FENCE.sub("", text)

    for link in re.findall(r"\]\(([^)]+)\)", prose):
        if link.startswith("http"):
            continue
        target, _, frag = link.partition("#")
        if not target:
            if frag not in anchors[path]:
                fail(path, f"anchor not found: {link}")
            continue
        resolved = os.path.normpath(os.path.join(base, target))
        if not os.path.exists(resolved):
            fail(path, f"link target missing: {target}")
        elif frag and frag not in anchors.get(resolved, set()):
            fail(path, f"anchor not found in {target}: #{frag}")

    # ![alt](path) is already covered above; <img src=…> is HTML and is not.
    for src in re.findall(r'<img[^>]+src="([^"]+)"', prose):
        if src.startswith("http"):
            continue
        if not os.path.exists(os.path.normpath(os.path.join(base, src))):
            fail(path, f"image missing: {src}")

    for ref in sorted(set(re.findall(r"scripts/[\w.-]+", prose))):
        if not os.path.exists(ref):
            fail(path, f"script referenced but absent: {ref}")

    if not SWITCH.search(text):
        fail(path, "no language switch line under the title")

    for i, block in enumerate(re.findall(r"```bash\n(.*?)```", text, re.S)):
        probe = PLACEHOLDER.sub("PLACEHOLDER", block)
        run = subprocess.run(
            ["bash", "-n"], input=probe, capture_output=True, text=True
        )
        # An unterminated heredoc only warns: bash -n still exits 0.
        if run.returncode or run.stderr.strip():
            fail(path, f"bash block {i}: {run.stderr.strip().splitlines()[0][:120]}")

    inside = False
    for n, line in enumerate(text.split("\n"), 1):
        if line.startswith("```"):
            inside = not inside
            continue
        if inside or line.lstrip().startswith("|") or "http" in line:
            continue
        if len(line.rstrip()) > MAX_LINE:
            fail(path, f"line {n} is longer than {MAX_LINE} characters")

for en, pt in PAIRS:
    if not (os.path.exists(en) and os.path.exists(pt)):
        fail(en, f"missing one side of the pair ({pt})")
        continue
    a, b = read(en), read(pt)
    for label, count in (
        ("sections", lambda s: len(re.findall(r"^## ", s, re.M))),
        ("code fences", lambda s: s.count("```")),
    ):
        if count(a) != count(b):
            fail(en, f"{label} differ from {pt}: {count(a)} vs {count(b)}")

if fails:
    print("\n".join(f"FAIL  {f}" for f in fails))
    sys.exit(f"\n{len(fails)} problem(s) found")
print(f"ok — {len(docs)} documents, {len(PAIRS)} language pairs")
