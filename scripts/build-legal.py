#!/usr/bin/env python3
"""Renders docs/legal/*.md to static HTML for the ate-legal GitHub Pages site
(https://melusi-k.github.io/ate-legal/). Usage: scripts/build-legal.py [outdir]
Does NOT write index.html, 404.html or r/ (hand-made in ate-legal)."""
import markdown, pathlib, sys, html, re, shutil
ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "docs/legal"
out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/legal")
out.mkdir(parents=True, exist_ok=True)
SITE = "https://melusi-k.github.io/ate-legal/"
BASE = "/ate-legal/"
# slug: (title, description, also emit slug/index.html)
PAGES = {
 "privacy": ("Privacy Policy", "What ate stores, where it's stored (Supabase EU), and your choices. No ads, no tracking.", True),
 "terms": ("Terms of Use", "The terms for using the ate recipe app and its share links.", True),
 "health": ("Health data privacy", "How ate reads Apple Health and Journaling Suggestions on your iPhone only.", False),
 "delete-account": ("Delete your account", "How to delete your ate account and data, in the app or by email.", True),
 "cookies": ("Cookies and tracking", "ate and this site use no cookies, analytics or trackers.", False),
 "subprocessors": ("Subprocessors and data map", "Who processes ate data, and where each kind of data lives.", False),
 "rights": ("Your data rights", "How to use your POPIA and GDPR rights with ate, and how to complain.", False),
 "ai": ("AI disclosure", "ate's on-device Apple Intelligence and Image Playground, and why you should check every recipe.", False),
 "support": ("Support and FAQ", "Installing the ate beta, widgets, Health, sync and Siri.", True),
 "beta": ("Beta tester terms", "Extra terms for testing ate beta builds.", False),
 "acceptable-use": ("Shared recipe rules and takedowns", "Rules for shared recipes, and how to report a link.", False),
 "security": ("Security", "How ate protects data, and how to report a vulnerability.", False),
 "releases": ("Release notes", "What changed in each ate beta build.", False),
 "policy-history": ("Policy history", "Every version of ate's Privacy Policy and Terms of Use.", False),
}
ARCHIVE = sorted((SRC / "archive").glob("*.md"))
NAV = [("privacy", "Privacy"), ("terms", "Terms"), ("health", "Health"), ("rights", "Your rights"), ("delete-account", "Delete account"), ("support", "Support")]
FOOT = [("ai", "AI"), ("cookies", "Cookies"), ("subprocessors", "Subprocessors"), ("acceptable-use", "Sharing rules"),
        ("beta", "Beta terms"), ("security", "Security"), ("releases", "Release notes"), ("policy-history", "Policy history")]
FONTS = ROOT / "Ate/Resources/Fonts"
CSS = """@font-face{font-family:"DM Sans";src:url(/ate-legal/assets/fonts/DMSans.ttf) format("truetype");font-weight:100 1000;font-display:swap}
@font-face{font-family:"Fraunces";src:url(/ate-legal/assets/fonts/Fraunces.ttf) format("truetype");font-weight:100 900;font-display:swap}
body{font:400 1.0625rem/1.6 "DM Sans",system-ui,-apple-system,sans-serif;background:#FCF7ED;color:#311F16;margin:0}
.skip{position:absolute;left:-999px;top:8px;background:#B4532A;color:#fff;padding:8px 14px;border-radius:8px;z-index:9}.skip:focus{left:8px}
header,main,footer{max-width:760px;margin:0 auto;padding:0 20px}header{padding-top:20px}main{padding-bottom:48px}
h1,h2{font-family:"Fraunces",Georgia,serif;line-height:1.2}h1{font-size:2.1em}h2{margin-top:2em}
a{color:#A8461F}a:focus-visible{outline:3px solid #D2643A;outline-offset:2px}code{background:#F3EAD7;padding:0 4px;border-radius:4px}
nav ul{list-style:none;padding:0;margin:0;display:flex;flex-wrap:wrap;gap:4px 18px;font-size:.95rem}nav a{display:inline-block;padding:10px 0}
nav a[aria-current=page]{font-weight:700;text-decoration-thickness:3px}.brand{font-family:"Fraunces",serif;font-weight:700;font-size:1.4rem;color:#A8461F;text-decoration:none}
table{border-collapse:collapse;width:100%;display:block;overflow-x:auto}th,td{border:1px solid #E5D8C3;padding:8px;text-align:left;vertical-align:top}
blockquote{margin:1.5em 0;padding:10px 16px;background:#FFF1D6;border-left:4px solid #C9821E;border-radius:6px}
footer{border-top:1px solid #E5D8C3;padding-top:16px;padding-bottom:40px;font-size:.9rem}
@media (prefers-color-scheme:dark){body{background:#1A120C;color:#F3EEE4}a,.brand{color:#F08A5D}code{background:#352820}th,td,footer{border-color:#4A3A2E}blockquote{background:#3A2A15}}"""

