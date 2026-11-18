# -*- coding: utf-8 -*-
"""JASS карты (триггеры героев) + нужные функции Blizzard.j -> GDScript для Godot.

Выход:
  w3_consts.gd  — константы common.j/Blizzard.j (база для среды исполнения)
  w3_map.gd     — функции и глобальные переменные карты (наследует W3Runtime)
  w3_meta.json  — имена звуков, используемые типы юнитов, отчёт
"""
import json
import pickle
import re
import sys

sys.path.insert(0, '/home/claude/work/scripts/jass')
import jparse  # noqa: E402

HERE = '/home/claude/work/scripts/jass/'
OUT = sys.argv[1] if len(sys.argv) > 1 else HERE + 'out/'

ast = pickle.load(open(HERE + 'ast.pkl', 'rb'))
base = pickle.load(open(HERE + 'base_ast.pkl', 'rb'))
scope = pickle.load(open(HERE + 'scope.pkl', 'rb'))
CJ, BJ = base['common'], base['blizzard']

MF = {f['name']: f for f in ast['functions']}
BF = {f['name']: f for f in BJ['functions']}
NAT = {n['name']: n for n in CJ['natives']}
GLOB = {}
for g in CJ['globals']:
    GLOB[g['name']] = dict(g, src='common')
for g in BJ['globals']:
    GLOB[g['name']] = dict(g, src='blizzard')
for g in ast['globals']:
    GLOB[g['name']] = dict(g, src='map')

PRIM = {'integer': 'int', 'real': 'float', 'boolean': 'bool', 'string': 'String'}
DEFAULT = {'integer': '0', 'real': '0.0', 'boolean': 'false', 'string': '""', 'code': 'null'}

INIT_FUNCS = ['jasshelper__initstructs100255836', 'TimerUtils___init', 'CSData___init', 'CSSafeCache___init',
              'Knockback___Init', 'CasterSystem___InitCasterSystem', 'CSDamagers___init', 'IsTerrainWalkable___Init',
              'PUI___Init', 'InitGlobals', 'InitSounds']
# хуки MemoryLeakHelper: h__X(...) -> X(...)
HOOK = re.compile(r'^h__(.+)$')
# функции Blizzard.j, которые среда исполнения делает сама (быстрее и точнее)
OVERRIDE_BJ = {'TriggerSleepAction', 'PolledWait'}


def fname(n):
    m = HOOK.match(n)
    if m:
        n = m.group(1)
    if n in NAT or n in OVERRIDE_BJ:
        return n
    return 'f_' + n


def real_name(n):
    m = HOOK.match(n)
    return m.group(1) if m else n


# ------------------------------------------------------------------ какие функции нужны
def collect():
    need = set()
    stack = list(scope['funcs']) + ['InitTrig_' + t for t in scope['owner']] + INIT_FUNCS
    natused = set()
    while stack:
        n = real_name(stack.pop())
        if n in need:
            continue
        f = MF.get(n) or BF.get(n)
        if f is None:
            if n in NAT:
                natused.add(n)
            continue
        if n in OVERRIDE_BJ:
            natused.add(n)
            continue
        need.add(n)
        for c in jparse.walk_calls(f['body'], set()):
            c = real_name(c)
            if c not in need:
                stack.append(c)
    return need, natused


NEED, NATUSED = collect()


def func_def(n):
    return MF.get(n) or BF.get(n)


# ------------------------------------------------------------------ сопрограммы (TriggerSleepAction)
SLEEPERS = {'TriggerSleepAction', 'PolledWait'}


def find_coroutines():
    co = set(SLEEPERS)
    changed = True
    calls = {n: {real_name(c) for c in jparse.walk_calls(func_def(n)['body'], set())} for n in NEED}
    while changed:
        changed = False
        for n in NEED:
            if n not in co and calls[n] & co:
                co.add(n)
                changed = True
    return co


CORO = find_coroutines()


# ------------------------------------------------------------------ типы выражений
def ret_type(n):
    n = real_name(n)
    if n in NAT:
        return NAT[n]['ret']
    f = func_def(n)
    return f['ret'] if f else None


class FuncCtx:
    def __init__(self, f):
        self.f = f
        self.locals = {pn: (pt, False) for pt, pn in f['params']}
        self.coro = f['name'] in CORO

    def var_type(self, name):
        if name in self.locals:
            return self.locals[name][0]
        g = GLOB.get(name)
        return g['type'] if g else None


def etype(e, ctx):
    t = e[0]
    if t == 'int':
        return 'integer'
    if t == 'real':
        return 'real'
    if t == 'str':
        return 'string'
    if t == 'bool':
        return 'boolean'
    if t == 'null':
        return 'null'
    if t == 'paren':
        return etype(e[1], ctx)
    if t in ('var', 'index'):
        return ctx.var_type(e[1]) if ctx else (GLOB.get(e[1], {}).get('type'))
    if t == 'call':
        return ret_type(e[1])
    if t == 'funcref':
        return 'code'
    if t == 'not':
        return 'boolean'
    if t == 'neg':
        return etype(e[1], ctx)
    if t == 'bin':
        op = e[1]
        if op in ('==', '!=', '<', '>', '<=', '>=', 'and', 'or'):
            return 'boolean'
        a, b = etype(e[2], ctx), etype(e[3], ctx)
        if a == 'string' or b == 'string':
            return 'string'
        if a == 'real' or b == 'real':
            return 'real'
        return 'integer'
    return None


