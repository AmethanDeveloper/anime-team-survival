import struct
def parse_obj(path, has_levels=True):
    b=open(path,'rb').read(); p=0
    def u32():
        nonlocal p; v=struct.unpack_from('<i',b,p)[0]; p+=4; return v
    def s4():
        nonlocal p; v=b[p:p+4]; p+=4; return v.decode('latin1')
    def cstr():
        nonlocal p; e=b.index(b'\0',p); v=b[p:e]; p=e+1
        try: return v.decode('utf-8')
        except: return v.decode('cp1251','replace')
    ver=u32(); out={}
    for table in (0,1):
        n=u32()
        for _ in range(n):
            oid=s4(); nid=s4()
            key = nid if nid!='\0\0\0\0' else oid
            sets=1
            if ver>=3: sets=u32()
            mods={}
            for si in range(sets):
                if ver>=3: setflag=u32()
                m=u32()
                for _ in range(m):
                    mid=s4(); vt=u32()
                    lvl=0
                    if has_levels: lvl=u32(); dp=u32()
                    if vt==0: v=u32()
                    elif vt in (1,2): v=struct.unpack_from('<f',b,p)[0]; p+=4
                    else: v=cstr()
                    end=s4()
                    mods[(mid,lvl)]=v
            out[key]={'base':oid,'custom':nid!='\0\0\0\0','mods':mods}
    return ver,out