def nav(items, cur, label):
    lis = "".join(f'<li><a href="{s}.html"{" aria-current=\"page\"" if s == cur else ""}>{t}</a></li>' for s, t in items)
    return f'<nav aria-label="{label}"><ul>{lis}</ul></nav>'

def page(slug, title, desc, body, canon_slug=None, noindex=False, path=None):
    canon = SITE + (canon_slug or slug) + ".html"
    t = html.escape(f"{title} · ate"); d = html.escape(desc)
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<base href="{BASE}"><title>{t}</title><meta name="description" content="{d}"><link rel="canonical" href="{canon}">
{'<meta name="robots" content="noindex">' if noindex else ''}<meta name="color-scheme" content="light dark"><meta name="theme-color" content="#FCF7ED">
<meta property="og:type" content="website"><meta property="og:site_name" content="ate"><meta property="og:title" content="{t}"><meta property="og:description" content="{d}">
<meta property="og:url" content="{canon}"><meta property="og:image" content="{SITE}assets/og-cover.png"><meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/png" sizes="32x32" href="assets/favicon-32.png"><link rel="apple-touch-icon" href="assets/apple-touch-icon.png">
<link rel="preload" href="assets/fonts/DMSans.ttf" as="font" type="font/ttf" crossorigin><style>{CSS}</style></head>
<body><a class="skip" href="{path or (canon_slug or slug) + '.html'}#main">Skip to content</a>
<header><a class="brand" href="./">ate</a>{nav(NAV, slug, "Legal")}</header>
<main id="main" tabindex="-1">{body}</main>
<footer>{nav(FOOT, slug, "More")}<p>Melusi Khumalo, South Africa · <a href="mailto:melusi.l.k@gmail.com">melusi.l.k@gmail.com</a></p></footer></body></html>"""

def md(text):
    return markdown.markdown(text, extensions=["tables", "toc", "sane_lists"])

def changelog():
    cl = (ROOT / "CHANGELOG.md").read_text()
    cl = re.sub(r"\A# Changelog.*?(?=^## )", "", cl, flags=re.S | re.M)
    return re.sub(r"^(#+) ", lambda m: "#" * (len(m[1]) + 0) + " ", cl, flags=re.M)

written = []
def write(rel, s):
    p = out / rel; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(s); written.append(rel)

for slug, (title, desc, dup) in PAGES.items():
    text = (SRC / f"{slug}.md").read_text().replace("{{CHANGELOG}}", changelog() if slug == "releases" else "")
    body = md(text)
    write(f"{slug}.html", page(slug, title, desc, body))
    if dup:  # pretty /slug/ URL; canonical points at slug.html
        write(f"{slug}/index.html", page(slug, title, desc, body, canon_slug=slug, path=f"{slug}/"))
for a in ARCHIVE:
    kind, date = a.stem.rsplit("-", 3)[0], "-".join(a.stem.split("-")[-3:])
    banner = f'<p><strong>This is an old version ({date}).</strong> See the <a href="{kind}.html">current version</a>.</p>'
    write(f"archive/{a.stem}.html", page("policy-history", f"{kind.title()} ({date}, archived)", f"Archived {kind} from {date}.",
                                         banner + md(a.read_text()), canon_slug=f"archive/{a.stem}", noindex=True, path=f"archive/{a.stem}.html"))
(out / "assets/fonts").mkdir(parents=True, exist_ok=True)
for f in ["DMSans.ttf", "Fraunces.ttf", "OFL-DMSans.txt", "OFL-Fraunces.txt"]:
    shutil.copy(FONTS / f, out / "assets/fonts" / f); written.append(f"assets/fonts/{f}")
write("README.md", """# ate legal and website

GitHub Pages site for the ate iOS app: https://melusi-k.github.io/ate-legal/

- Hand-made here: `index.html` (landing), `404.html`, `r/` (shared recipes).
- Generated: the legal and support pages, `archive/` and `assets/fonts/`. Their source is `docs/legal/*.md` in
  [melusi-k/ate-ios](https://github.com/melusi-k/ate-ios), rendered with `scripts/build-legal.py`. Edit the Markdown there, not the HTML here.
""")
print("\n".join(sorted(written)))
