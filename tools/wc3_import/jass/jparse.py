# -*- coding: utf-8 -*-
"""Разбор JASS (war3map.j) в простое дерево."""
import re

TOKEN_RE = re.compile(r'''
    (?P<ws>[ \t]+)
  | (?P<comment>//[^\n]*)
  | (?P<nl>\r?\n)
  | (?P<real>(?:\d+\.\d*|\.\d+))
  | (?P<hex>(?:0[xX]|\$)[0-9a-fA-F]+)
  | (?P<int>\d+)
  | (?P<fourcc>'(?:\\.|[^'\\])*')
  | (?P<str>"(?:\\.|[^"\\])*")
  | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>==|!=|<=|>=|[-+*/()\[\],=<>])
''', re.X)

KEYWORDS = {'function', 'takes', 'returns', 'nothing', 'endfunction', 'globals', 'endglobals', 'local', 'set', 'call',
            'if', 'then', 'elseif', 'else', 'endif', 'loop', 'endloop', 'exitwhen', 'return', 'and', 'or', 'not',
            'true', 'false', 'null', 'array', 'constant', 'native', 'type', 'extends', 'debug'}


class Tok:
    __slots__ = ('k', 'v', 'line')

    def __init__(self, k, v, line):
        self.k, self.v, self.line = k, v, line

    def __repr__(self):
        return '%s:%r' % (self.k, self.v)


def tokenize(src):
    out = []
    pos = 0
    line = 1
    n = len(src)
    while pos < n:
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise SyntaxError('line %d: bad char %r' % (line, src[pos:pos + 20]))
        k = m.lastgroup
        v = m.group(k)
        pos = m.end()
        if k == 'ws' or k == 'comment':
            continue
        if k == 'nl':
            if out and out[-1].k != 'nl':
                out.append(Tok('nl', '\n', line))
            line += 1
            continue
        if k == 'id' and v in KEYWORDS:
            k = 'kw'
        out.append(Tok(k, v, line))
    out.append(Tok('nl', '\n', line))
    out.append(Tok('eof', '', line))
    return out


