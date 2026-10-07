"""Extract top-level Julia definitions (with their docstrings) by name from a source file.

Usage: python3 extract.py SOURCE NAME [NAME ...] > out.jl
"""
import re, sys
src, names = sys.argv[1], sys.argv[2:]
lines = open(src).read().split('\n')
n = len(lines)
# 1. mark docstring lines
indoc = [False]*n
i = 0
while i < n:
    l = lines[i]
    if l.startswith('"""'):
        if l.count('"""') >= 2 and len(l.strip()) > 3:
            indoc[i] = True; i += 1; continue
        j = i + 1
        while j < n and '"""' not in lines[j]:
            j += 1
        for k in range(i, min(j+1, n)): indoc[k] = True
        i = j + 1; continue
    if l.startswith('"') and l.rstrip().endswith('"') and not l.startswith('""'):
        indoc[i] = True
    i += 1
# multi-line plain "..." docstrings
i = 0
while i < n:
    l = lines[i]
    if not indoc[i] and l.startswith('"') and not l.startswith('"""') and l.count('"') == 1:
        j = i + 1
        while j < n and '"' not in lines[j]: j += 1
        for k in range(i, min(j+1, n)): indoc[k] = True
        i = j + 1; continue
    i += 1
def header(i):
    l = lines[i]
    return (l and not indoc[i] and not l[0].isspace() and not l.startswith(('end', ')', ']', '}', '#')))
heads = [i for i in range(n) if header(i)]
def blockstart(h):
    s = h
    while s - 1 >= 0 and (indoc[s-1] or lines[s-1].startswith('#')): s -= 1
    return s
items = []
for k, h in enumerate(heads):
    e = blockstart(heads[k+1]) if k + 1 < len(heads) else n
    items.append((blockstart(h), e, lines[h]))
out = []
for name in names:
    pat = re.compile(r'^(?:@kernel\s+)?(?:Base\.@kwdef\s+)?(?:mutable\s+)?(?:function\s+|struct\s+|const\s+|@inline\s+)?(?:Base\.)?(?:function\s+)?' + re.escape(name) + r'(?![\w!])')
    found = [it for it in items if pat.match(it[2])]
    if not found:
        sys.stderr.write(f"NOT FOUND: {name}\n"); sys.exit(1)
    for (a, b, h) in found:
        out.append('\n'.join(lines[a:b]).rstrip())
print('\n\n'.join(out))
