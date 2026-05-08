"""Build docs/search-index.json from docs/*.html.
Run after adding or updating any docs/ HTML page.
"""
import json
import re
from pathlib import Path
SCRIPT_DIR = Path(__file__).resolve().parent
DOCS_DIR = SCRIPT_DIR.parent / 'docs'
SKIP = {'search.html', 'index.html'}
def first_paragraph(body: str) -> str:
    for m in re.finditer(r'<p[^>]*>(.*?)</p>', body, re.DOTALL):
        text = re.sub(r'<[^>]+>', '', m.group(1))
        text = re.sub(r'\s+', ' ', text).strip()
        if len(text) > 50:
            return text[:300]
    return ''
def extract(path: Path) -> dict:
    text = path.read_text(encoding='utf-8')
    title = re.search(r'<title>([^<]+)</title>', text)
    desc = re.search(r'<meta name="description" content="([^"]+)"', text)
    kw = re.search(r'<meta name="keywords" content="([^"]+)"', text)
    h1 = re.search(r'<h1[^>]*>([^<]+)</h1>', text)
    body = re.search(r'<body[^>]*>(.*?)</body>', text, re.DOTALL)
    snippet = first_paragraph(body.group(1)) if body else ''
    title_text = (
        title.group(1).strip() if title
        else h1.group(1).strip() if h1
        else path.stem
    )
    return {
        'url': path.name,
        'title': title_text[:200],
        'description': (desc.group(1).strip() if desc else '')[:300],
        'keywords': (kw.group(1).strip() if kw else '')[:300],
        'snippet': snippet,
    }
def main() -> None:
    items = [extract(p) for p in sorted(DOCS_DIR.glob('*.html')) if p.name not in SKIP]
    out = DOCS_DIR / 'search-index.json'
    out.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Indexed {len(items)} pages into {out.relative_to(SCRIPT_DIR.parent)}')
if __name__ == '__main__':
    main()
