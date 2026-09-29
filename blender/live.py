#!/usr/bin/env python3
"""
Run Python inside the *running* Blender through the MCP add-on's bridge
(Preferences → Add-ons → MCP, default localhost:9876). The code's `result`
dict comes back as JSON; print() output is returned too.

    python3 blender/live.py 'result = {"file": bpy.data.filepath}'
    python3 blender/live.py -f script.py
    echo 'result = {"n": len(bpy.data.objects)}' | python3 blender/live.py -

`bpy` is imported for you. Use --raw to get the full JSON response.
"""
import argparse
import json
import socket
import sys

HOST, PORT = "127.0.0.1", 9876


def run(code: str, strict_json: bool = False, timeout: float = 120.0) -> dict:
    request = json.dumps({"type": "execute", "code": "import bpy\n" + code, "strict_json": strict_json})
    with socket.create_connection((HOST, PORT), timeout=timeout) as s:
        s.sendall(request.encode("utf-8") + b"\0")
        buf = b""
        while not buf.endswith(b"\0"):
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
    return json.loads(buf.rstrip(b"\0").decode("utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("code", nargs="?", help="Python code, or - for stdin")
    ap.add_argument("-f", "--file", help="read the code from a file")
    ap.add_argument("--raw", action="store_true", help="print the whole JSON response")
    args = ap.parse_args()
    if args.file:
        code = open(args.file).read()
    elif args.code == "-" or args.code is None:
        code = sys.stdin.read()
    else:
        code = args.code
    try:
        resp = run(code)
    except ConnectionRefusedError:
        print("Blender's MCP bridge is not listening on localhost:9876. Open Blender, then Preferences → Add-ons → MCP → Start.", file=sys.stderr)
        return 2
    if args.raw:
        print(json.dumps(resp, indent=2))
    else:
        if resp.get("stdout"):
            print(resp["stdout"], end="" if resp["stdout"].endswith("\n") else "\n")
        if resp.get("status") == "ok":
            r = resp.get("result", {})
            if r:
                print(json.dumps(r, indent=2))
        else:
            print(resp.get("message", resp), file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
