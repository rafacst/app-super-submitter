import re, sys
from html.parser import HTMLParser

KEEP = ('font-size','font-weight','color','background','padding','gap','border-radius',
        'border','width','height','min-width','max-width','letter-spacing','text-transform',
        'flex-direction','align-items','justify-content','grid-template-columns','font-family',
        'line-height','opacity','margin','box-shadow','overflow','position','top','left','right','bottom')

def squeeze(style):
    out = []
    for part in style.split(';'):
        part = part.strip()
        if not part: continue
        k = part.split(':')[0].strip()
        if k in KEEP: out.append(part)
    return '; '.join(out)

class Outline(HTMLParser):
    def __init__(self):
        super().__init__(); self.depth = 0; self.lines = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        bits = []
        if a.get('style'):
            sq = squeeze(a['style'])
            if sq: bits.append(sq)
        for k in ('onclick','onClick'):
            if a.get(k): bits.append(f"on={a[k]}")
        info = ('  { ' + ' | '.join(bits) + ' }') if bits else ''
        self.lines.append('  '*self.depth + f"<{tag}>{info}")
        if tag not in ('br','img','input','hr','meta','link'): self.depth += 1
    def handle_endtag(self, tag):
        if tag not in ('br','img','input','hr','meta','link'): self.depth = max(0, self.depth-1)
    def handle_data(self, data):
        t = ' '.join(data.split())
        if t: self.lines.append('  '*self.depth + f'· {t}')

src = open(sys.argv[1]).read()
a, b = int(sys.argv[2]), int(sys.argv[3])
chunk = src[a:b]
# start from a clean tag boundary
i = chunk.find('<')
p = Outline(); p.feed(chunk[i:])
print('\n'.join(p.lines))
