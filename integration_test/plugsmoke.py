import json, subprocess, sys, os, threading
plug = sys.argv[1]; tool = sys.argv[2]
raw = sys.argv[3]
if raw.startswith('b64:'):
    import base64
    raw = base64.b64decode(raw[4:]).decode()
args = json.loads(raw)
d = os.path.join(os.environ.get('CYAN_PLUGINS_ROOT') or os.path.join(os.environ.get('USERPROFILE') or os.environ['HOME'], '.cyan', 'plugins'), plug)
msgs = [
 {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}},
 {"jsonrpc":"2.0","method":"notifications/initialized"},
 {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":tool,"arguments":args}},
]
# Entry resolution: packaged plugins expose a console script named after the
# plugin (see the bundle's ./run); flat ones ship src/plugin.py or plugin.py.
if os.path.exists(os.path.join(d, 'run')) or not (
        os.path.exists(os.path.join(d,'src','plugin.py')) or os.path.exists(os.path.join(d,'plugin.py'))):
    cmd = ["uv","run","--project",".",plug]
elif os.path.exists(os.path.join(d,'src','plugin.py')):
    cmd = ["uv","run","--project",".","python","src/plugin.py"]
else:
    cmd = ["uv","run","--project",".","python","plugin.py"]
# The real consumer (engine mcp_host) keeps stdin OPEN for the life of the
# session — an early EOF cancels fastmcp's async loop mid tool-call. Mirror
# that: write the messages, hold the pipe, read replies until id==2 lands.
p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE, text=True, cwd=d)
err_buf = []
threading.Thread(target=lambda: err_buf.append(p.stderr.read()), daemon=True).start()
for m in msgs:
    p.stdin.write(json.dumps(m) + "\n"); p.stdin.flush()
result = None

def reader():
    global result
    for line in p.stdout:
        try:
            m = json.loads(line)
        except Exception:
            continue
        if m.get("id") == 2:
            result = m
            return

t = threading.Thread(target=reader, daemon=True)
t.start(); t.join(timeout=300)
try:
    p.stdin.close()
except Exception:
    pass
p.terminate()
if result is not None:
    print(json.dumps(result.get("result", result))); sys.exit(0)
print("NO_RESULT"); print("STDERR:", ("".join(err_buf))[-800:]); sys.exit(1)
