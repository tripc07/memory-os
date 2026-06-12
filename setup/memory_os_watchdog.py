#!/usr/bin/env python3
"""Lightweight Memory OS service watchdog - minimal overhead, auto-start when offline."""
import os
import subprocess
import time
import urllib.request
import urllib.error

def check_port(port, path="/healthz", timeout=2):
    """Check if a service is responding on a port."""
    try:
        url = f"http://127.0.0.1:{port}{path}"
        urllib.request.urlopen(url, timeout=timeout)
        return True
    except:
        return False

def check_redis():
    """Check Redis via redis-cli ping."""
    try:
        result = subprocess.run(["redis-cli", "ping"], capture_output=True, text=True, timeout=2)
        return "PONG" in result.stdout
    except:
        return False

def main():
    # Load .env if exists
    env_path = os.path.expanduser("~/memory-os/.env")
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, val = line.split("=", 1)
                    if key not in os.environ:
                        os.environ[key] = val
    
    # Load Jan port from EMBEDDING_API_BASE or default
    jan_port = os.environ.get("JAN_PORT", "6767")
    emb_base = os.environ.get("EMBEDDING_API_BASE", "")
    if not jan_port and emb_base:
        import re
        m = re.search(r'(?:localhost|127\.0\.0\.1):(\d+)', emb_base)
        if m:
            jan_port = m.group(1)
    
    # Check services
    services_down = []
    
    if not check_redis():
        services_down.append("redis")
    
    if not check_port(6333, "/healthz"):
        services_down.append("qdrant")
    
    if not check_port(int(jan_port), "/v1/models"):
        services_down.append("jan")
    
    # Only start if something is down
    if services_down:
        print(f"Services down: {', '.join(services_down)} - starting...")
        subprocess.run(["pwsh", "-File", "~/memory-os/setup/start_all.ps1", "-Only", ",".join(services_down)], shell=True)
    else:
        print("All services healthy")

if __name__ == "__main__":
    main()