def fourcc(s):
    body = s[1:-1].encode('latin1').decode('unicode_escape')
    if len(body) == 1:
        return ord(body)
    v = 0
    for ch in body:
        v = v * 256 + ord(ch)
    return v


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self, o=0):
        return self.t[self.i + o]

    def next(self):
        tk = self.t[self.i]
        self.i += 1
        return tk

    def accept(self, k, v=None):
        tk = self.t[self.i]
        if tk.k == k and (v is None or tk.v == v):
            self.i += 1
            return tk
        return None

    def expect(self, k, v=None):
        tk = self.accept(k, v)
        if not tk:
            cur = self.t[self.i]
            raise SyntaxError('line %d: expected %s %s, got %r' % (cur.line, k, v or '', cur))
        return tk

    def skip_nl(self):
        while self.t[self.i].k == 'nl':
            self.i += 1

    # ------------------------------------------------------------- top level
    def parse(self):
        res = {'globals': [], 'functions': [], 'types': [], 'natives': []}
        self.skip_nl()
        while self.peek().k != 'eof':
            tk = self.peek()
            if tk.k == 'kw' and tk.v == 'globals':
                self.next()
                self.skip_nl()
                while not self.accept('kw', 'endglobals'):
                    res['globals'].append(self.global_decl())
                    self.skip_nl()
            elif tk.k == 'kw' and tk.v == 'type':
                while self.peek().k != 'nl':
                    self.next()
            elif tk.k == 'kw' and tk.v in ('function', 'constant', 'native'):
                if tk.v == 'constant':
                    self.next()
                if self.peek().v == 'native':
                    self.next()
                    res['natives'].append(self.signature())
                else:
                    res['functions'].append(self.function())
            else:
                raise SyntaxError('line %d: unexpected %r' % (tk.line, tk))
            self.skip_nl()
        return res

    def global_decl(self):
        const = bool(self.accept('kw', 'constant'))
        typ = self.next().v
        arr = bool(self.accept('kw', 'array'))
        name = self.expect('id').v
        init = None
        if self.accept('op', '='):
            init = self.expr()
        self.expect('nl')
        return {'const': const, 'type': typ, 'array': arr, 'name': name, 'init': init}

    def signature(self):
        self.accept('kw', 'function')
        name = self.expect('id').v
        self.expect('kw', 'takes')
        params = []
        if not self.accept('kw', 'nothing'):
            while True:
                pt = self.next().v
                pn = self.expect('id').v
                params.append((pt, pn))
                if not self.accept('op', ','):
                    break
        self.expect('kw', 'returns')
        rt = self.next().v
        return {'name': name, 'params': params, 'ret': rt}

    def function(self):
        self.expect('kw', 'function')
        self.i -= 1
        sig = self.signature()
        self.expect('nl')
        body = self.block(('endfunction',))
        self.expect('kw', 'endfunction')
        sig['body'] = body
        return sig

    def block(self, enders):
        out = []
        self.skip_nl()
        while not (self.peek().k == 'kw' and self.peek().v in enders):
            out.append(self.statement())
            self.skip_nl()
        return out

    def statement(self):
        tk = self.next()
        line = tk.line
        if tk.k == 'kw' and tk.v == 'debug':
            tk = self.next()
        if tk.k != 'kw':
            raise SyntaxError('line %d: statement expected, got %r' % (tk.line, tk))
        v = tk.v
        if v == 'local':
            typ = self.next().v
            arr = bool(self.accept('kw', 'array'))
            name = self.expect('id').v
            init = self.expr() if self.accept('op', '=') else None
            return ('local', typ, arr, name, init, line)
        if v == 'set':
            name = self.expect('id').v
            idx = None
            if self.accept('op', '['):
                idx = self.expr()
                self.expect('op', ']')
            self.expect('op', '=')
            return ('set', name, idx, self.expr(), line)
        if v == 'call':
            e = self.expr()
            if e[0] != 'call':
                raise SyntaxError('line %d: call expected' % line)
            return ('callst', e, line)
        if v == 'return':
            if self.peek().k == 'nl':
                return ('return', None, line)
            return ('return', self.expr(), line)
        if v == 'exitwhen':
            return ('exitwhen', self.expr(), line)
        if v == 'loop':
            body = self.block(('endloop',))
            self.expect('kw', 'endloop')
            return ('loop', body, line)
        if v == 'if':
            branches = []
            cond = self.expr()
            self.expect('kw', 'then')
            body = self.block(('elseif', 'else', 'endif'))
            branches.append((cond, body))
            els = None
            while True:
                k = self.next()
                if k.v == 'elseif':
                    c = self.expr()
                    self.expect('kw', 'then')
                    branches.append((c, self.block(('elseif', 'else', 'endif'))))
                elif k.v == 'else':
                    els = self.block(('endif',))
                elif k.v == 'endif':
                    break
            return ('if', branches, els, line)
        raise SyntaxError('line %d: unknown statement %r' % (line, v))

    # ------------------------------------------------------------- expressions
    def expr(self):
        return self.or_expr()

    def or_expr(self):
        a = self.and_expr()
        while self.accept('kw', 'or'):
            a = ('bin', 'or', a, self.and_expr())
        return a

    def and_expr(self):
        a = self.not_expr()
        while self.accept('kw', 'and'):
            a = ('bin', 'and', a, self.not_expr())
        return a

    def not_expr(self):
        if self.accept('kw', 'not'):
            return ('not', self.not_expr())
        return self.cmp_expr()

    def cmp_expr(self):
        a = self.add_expr()
        while self.peek().k == 'op' and self.peek().v in ('==', '!=', '<', '>', '<=', '>='):
            op = self.next().v
            a = ('bin', op, a, self.add_expr())
        return a

    def add_expr(self):
        a = self.mul_expr()
        while self.peek().k == 'op' and self.peek().v in ('+', '-'):
            op = self.next().v
            a = ('bin', op, a, self.mul_expr())
        return a

    def mul_expr(self):
        a = self.unary()
        while self.peek().k == 'op' and self.peek().v in ('*', '/'):
            op = self.next().v
            a = ('bin', op, a, self.unary())
        return a

    def unary(self):
        if self.accept('op', '-'):
            return ('neg', self.unary())
        if self.accept('op', '+'):
            return self.unary()
        if self.peek().k == 'kw' and self.peek().v == 'not':
            return self.not_expr()
        return self.primary()

    def primary(self):
        tk = self.next()
        k, v = tk.k, tk.v
        if k == 'int':
            if len(v) > 1 and v[0] == '0':
                return ('int', int(v, 8))
            return ('int', int(v))
        if k == 'hex':
            return ('int', int(v[2:] if v[0] == '0' else v[1:], 16))
        if k == 'real':
            return ('real', float(v))
        if k == 'fourcc':
            return ('int', fourcc(v), v[1:-1])
        if k == 'str':
            return ('str', v)
        if k == 'kw':
            if v == 'true':
                return ('bool', True)
            if v == 'false':
                return ('bool', False)
            if v == 'null':
                return ('null',)
            if v == 'function':
                return ('funcref', self.expect('id').v)
            raise SyntaxError('line %d: unexpected %r' % (tk.line, v))
        if k == 'op' and v == '(':
            e = self.expr()
            self.expect('op', ')')
            return ('paren', e)
        if k == 'id':
            if self.accept('op', '('):
                args = []
                if not self.accept('op', ')'):
                    while True:
                        args.append(self.expr())
                        if self.accept('op', ')'):
                            break
                        self.expect('op', ',')
                return ('call', v, args)
            if self.accept('op', '['):
                idx = self.expr()
                self.expect('op', ']')
                return ('index', v, idx)
            return ('var', v)
        raise SyntaxError('line %d: unexpected %r' % (tk.line, tk))


