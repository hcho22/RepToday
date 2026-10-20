#!/usr/bin/env python3
"""A local stand-in for the places the Waitlist pages post to (US-WL02, US-WL05).

It exists so no test ever posts to Kit's real sign-up endpoint or to the production event
sink. It is Python 3 standard library only, binds 127.0.0.1, keeps what it receives in memory
and prints counts only, never a value.

  python3 tools/waitlist/stub-receiver.py [--port 8799]

Routes (all send permissive CORS headers, like Kit's public endpoint):
  POST /signup          a sign-up body (form-encoded); answers as the current mode says
  POST /event           a web event body (JSON, any content type)
  GET  /received        {"signups": [...], "events": [...]} as received so far
  POST /__reset         forget everything and go back to the success mode
  POST /__mode          body {"mode": "success" | "quarantined" | "errors" | "fail" | "slow"}
  GET  /forms/guards/*  a tiny stand-in for Kit's reCAPTCHA page: it reports a size, and a
                        button reports "confirmed" to the page that framed it

The pages find it at http://127.0.0.1:8799 when they are served from localhost.
"""

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl

LOCK = threading.Lock()
STATE = {'signups': [], 'events': [], 'mode': 'success'}

GUARD_PAGE = b"""<!doctype html><meta charset="utf-8"><title>guard stub</title>
<body style="font:16px sans-serif;margin:0;padding:12px">
<p>One more step (test stand-in)</p>
<button id="ok" type="button" style="min-height:44px">I'm not a robot</button>
<script>
parent.postMessage({name: 'ckjs:guard:loaded'}, '*');
parent.postMessage({name: 'ckjs:guard:size', width: 300, height: 120}, '*');
document.getElementById('ok').addEventListener('click', function () {
  parent.postMessage({name: 'ckjs:guard:confirmed'}, '*');
});
</script></body>"""


class Handler(BaseHTTPRequestHandler):
    server_version = 'waitlist-stub'

    def log_message(self, format, *args):  # never log a request line, it may carry a value
        return

    def _send(self, status, body=b'', content_type='application/json'):
        self.send_response(status)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', 'content-type')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        if body or status == 200:
            self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get('Content-Length') or 0)
        return self.rfile.read(length).decode('utf-8', 'replace') if length else ''

    def do_OPTIONS(self):
        self._send(204)

    def do_GET(self):
        if self.path == '/received':
            with LOCK:
                self._send(200, json.dumps({'signups': STATE['signups'], 'events': STATE['events']}).encode())
        elif self.path.startswith('/forms/guards/'):
            self._send(200, GUARD_PAGE, 'text/html; charset=utf-8')
        else:
            self._send(404, b'{}')

    def do_POST(self):
        path = self.path.split('?')[0]
        body = self._body()
        if path == '/__reset':
            with LOCK:
                STATE.update(signups=[], events=[], mode='success')
            self._send(200, b'{}')
        elif path == '/__mode':
            with LOCK:
                STATE['mode'] = json.loads(body or '{}').get('mode', 'success')
            self._send(200, b'{}')
        elif path == '/event':
            with LOCK:
                STATE['events'].append({'content_type': self.headers.get('Content-Type', ''), 'origin': self.headers.get('Origin', ''), 'cookie': self.headers.get('Cookie', ''), 'body': body})
            self._send(204)
        elif path == '/signup':
            with LOCK:
                mode = STATE['mode']
                if mode in ('success', 'slow', 'errors', 'quarantined'):
                    pass
                if mode in ('success', 'slow'):
                    STATE['signups'].append(parse_qsl(body, keep_blank_values=True))
            if mode == 'slow':
                time.sleep(1.5)
            if mode == 'fail':
                self._send(500, b'{}')
            elif mode == 'errors':
                self._send(422, b'{"errors":["email_address contains an invalid email address"]}')
            elif mode == 'quarantined':
                origin = 'http://%s:%d' % self.server.server_address[:2]
                self._send(200, json.dumps({'status': 'quarantined', 'url': origin + '/forms/guards/test'}).encode())
            else:
                self._send(200, b'{"status":"success","redirect_url":"https://example.invalid/success"}')
        else:
            self._send(404, b'{}')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--port', type=int, default=8799)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print('waitlist stub receiver on http://127.0.0.1:%d (counts only, no values are printed)' % args.port, flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
