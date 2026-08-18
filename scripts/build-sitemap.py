"""Build docs/sitemap.xml from docs/*.html.

Why this exists
---------------
docs/sitemap.xml was maintained by hand. On 2026-08-17 it listed 189 URLs while
docs/ held 213 pages: 25 pages had never been added, among them the Japanese
landing pages for all three paid audits (full-surface-audit-jp.html at 29,800 JPY,
token-burn-audit-jp.html and claude-md-audit-jp.html at 3,980 JPY each) and the six
free preview chapters that let a reader check the monthly before subscribing.
A site: query on Google returned results for pages that were in the sitemap and
"no results" for the ones that were not, with the same query shape as control.

This is the same failure that docs/search-index.json had on 2026-08-03, and it gets
the same treatment: generate the file, and let CI regenerate and diff so the
omission cannot come back silently.

Run after adding, renaming or removing any docs/ HTML page:

    python3 scripts/build-sitemap.py

Determinism
-----------
CI regenerates and diffs, so the output has to depend only on files in the repo.
Per-URL <lastmod>/<priority>/<changefreq> are therefore carried over from the
existing sitemap.xml rather than read from the filesystem (mtime is the checkout
time in CI) or from git (the workflow does a shallow clone). New pages get
defaults and no <lastmod>: an absent lastmod is valid and is honest about the
fact that we do not know when the page last changed.
"""
import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DOCS_DIR = SCRIPT_DIR.parent / 'docs'
SITEMAP = DOCS_DIR / 'sitemap.xml'
BASE = 'https://yurukusa.github.io/cc-safe-setup/'

# index-legacy.html is the previous version of the front page. It is kept in the
# repository for reference but must not be offered to search engines: it would
# compete with "/" for the same query with older content.
SKIP = {'index-legacy.html'}

DEFAULT_PRIORITY = '0.6'
DEFAULT_CHANGEFREQ = 'monthly'


def url_for(path: Path) -> str:
    """The address a reader should land on.

    A page that declares its own canonical wins: token-checkup.html canonicalises
    to the extensionless /token-checkup, and the sitemap has to agree with the page
    or the two disagree about which address is the real one.
    """
    text = path.read_text(encoding='utf-8', errors='replace')
    m = re.search(r'<link[^>]+rel=["\']canonical["\'][^>]*href=["\']([^"\']+)', text, re.I)
    if m and m.group(1).startswith(BASE):
        return m.group(1)
    rel = path.relative_to(DOCS_DIR).as_posix()
    if rel == 'index.html':
        return BASE
    return BASE + rel


def existing_metadata() -> dict:
    """Per-URL lastmod/priority/changefreq already recorded in the sitemap."""
    if not SITEMAP.exists():
        return {}
    raw = SITEMAP.read_text(encoding='utf-8')
    out = {}
    for block in re.findall(r'<url>(.*?)</url>', raw, re.DOTALL):
        loc = re.search(r'<loc>([^<]+)</loc>', block)
        if not loc:
            continue
        def field(name):
            m = re.search(rf'<{name}>([^<]+)</{name}>', block)
            return m.group(1) if m else None
        out[loc.group(1)] = {
            'lastmod': field('lastmod'),
            'priority': field('priority'),
            'changefreq': field('changefreq'),
        }
    return out


def main() -> None:
    meta = existing_metadata()
    urls = []
    # rglob, not glob: docs/tools/june15-readiness-audit.html lives one level down
    # and was the single URL the first version of this script silently dropped.
    for path in sorted(DOCS_DIR.rglob('*.html')):
        if path.relative_to(DOCS_DIR).as_posix() in SKIP:
            continue
        urls.append(url_for(path))

    # The front page first, then the rest in a stable order.
    urls = sorted(set(urls), key=lambda u: (u != BASE, u))

    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for u in urls:
        m = meta.get(u, {})
        parts = [f'<loc>{u}</loc>']
        if m.get('lastmod'):
            parts.append(f"<lastmod>{m['lastmod']}</lastmod>")
        parts.append(f"<priority>{m.get('priority') or DEFAULT_PRIORITY}</priority>")
        parts.append(f"<changefreq>{m.get('changefreq') or DEFAULT_CHANGEFREQ}</changefreq>")
        lines.append('<url>' + ''.join(parts) + '</url>')
    lines.append('</urlset>')

    SITEMAP.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    added = [u for u in urls if u not in meta]
    print(f'docs/sitemap.xml: {len(urls)} URLs '
          f'({len(added)} new, {len(urls) - len(added)} carried over)')
    for u in added:
        print(f'  + {u}')


if __name__ == '__main__':
    main()