def parse(src):
    return Parser(tokenize(src)).parse()


def walk_calls(stmts, out):
    """Собирает имена вызываемых функций и ссылок function X."""
    def ex(e):
        if e is None:
            return
        t = e[0]
        if t == 'call':
            out.add(e[1])
            for a in e[2]:
                ex(a)
        elif t == 'funcref':
            out.add(e[1])
        elif t == 'bin':
            ex(e[2])
            ex(e[3])
        elif t in ('not', 'neg', 'paren'):
            ex(e[1])
        elif t == 'index':
            ex(e[2])

    for s in stmts:
        t = s[0]
        if t == 'local':
            ex(s[4])
        elif t == 'set':
            ex(s[2])
            ex(s[3])
        elif t == 'callst':
            ex(s[1])
        elif t in ('return', 'exitwhen'):
            ex(s[1])
        elif t == 'loop':
            walk_calls(s[1], out)
        elif t == 'if':
            for c, b in s[1]:
                ex(c)
                walk_calls(b, out)
            if s[2]:
                walk_calls(s[2], out)
    return out


def walk_vars(stmts, out):
    """Имена переменных, которые читаются или пишутся."""
    def ex(e):
        if e is None:
            return
        t = e[0]
        if t == 'call':
            for a in e[2]:
                ex(a)
        elif t == 'bin':
            ex(e[2])
            ex(e[3])
        elif t in ('not', 'neg', 'paren'):
            ex(e[1])
        elif t == 'index':
            out.add(e[1])
            ex(e[2])
        elif t == 'var':
            out.add(e[1])

    for s in stmts:
        t = s[0]
        if t == 'local':
            ex(s[4])
        elif t == 'set':
            out.add(s[1])
            ex(s[2])
            ex(s[3])
        elif t == 'callst':
            ex(s[1])
        elif t in ('return', 'exitwhen'):
            ex(s[1])
        elif t == 'loop':
            walk_vars(s[1], out)
        elif t == 'if':
            for c, b in s[1]:
                ex(c)
                walk_vars(b, out)
            if s[2]:
                walk_vars(s[2], out)
    return out
