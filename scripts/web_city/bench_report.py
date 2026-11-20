#!/usr/bin/env python3
"""Side-by-side table of the two cities' benchmark runs (scripts/web/city_bench.gd).

    python3 scripts/web_city/bench_report.py --bench city_bench.jsonl --perf web_city_perf.jsonl [--source "iPad Pro M2, real device"]

Reads the files copied from a device's app container (or a desktop's user folder) and prints, per phase, the
Godot city's engine frame times and the web city's JS-loop frame times for the newest run of each kind. The
--source label is printed on every table: results are never shown without where they came from. Neither
column is the displayed frame cadence; use Instruments for that.
"""
import argparse
import json
import statistics


def lines(path):
    out = []
    try:
        with open(path, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line:
                    out.append(json.loads(line))
    except FileNotFoundError:
        pass
    return out


def newest_run(bench, kind):
    runs = [r for r in bench if r.get('t') == 'run' and r.get('kind') == kind]
    return runs[-1] if runs else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bench', required=True)
    ap.add_argument('--perf', required=True)
    ap.add_argument('--source', required=True, help='where the numbers came from, e.g. "iPhone 15, real device"')
    a = ap.parse_args()
    bench = lines(a.bench)
    perf = lines(a.perf)
    g = newest_run(bench, 'godot')
    w = newest_run(bench, 'web')
    print(f'Source: {a.source}')
    for label, run in (('Godot city', g), ('Web city', w)):
        if run:
            print(f'{label}: run {run["run"]}, {run.get("model")} {run.get("os")} {run.get("os_version")}, window {run.get("window")}, scale {run.get("scale")}')
        else:
            print(f'{label}: no run in these files')
    phases = [r['phase'] for r in bench if r.get('t') == 'phase' and g and r.get('run') == g['run']] or \
             [r['phase'] for r in bench if r.get('t') == 'phase' and w and r.get('run') == w['run']]
    gs = {r['phase']: r for r in bench if g and r.get('run') == g['run'] and r.get('t') == 'summary'}
    print()
    print('| Phase | Godot fps | Godot p95 ms | Web fps (mean of seconds) | Web p95 ms (worst second) | Web draw calls |')
    print('|---|---|---|---|---|---|')
    for p in phases:
        gr = gs.get(p, {})
        ws = [r for r in perf if w and r.get('bench') == w['run'] and r.get('phase') == p]
        wfps = statistics.mean(r['fps'] for r in ws) if ws else None
        wp95 = max(r['p95'] for r in ws) if ws else None
        calls = max(r.get('calls', 0) for r in ws) if ws else None
        f = lambda v, d=1: '' if v is None else f'{v:.{d}f}'
        print(f'| {p} | {f(gr.get("fps"))} | {f(gr.get("p95"))} | {f(wfps)} | {f(wp95)} | {"" if calls is None else calls} |')
    mem = [r for r in bench if r.get('t') == 'second' and r.get('stats')]
    if mem:
        print()
        for label, run in (('Godot city', g), ('Web city', w)):
            rs = [r['stats'] for r in mem if run and r.get('run') == run['run']]
            if rs:
                print(f'{label}: app footprint peak {max(s.get("footprint_mb", 0) for s in rs):.0f} MB '
                      f'(the app process only; the web page\'s WebKit processes are not in it), thermal max {max(s.get("thermal", 0) for s in rs)}')


if __name__ == '__main__':
    main()