def jstr(v):
    """Строка JASS (latin1-прочитанная) -> строка GDScript."""
    body = v[1:-1]
    try:
        body = body.encode('latin1').decode('utf-8')
    except UnicodeDecodeError:
        pass
    body = body.replace('\r', '').replace('\n', '\\n')
    return '"' + body + '"'


def ex(e, ctx):
    t = e[0]
    if t == 'int':
        return str(e[1])
    if t == 'real':
        return repr(float(e[1]))
    if t == 'str':
        return jstr(e[1])
    if t == 'bool':
        return 'true' if e[1] else 'false'
    if t == 'null':
        return 'null'
    if t == 'paren':
        return ex(e[1], ctx)
    if t == 'var':
        n = e[1]
        if ctx and n in ctx.locals:
            return 'l_' + n
        return n
    if t == 'index':
        n = e[1]
        vt = ctx.var_type(n) if ctx else None
        d = DEFAULT.get(vt, 'null')
        base = ('l_' + n) if ctx and n in ctx.locals else n
        return '%s.get(%s, %s)' % (base, ex(e[2], ctx), d)
    if t == 'funcref':
        return fname(e[1])
    if t == 'not':
        return '(not %s)' % ex(e[1], ctx)
    if t == 'neg':
        return '(-%s)' % ex(e[1], ctx)
    if t == 'call':
        n = real_name(e[1])
        args = ', '.join(ex(a, ctx) for a in e[2])
        s = '%s(%s)' % (fname(e[1]), args)
        if n in CORO:
            s = '(await %s)' % s
        return s
    if t == 'bin':
        op = e[1]
        a, b = e[2], e[3]
        if op in ('==', '!='):
            ta, tb = etype(a, ctx), etype(b, ctx)
            if ta == 'null' and tb == 'string':
                a = ('str', '""')
            if tb == 'null' and ta == 'string':
                b = ('str', '""')
            if ta == 'null' or tb == 'null':
                # освобождённый объект Godot тоже считаем null
                other = b if ta == 'null' else a
                s = '_isnull(%s)' % ex(other, ctx)
                return s if op == '==' else '(not %s)' % s
            if ta == 'real' or tb == 'real':
                # в JASS сравнение вещественных нестрогое: 0.1 * 11 == 1.1
                s = '_feq(%s, %s)' % (ex(a, ctx), ex(b, ctx))
                return s if op == '==' else '(not %s)' % s
        if op == '/' and etype(a, ctx) == 'integer' and etype(b, ctx) == 'integer':
            return '_idiv(%s, %s)' % (ex(a, ctx), ex(b, ctx))
        return '(%s %s %s)' % (ex(a, ctx), op, ex(b, ctx))
    raise ValueError(e)


def coerce(e, want, ctx):
    """Присваивание real <- integer и т. п."""
    s = ex(e, ctx)
    if want == 'real' and etype(e, ctx) == 'integer':
        return 'float(%s)' % s
    if want == 'string' and etype(e, ctx) == 'null':
        return '""'
    return s


def stmts(body, ctx, ind, out):
    if not body:
        out.append(ind + 'pass')
        return
    for s in body:
        t = s[0]
        if t == 'local':
            _, typ, arr, name, init, _ln = s
            ctx.locals[name] = (typ, arr)
            if arr:
                out.append('%svar l_%s := {}' % (ind, name))
            else:
                ann = (': ' + PRIM[typ]) if typ in PRIM else ''
                val = coerce(init, typ, ctx) if init is not None else DEFAULT.get(typ, 'null')
                out.append('%svar l_%s%s = %s' % (ind, name, ann, val))
        elif t == 'set':
            _, name, idx, val, _ln = s
            vt = ctx.var_type(name)
            tgt = ('l_' + name) if name in ctx.locals else name
            if idx is not None:
                tgt = '%s[%s]' % (tgt, ex(idx, ctx))
            out.append('%s%s = %s' % (ind, tgt, coerce(val, vt, ctx)))
        elif t == 'callst':
            line = ex(s[1], ctx)
            if line.startswith('(await ') and line.endswith(')'):
                line = line[1:-1]
            out.append(ind + line)
            if real_name(s[1][1]) in CORO:
                out.append(ind + '_ev = __ev')
        elif t == 'return':
            if s[1] is None:
                out.append(ind + 'return')
            else:
                out.append(ind + 'return ' + coerce(s[1], ctx.f['ret'], ctx))
        elif t == 'exitwhen':
            out.append('%sif %s:' % (ind, ex(s[1], ctx)))
            out.append(ind + '\tbreak')
        elif t == 'loop':
            out.append(ind + 'while true:')
            stmts(s[1], ctx, ind + '\t', out)
        elif t == 'if':
            branches, els = s[1], s[2]
            for k, (c, b) in enumerate(branches):
                out.append('%s%s %s:' % (ind, 'if' if k == 0 else 'elif', ex(c, ctx)))
                stmts(b, ctx, ind + '\t', out)
            if els:
                out.append(ind + 'else:')
                stmts(els, ctx, ind + '\t', out)
        else:
            raise ValueError(s)


