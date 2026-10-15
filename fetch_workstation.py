#!/usr/bin/env python3
import sys
import os
import json
import subprocess

PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))
STATUS_FILE = os.path.join(PROJECT_DIR, "workstation_status.json")

def fetch_stats():
    cmd = [
        "ssh", "-o", "ConnectTimeout=3", "-o", "BatchMode=yes", "-o", "LogLevel=ERROR",
        "dio", "docker exec agy-workstation /home/ubuntu/.local/bin/workstation_stats.py"
    ]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
        if res.returncode == 0 and res.stdout.strip():
            raw = res.stdout.strip()
            # Validate JSON
            data = json.loads(raw)
            with open(STATUS_FILE, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print("OK")
            return
    except Exception as e:
        print(f"Fetch error: {e}", file=sys.stderr)

    # Fallback offline state
    offline_data = {
        "status": "offline",
        "error": "Сервер DIO недоступен по SSH",
        "host": {"load_1m": 0, "load_5m": 0, "load_15m": 0, "ram_total_mb": 0, "ram_used_mb": 0, "swap_total_mb": 0, "swap_used_mb": 0},
        "container": {"ram_used_mb": 0, "ram_limit_mb": 14336, "ram_percent": 0, "pids_count": 0},
        "summary": {"total": 0, "active": 0, "orphan": 0},
        "sessions": []
    }
    with open(STATUS_FILE, "w", encoding="utf-8") as f:
        json.dump(offline_data, f, ensure_ascii=False, indent=2)

def handle_action(action, *args):
    if action == "--reap":
        cmd = ["ssh", "-o", "ConnectTimeout=4", "-o", "BatchMode=yes", "dio", "docker exec agy-workstation /home/ubuntu/.local/bin/workstation_stats.py --reap"]
        subprocess.run(cmd, timeout=6)
        fetch_stats()
    elif action == "--restart":
        cmd = ["ssh", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes", "dio", "docker restart agy-workstation"]
        subprocess.run(cmd, timeout=15)
        fetch_stats()
    elif action == "--kill" and args:
        cmd = ["ssh", "-o", "ConnectTimeout=4", "-o", "BatchMode=yes", "dio", f"docker exec agy-workstation /home/ubuntu/.local/bin/workstation_stats.py --kill {args[0]}"]
        subprocess.run(cmd, timeout=6)
        fetch_stats()

def main():
    if len(sys.argv) > 1:
        handle_action(sys.argv[1], *sys.argv[2:])
    else:
        fetch_stats()

if __name__ == "__main__":
    main()
