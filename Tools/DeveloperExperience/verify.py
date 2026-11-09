#!/usr/bin/env python3
"""Check consumer snippets, generated DocC links and preserved-demo invariants."""
import hashlib
from pathlib import Path
import re
import tempfile
from urllib.parse import unquote
from snippets import ROOT, check
from build_docs import CONTRACTS, write_catalog

check()
with tempfile.TemporaryDirectory(prefix='qualia-doc-check-') as temp:
    for module in ('QualiaKit','QualiaTesting','QualiaCoreML'):
        catalog=Path(temp)/(module+'.docc')
        write_catalog(catalog,module)
        articles={path.stem for path in catalog.glob('*.md')}
        assert {contract[0] for contract in CONTRACTS.values()} <= articles, 'Missing public contract guide'
        for path in catalog.glob('*.md'):
            for target in re.findall(r'<doc:([^>]+)>',path.read_text()):
                assert target in articles, f'Broken DocC link: {path.name}: {target}'
assert hashlib.sha256((ROOT/'qualia-demo.gif').read_bytes()).hexdigest()=='911012e2eb28f780143864aceeaa64045e9aaf0045c0fd472718eca1cc5cd823', 'Demo GIF changed'
assert '![QualiaKit demo](qualia-demo.gif)' in (ROOT/'README.md').read_text(), 'Demo GIF must remain visible'
paths=[ROOT/'README.md',ROOT/'Examples/DeveloperExperience/README.md',*sorted((ROOT/'docs').rglob('*.md'))]
for path in paths:
    text=re.sub(r'```.*?```','',path.read_text(),flags=re.S)
    for target in re.findall(r'\]\(([^)]+)\)',text):
        if target.startswith(('https://','http://','#')):continue
        target=unquote(target.split('#',1)[0])
        assert (path.parent/target).exists(),f'Broken local link: {path}: {target}'
print(f'{len(paths)} documentation pages checked; GIF preserved byte-for-byte')
