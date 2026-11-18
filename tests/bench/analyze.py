import sys,csv,statistics as st
lines=open(sys.argv[1]).read().splitlines()
i=[k for k,l in enumerate(lines) if l.startswith("tick,timestamp")][0]
rows=[r for r in csv.DictReader(lines[i:]) if r["tick"][:1]=="t"]
def s(col):
    v=[int(r[col]) for r in rows[10:]]
    return st.mean(v)/1e6, st.median(v)/1e6, max(v)/1e6
w,sc=s("wholeUpdate"),s("scriptUpdate")
print(f"RESULT ticks={len(rows)} whole mean={w[0]:.4f} median={w[1]:.4f} max={w[2]:.1f} | script mean={sc[0]:.4f} median={sc[1]:.4f} max={sc[2]:.1f} (ms, first 10 ticks skipped)")
for col in ("wholeUpdate","scriptUpdate"):
    v=[int(r[col]) for r in rows]
    top=sorted(range(len(v)),key=lambda k:-v[k])[:2]
    print("PEAK",col," ".join(f"row{k}({rows[k]['tick']})={v[k]/1e6:.1f}ms" for k in top))
import os
st0=int(os.environ.get("SHOW_TICK","5"))
print("SHOWWIN scriptUpdate ms from show tick:"," ".join(f"{int(r['scriptUpdate'])/1e6:.1f}" for r in rows[st0:st0+12]))

if int(os.environ.get("STRESS","0")) > 0:
    # windows from the bench driver: ARRIVE = SHOW+100 (gather + fill + 10 s arrival), LEAVE = SHOW+1300 (departure)
    hold = int(os.environ.get("HOLD", "1300"))
    # PARKED = the last 500 ticks before the departure (with HOLD >= 2300 the ships are all settled: the float cost alone)
    for name, a, b in (("arrive", st0 + 100, st0 + hold), ("parked", st0 + hold - 500, st0 + hold - 10), ("leave", st0 + hold, st0 + hold + 600)):
        v = sorted(int(r["scriptUpdate"]) / 1e6 for r in rows[a:b])
        if not v: continue
        over = sum(1 for x in v if x > 16.67)
        print(f"STRESS {name}: ticks={len(v)} script mean={st.mean(v):.2f} median={v[len(v)//2]:.2f} p95={v[int(len(v)*.95)]:.2f} max={v[-1]:.1f} ms, ticks over 16.7 ms={over}")