def gen_func(n):
    f = func_def(n)
    ctx = FuncCtx(f)
    params = []
    for pt, pn in f['params']:
        params.append('l_%s%s' % (pn, (': ' + PRIM[pt]) if pt in PRIM else ''))
    out = ['func %s(%s):' % (fname(n), ', '.join(params))]
    body = []
    if ctx.coro:
        body.append('\tvar __ev = _ev')
    stmts(f['body'], ctx, '\t', body)
    out += body
    return out


# ------------------------------------------------------------------ глобальные
def used_globals():
    vs = set()
    for n in NEED:
        jparse.walk_vars(func_def(n)['body'], vs)
    # глобальные, на которые ссылаются инициализаторы других глобальных
    more = True
    while more:
        more = False
        for v in list(vs):
            g = GLOB.get(v)
            if g and g['init'] is not None:
                s = set()
                jparse.walk_vars([('return', g['init'], 0)], s)
                for x in s - vs:
                    vs.add(x)
                    more = True
    return {v for v in vs if v in GLOB}


def literal(e):
    return e is not None and e[0] in ('int', 'real', 'str', 'bool', 'null') or (
        e is not None and e[0] == 'neg' and e[1][0] in ('int', 'real'))


def gen_consts():
    """Константы common.j: Convert*(n) -> StringName с именем константы."""
    out = ['class_name W3Consts', 'extends Node', '## Константы common.j и Blizzard.j (сгенерировано transpile.py).', '']
    for g in CJ['globals'] + BJ['globals']:
        if not g['const']:
            continue
        init = g['init']
        if init is None:
            continue
        if literal(init):
            out.append('const %s = %s' % (g['name'], ex(init, None)))
        elif init[0] == 'call' and init[1].startswith('Convert'):
            out.append('const %s = &"%s"' % (g['name'], g['name']))
        else:
            # выражения из других констант (bj_PI*2 и т. п.)
            try:
                out.append('const %s = %s' % (g['name'], ex(init, None)))
            except Exception:
                pass
    return out


def main():
    import os
    os.makedirs(OUT, exist_ok=True)
    gl = used_globals()
    consts = gen_consts()
    const_names = {line.split()[1] for line in consts if line.startswith('const ')}
    out = ['extends W3Runtime', '## Триггеры героев из карты Anime Team Survival 4.9v, переведённые из JASS.',
           '## Сгенерировано tools/wc3_import/jass/transpile.py — не править руками.',
           '@warning_ignore_start("unused_variable", "unused_parameter", "integer_division", "narrowing_conversion", '
           '"shadowed_variable", "unused_local_constant", "standalone_expression", "redundant_await", '
           '"return_value_discarded", "unsafe_method_access", "untyped_declaration", "inferred_declaration", '
           '"confusable_local_usage")', '']
    inits = []
    for v in sorted(gl):
        if v in const_names:
            continue
        g = GLOB[v]
        if g['src'] == 'common':
            continue
        typ = g['type']
        if g['array']:
            out.append('var %s := {}' % v)
            continue
        ann = (': ' + PRIM[typ]) if typ in PRIM else ''
        init = g['init']
        if init is not None and literal(init):
            out.append('var %s%s = %s' % (v, ann, coerce(init, typ, None)))
        else:
            out.append('var %s%s = %s' % (v, ann, DEFAULT.get(typ, 'null')))
            if init is not None:
                inits.append('\t%s = %s' % (v, coerce(init, typ, None)))
    out.append('')
    out.append('func _init_globals():')
    out += inits or ['\tpass']
    out.append('')
    out.append('func _init_map():')
    for n in INIT_FUNCS:
        if n in NEED:
            out.append('\t' + fname(n) + '()')
    out.append('')
    out.append('func _init_triggers():')
    trig_names = sorted(scope['owner'])
    for t in trig_names:
        if 'InitTrig_' + t in NEED:
            out.append('\tf_InitTrig_%s()' % t)
    out.append('')
    nlines = 0
    for n in sorted(NEED, key=lambda x: (x not in MF, x)):
        fl = gen_func(n)
        out += fl
        out.append('')
        nlines += len(fl)
    open(OUT + 'w3_map.gd', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    open(OUT + 'w3_consts.gd', 'w', encoding='utf-8').write('\n'.join(consts) + '\n')
    meta = {'natives': sorted(NATUSED), 'functions': len(NEED), 'coroutines': len(CORO), 'lines': nlines,
            'owner': scope['owner']}
    json.dump(meta, open(OUT + 'w3_meta.json', 'w'), indent=1, ensure_ascii=False)
    print('functions', len(NEED), 'coroutines', len(CORO), 'globals', len(gl), 'lines', nlines,
          'natives', len(NATUSED))


if __name__ == '__main__':
    main()
