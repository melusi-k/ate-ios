#!/usr/bin/env python3
"""Renders docs/legal/*.md to static HTML (published at https://melusi-k.github.io/ate-legal/)."""
import markdown, pathlib, sys, html
out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/legal")
out.mkdir(parents=True, exist_ok=True)
CSS = """body{font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#FCF7ED;color:#311F16;margin:0}
main{max-width:720px;margin:0 auto;padding:32px 20px 64px}h1{font-family:Georgia,serif;font-size:2em;line-height:1.2}
h2{font-family:Georgia,serif;margin-top:2em}a{color:#C95028}code{background:#F3EAD7;padding:0 4px;border-radius:4px}
nav{font-size:14px;margin-bottom:24px}nav a{margin-right:16px}.brand{font-weight:700;letter-spacing:.2em;color:#C95028}
@media (prefers-color-scheme:dark){body{background:#1A120C;color:#F3EEE4}a,.brand{color:#E77140}code{background:#352820}}"""
pages = {"privacy": "Privacy Policy", "terms": "Terms of Use"}
def page(title, body):
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)} · ate</title><meta name="color-scheme" content="light dark"><style>{CSS}</style></head>
<body><main><nav><span class="brand">ATE</span> <a href="./privacy.html">Privacy</a><a href="./terms.html">Terms</a></nav>{body}</main></body></html>"""
for slug, title in pages.items():
    md = pathlib.Path(f"docs/legal/{slug}.md").read_text()
    (out / f"{slug}.html").write_text(page(title, markdown.markdown(md)))
    (out / slug).mkdir(exist_ok=True); (out / slug / "index.html").write_text(page(title, markdown.markdown(md)))
(out / "index.html").write_text(page("ate legal", "<h1>ate</h1><p><a href='./privacy.html'>Privacy Policy</a></p><p><a href='./terms.html'>Terms of Use</a></p><p>Contact: melusi.l.k@gmail.com</p>"))
(out / ".nojekyll").write_text("")
print("wrote", sorted(p.name for p in out.iterdir()))
