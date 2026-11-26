import json
import re
import subprocess
import sys
import time


def cpu_seconds(pid):
    value = subprocess.check_output(["ps", "-o", "time=", "-p", str(pid)]).decode().strip()
    total = 0.0
    for part in value.split(":"):
        total = total * 60 + float(part)
    return total


def footprint_mb(pid):
    try:
        output = subprocess.check_output(["footprint", "-p", str(pid)], stderr=subprocess.DEVNULL).decode()
    except subprocess.CalledProcessError:
        return -1.0
    match = re.search(r"Footprint:\s+([\d.]+)\s+(KB|MB|GB)", output)
    if not match:
        return -1.0
    value = float(match.group(1))
    return {"KB": value / 1024, "MB": value, "GB": value * 1024}[match.group(2)]


def gpu_utilization():
    output = subprocess.check_output(["ioreg", "-r", "-d", "1", "-w", "0", "-c", "IOAccelerator"]).decode()
    match = re.search(r'"Device Utilization %"=(\d+)', output)
    return int(match.group(1)) if match else -1


def main():
    if len(sys.argv) < 3:
        print("usage: sysmon.py <pid> <seconds> [label]")
        sys.exit(1)
    pid = int(sys.argv[1])
    seconds = float(sys.argv[2])
    label = sys.argv[3] if len(sys.argv) > 3 else ""
    window_server = subprocess.check_output(["pgrep", "-x", "WindowServer"]).decode().split()[0]
    start = time.time()
    app_start = cpu_seconds(pid)
    ws_start = cpu_seconds(window_server)
    gpu_samples = []
    while time.time() - start < seconds:
        gpu_samples.append(gpu_utilization())
        time.sleep(0.5)
    elapsed = time.time() - start
    result = {
        "label": label,
        "seconds": round(elapsed, 1),
        "appCores": round((cpu_seconds(pid) - app_start) / elapsed, 3),
        "windowServerCores": round((cpu_seconds(window_server) - ws_start) / elapsed, 3),
        "gpuPercent": round(sum(gpu_samples) / max(1, len(gpu_samples)), 1),
        "footprintMB": round(footprint_mb(pid), 1),
    }
    print(json.dumps(result))


if __name__ == "__main__":
    main()
