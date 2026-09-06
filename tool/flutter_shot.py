import sys, json, base64, re, asyncio

url = sys.argv[1]          # http://127.0.0.1:10104/token=  或带路径
out = sys.argv[2]
m = re.match(r"http://127\.0\.0\.1:(\d+)/(.+?)/?$", url)
port, token = m.group(1), m.group(2)

async def main():
    import websockets
    uri = f"ws://127.0.0.1:{port}/{token}"
    async with websockets.connect(uri, max_size=64*1024*1024) as ws:
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "_flutter.screenshot", "params": {}}))
        while True:
            resp = json.loads(await ws.recv())
            if resp.get("id") == 1:
                if "result" in resp and "screenshot" in resp["result"]:
                    data = base64.b64decode(resp["result"]["screenshot"])
                    open(out, "wb").write(data)
                    print("saved", out, len(data), "bytes")
                else:
                    print("resp:", json.dumps(resp)[:300])
                break

asyncio.run(main())
