BAD = ('alternate', 'portrait', 'decay', 'dissipate', 'morph')

def choose(names, vis=None, durs=None, lift=None, height=1.7):
    vis = vis or {}
    durs = durs or {}
    lift = lift or {}
    names = [n for n in names if vis.get(n, 1.0) >= 0.85 and durs.get(n, 1.0) > 0.05] or names
    base = min([lift[n][0] for n in names if n in lift and n.lower().startswith('stand')] or [0])
    def calm(n, max_lift=60 * max(1.0, height / 1.7), max_dur=2.4):
        return lift.get(n, [0, 0])[0] - base <= max_lift and durs.get(n, 1.0) <= max_dur
    calm_names = [n for n in names if calm(n)]
    low = {n: n.lower().strip() for n in names}

    def first(*preds):
        for p in preds:
            for n in names:
                if p(low[n]):
                    return n
        return None

    ok = lambda s: not any(b in s for b in BAD)
    out = {}
    out['Idle'] = first(lambda s: s == 'stand', lambda s: s.startswith('stand') and ok(s) and not any(
        w in s for w in ('ready', 'hit', 'victory', 'work', 'channel', 'swim')), lambda s: 'stand' in s and ok(s),
        lambda s: 'stand' in s)
    out['Run'] = first(lambda s: s == 'walk', lambda s: s.startswith('walk') and ok(s) and 'fast' not in s,
                       lambda s: ('walk' in s or 'run' in s) and ok(s), lambda s: 'walk' in s)
    full = names
    names = calm_names or names
    low = {n: n.lower().strip() for n in full}
    out['Attack'] = first(lambda s: s in ('attack', 'attack 1', 'attack - 1', 'attack -1', 'attack one'),
                          lambda s: s.startswith('attack') and ok(s) and 'slam' not in s and 'spell' not in s,
                          lambda s: 'attack' in s and ok(s), lambda s: 'attack' in s)
    out['Cast'] = first(lambda s: s in ('spell', 'spell one', 'spell 1'),
                        lambda s: s.startswith('spell') and ok(s) and 'channel' not in s,
                        lambda s: s.startswith('spell') and ok(s), lambda s: 'attack slam' in s and ok(s),
                        lambda s: 'attack spell' in s and ok(s), lambda s: 'spell' in s and ok(s),
                        lambda s: s.startswith('attack') and ok(s) and s != low.get(out['Attack'] or '', ''))
    names = full
    out['Death'] = first(lambda s: s == 'death', lambda s: s.startswith('death') and ok(s), lambda s: 'death' in s)
    return {k: v for k, v in out.items() if v}
