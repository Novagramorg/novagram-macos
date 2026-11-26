import subprocess, time, sys, re, json
out = sys.argv[1]
interval = float(sys.argv[2]) if len(sys.argv) > 2 else 0.25
ws = subprocess.check_output(["pgrep", "-x", "WindowServer"]).decode().split()[0]
def ws_cpu():
    t = subprocess.check_output(["ps", "-o", "time=", "-p", ws]).decode().strip()
    parts = t.split(":")
    s = 0.0
    for p in parts:
        s = s * 60 + float(p)
    return s
def gpu():
    o = subprocess.check_output(["ioreg", "-r", "-d", "1", "-w", "0", "-c", "IOAccelerator"]).decode()
    d = re.search(r'"Device Utilization %"=(\d+)', o)
    r = re.search(r'"Renderer Utilization %"=(\d+)', o)
    return (int(d.group(1)) if d else -1, int(r.group(1)) if r else -1)
with open(out, "a") as f:
    while True:
        t = time.time()
        c = ws_cpu()
        d, r = gpu()
        f.write(json.dumps({"t": t, "ws": c, "gpu": d, "rend": r}) + "\n")
        f.flush()
        time.sleep(max(0, interval - (time.time() - t)))
