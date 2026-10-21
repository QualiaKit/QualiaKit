#!/usr/bin/env python3
"""Check consumer snippet, catalog, local-link and preserved-demo invariants."""
import hashlib
from pathlib import Path
import re
from urllib.parse import unquote
from snippets import ROOT, check
from build_docs import sync_catalog

check()
sync_catalog()
assert hashlib.sha256((ROOT/'qualia-demo.gif').read_bytes()).hexdigest()=='911012e2eb28f780143864aceeaa64045e9aaf0045c0fd472718eca1cc5cd823', 'Demo GIF changed'
assert '![QualiaKit demo](qualia-demo.gif)' in (ROOT/'README.md').read_text(), 'Demo GIF must remain visible'
paths=[ROOT/'README.md',ROOT/'Examples/DeveloperExperience/README.md',*sorted((ROOT/'docs').glob('*.md'))]
for path in paths:
    text=re.sub(r'```.*?```','',path.read_text(),flags=re.S)
    for target in re.findall(r'\]\(([^)]+)\)',text):
        if target.startswith(('https://','http://','#')):continue
        target=unquote(target.split('#',1)[0])
        assert (path.parent/target).exists(),f'Broken local link: {path}: {target}'
print(f'{len(paths)} documentation pages checked; GIF preserved byte-for-byte')
