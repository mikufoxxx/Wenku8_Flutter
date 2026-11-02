#!/usr/bin/env python3
"""Build only the public project landing page; never export the source tree."""
from html import escape
import json
from pathlib import Path
import shutil
from string import Template

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'build/project-site'
OUTPUT.mkdir(parents=True, exist_ok=True)
template = Template((ROOT / 'site/template.html').read_text())
content = json.loads((ROOT / 'site/content.json').read_text())
for locale, fields in content.items():
    values = {key: escape(value, quote=True) for key, value in fields.items()}
    values.update(locale=locale, other_lang='zh-CN' if locale == 'en' else 'en')
    page = 'index.html' if locale == 'en' else 'zh.html'
    (OUTPUT / page).write_text(template.substitute(values))
shutil.copyfile(ROOT / 'site/site.css', OUTPUT / 'site.css')
(OUTPUT / '.nojekyll').touch()
assets = OUTPUT / 'assets'
assets.mkdir(exist_ok=True)
for name in ['discovery.png', 'reader.png', 'settings.png',
             'sponsor-en-light.svg', 'sponsor-en-dark.svg',
             'sponsor-zh-light.svg', 'sponsor-zh-dark.svg']:
    shutil.copyfile(ROOT / 'docs/images' / name, assets / name)
print(f'Built static project pages: {OUTPUT}')
