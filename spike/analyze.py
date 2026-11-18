import sys,csv,statistics as st
lines=open(sys.argv[1]).read().splitlines()
i=[k for k,l in enumerate(lines) if l.startswith("tick,timestamp")][0]
rows=list(csv.DictReader(lines[i:]))
rows=[r for r in rows if r["tick"][:1]=="t"]
print("rows",len(rows),"cols units: ns presumed; first row wholeUpdate",rows[0]["wholeUpdate"])
def stat(col,skip):
    v=[int(r[col]) for r in rows[skip:]]
    return st.mean(v)/1e6, st.median(v)/1e6, max(v)/1e6
for skip in (0,10):
    for col in ("wholeUpdate","scriptUpdate"):
        m,md,mx=stat(col,skip)
        print(f"skip{skip} {col}: mean {m:.4f} ms median {md:.4f} ms max {mx:.3f} ms")
