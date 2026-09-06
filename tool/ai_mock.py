"""本地 OpenAI 兼容 mock：POST /v1/chat/completions。
含「推荐」→ 返回作品 JSON；否则返回总结文本。"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

REC = json.dumps([
    {"title": "ATRI -My Dear Moments-", "reason": "高口碑剧情作，与你的偏好标签高度重合", "tags": ["剧情", "科幻", "催泪"]},
    {"title": "星之梦", "reason": "短篇催泪神作，你喜欢 Key 社风格的话不要错过", "tags": ["短篇", "催泪"]},
], ensure_ascii=False)

class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(n).decode('utf-8', errors='replace'))
        user = body['messages'][-1]['content']
        if '推荐' in user:
            content = '```json\n' + REC + '\n```'
        else:
            content = ('这是一段测试总结：你最近重温了《千恋＊万花》并给出 4 分好评，'
                       '整体偏好和风奇幻与恋爱喜剧，游玩节奏偏向短会话。'
                       '从词云看「恋爱」「奇幻」「冒险」是你的高频兴趣，'
                       '继续期待你的下一部作品吧！')
        resp = {
            "id": "mock", "object": "chat.completion", "model": body.get('model', 'mock'),
            "choices": [{"index": 0, "finish_reason": "stop",
                         "message": {"role": "assistant", "content": content}}],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
        }
        data = json.dumps(resp, ensure_ascii=False).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

HTTPServer(('127.0.0.1', 8123), H).serve_forever()
