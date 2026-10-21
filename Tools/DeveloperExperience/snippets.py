#!/usr/bin/env python3
"""Keep documented Swift snippets identical to compiled consumer sources."""
import argparse
import re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PATTERN=re.compile(r'<!-- snippet: ([\w./-]+)#([\w-]+) -->\n```swift\n(.*?)\n```',re.S)

def snippet(path, name):
    source=(ROOT/path).read_text()
    start='// snippet:start '+name+'\n';end='// snippet:end '+name
    if source.count(start)!=1 or source.count(end)!=1:raise ValueError(f'Nonunique snippet {path}#{name}')
    return source.split(start,1)[1].split(end,1)[0].rstrip()

def check(write=False):
    count=0
    for path in [ROOT/'README.md', *sorted((ROOT/'docs').glob('*.md')), ROOT/'Examples/DeveloperExperience/README.md']:
        if not path.exists():continue
        text=path.read_text();matches=list(PATTERN.finditer(text))
        if text.count('```swift')!=len(matches):raise ValueError(f'Unbound Swift snippet in {path}')
        for match in reversed(matches):
            expected=snippet(match[1],match[2]);count+=1
            if write:text=text[:match.start(3)]+expected+text[match.end(3):]
            elif match[3]!=expected:raise ValueError(f'Snippet drift: {path}: {match[2]}')
        if write:path.write_text(text)
    if count<8:raise ValueError('Expected at least eight compiled documentation snippets')
    for path in (ROOT/'Examples/DeveloperExperience').rglob('*.swift'):
        if '.build' in path.parts:continue
        text=path.read_text()
        if '@testable' in text or '@_spi' in text or 'try?' in text:raise ValueError(f'Unsafe consumer shortcut: {path}')
    print(f'{count} documentation snippets match public consumer source files')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--write',action='store_true');args=p.parse_args();check(args.write)
