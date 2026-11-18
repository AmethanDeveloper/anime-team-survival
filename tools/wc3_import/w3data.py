import re, os
def parse_slk(path):
    rows={}; header={}; cur_y=None
    data=open(path,'rb').read().decode('utf-8','replace')
    cells={}
    x=y=0
    for line in data.split('\n'):
        line=line.rstrip('\r')
        if not line.startswith('C;'): continue
        parts=line.split(';')[1:]
        val=None
        for p in parts:
            if p.startswith('X'): x=int(p[1:])
            elif p.startswith('Y'): y=int(p[1:])
            elif p.startswith('K'): val=p[1:]
        if val is None: continue
        if val.startswith('"') and val.endswith('"'): val=val[1:-1]
        cells.setdefault(y,{})[x]=val
    hdr=cells.get(1,{})
    out={}
    for yy,r in cells.items():
        if yy==1: continue
        rid=r.get(1)
        if rid is None: continue
        out[rid]={hdr.get(k,str(k)):v for k,v in r.items()}
    return out

def parse_profile(path):
    out={}; cur=None
    data=open(path,'rb').read()
    try: txt=data.decode('utf-8')
    except: txt=data.decode('cp1251','replace')
    for line in txt.splitlines():
        if line.startswith('//'): continue
        m=re.match(r'^\[(.+)\]\s*$',line)
        if m: cur=out.setdefault(m.group(1),{}); continue
        if cur is None or '=' not in line: continue
        k,v=line.split('=',1)
        cur[k.strip()]=v
    return out
