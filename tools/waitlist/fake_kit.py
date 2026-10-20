"""A local stand-in for the part of Kit's v4 API the Waitlist tooling uses, so the real client code is tested over
real HTTP without ever reaching Kit (US-WL06 to US-WL10).

Python 3 standard library only. It binds 127.0.0.1, keeps subscribers in memory, requires the API-key header a
test gives it, and never prints a request. Its behavior follows what `artifacts/reports/US-WL06/spike.md` and the
test-account probes showed Kit doing: `status=all` lists every state, a list is cursor-paginated, `PUT` merges the
named custom fields and replaces the address when one is given, unsubscribing sets `cancelled`, a tag create is
idempotent, a listing returns a blank custom field as an empty string where a single-record read returns null (as
Kit's listing did on 2026-10-20), and there is no API delete (`DELETE` answers 404, as Kit's does). `delete` stands
in for the founder's delete in Kit's web app: afterwards the id answers 404. A state in `refuse_unsubscribe` makes
the unsubscribe call answer 422, as Kit might for a record it already mails nothing. A test sets `mode` to `hang` (answers after a long pause), `error` (HTTP 500), `truncated` (an answer
cut short of the length it states) or `busy` (HTTP
`busy_status`, 503 unless set, for the next `busy_count` requests, then normal; `busy_retry_after` adds a
`Retry-After` header, as Kit's rate limit does with a 429).
"""
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

FIELD_NAMES = ('fit', 'beta_opt_in', 'source', 'entry')


class FakeKit(object):
    def __init__(self, api_key):
        self.api_key = api_key
        self.subscribers = {}
        self.tags = {}
        self.tag_members = {}
        self.mode = 'normal'
        self.busy_count = 0
        self.busy_status = 503
        self.busy_retry_after = None
        self.requests = []
        self.refuse_unsubscribe = set()
        self.lock = threading.Lock()
        self._next_id = 1000
        self._next_tag = 500
        self.server = None
        self.thread = None

    # Test setup.

    def add(self, email, state='active', created_at='2026-10-02T10:00:00Z', **fields):
        with self.lock:
            self._next_id += 1
            subscriber_id = self._next_id
            self.subscribers[subscriber_id] = {
                'id': subscriber_id, 'first_name': None, 'email_address': email, 'state': state,
                'created_at': created_at, 'fields': {name: fields.get(name) for name in FIELD_NAMES}}
            return subscriber_id

    def get(self, subscriber_id):
        return self.subscribers[int(subscriber_id)]

    def delete(self, subscriber_id):
        """The founder's delete in Kit's web app: the record is gone, from every listing and every read."""
        with self.lock:
            del self.subscribers[int(subscriber_id)]
            for members in self.tag_members.values():
                if int(subscriber_id) in members:
                    members.remove(int(subscriber_id))

    def start(self):
        fake = self

        class Handler(BaseHTTPRequestHandler):
            server_version = 'fake-kit'

            def log_message(self, format, *args):
                return

            def _send(self, status, payload=None, headers=None):
                body = json.dumps(payload).encode('utf-8') if payload is not None else b''
                self.send_response(status)
                for name, value in (headers or {}).items():
                    self.send_header(name, value)
                if body:
                    self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                if body:
                    self.wfile.write(body)

            def _body(self):
                length = int(self.headers.get('Content-Length') or 0)
                raw = self.rfile.read(length) if length else b''
                return json.loads(raw.decode('utf-8')) if raw else {}

            def _dispatch(self, method):
                with fake.lock:
                    fake.requests.append((method, urlparse(self.path).path, self.headers.get('X-Kit-Api-Key') == fake.api_key))
                    mode = fake.mode
                    if mode == 'busy' and fake.busy_count > 0:
                        fake.busy_count -= 1
                        extra = {'Retry-After': str(fake.busy_retry_after)} if fake.busy_retry_after is not None else None
                        return self._send(fake.busy_status, headers=extra)
                if mode == 'hang':
                    time.sleep(30)
                if mode == 'error':
                    return self._send(500)
                if mode == 'truncated':
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', '1000')
                    self.end_headers()
                    self.wfile.write(b'{"subscribers": [')
                    return None
                if self.headers.get('X-Kit-Api-Key') != fake.api_key:
                    return self._send(401, {'errors': ['The access token is invalid']})
                body = self._body() if method in ('POST', 'PUT') else {}
                parsed = urlparse(self.path)
                query = {key: values[0] for key, values in parse_qs(parsed.query).items()}
                parts = [part for part in parsed.path.split('/') if part]
                with fake.lock:
                    return self._route(method, parts, query, body)

            def _route(self, method, parts, query, body):
                if parts[:2] == ['v4', 'subscribers']:
                    if len(parts) == 2 and method == 'GET':
                        return self._list(query)
                    if len(parts) == 3:
                        subscriber = fake.subscribers.get(int(parts[2]))
                        if subscriber is None:
                            return self._send(404)
                        if method == 'GET':
                            return self._send(200, {'subscriber': subscriber})
                        if method == 'PUT':
                            if body.get('email_address') is not None:
                                subscriber['email_address'] = body['email_address']
                            if 'first_name' in body:
                                subscriber['first_name'] = body['first_name']
                            for key, value in (body.get('fields') or {}).items():
                                subscriber['fields'][key] = value
                            return self._send(200, {'subscriber': subscriber})
                    if len(parts) == 4 and parts[3] == 'unsubscribe' and method == 'POST':
                        subscriber = fake.subscribers.get(int(parts[2]))
                        if subscriber is None:
                            return self._send(404)
                        if subscriber['state'] in fake.refuse_unsubscribe:
                            return self._send(422, {'errors': ['Subscriber cannot be unsubscribed']})
                        subscriber['state'] = 'cancelled'
                        return self._send(204)
                if parts[:2] == ['v4', 'tags']:
                    if len(parts) == 2 and method == 'POST':
                        name = body['name']
                        if name not in fake.tags:
                            fake._next_tag += 1
                            fake.tags[name] = fake._next_tag
                            fake.tag_members[fake._next_tag] = []
                        return self._send(201, {'tag': {'id': fake.tags[name], 'name': name}})
                    if len(parts) == 5 and parts[3] == 'subscribers' and method == 'POST':
                        members = fake.tag_members[int(parts[2])]
                        if int(parts[4]) not in fake.subscribers:
                            return self._send(404)
                        if int(parts[4]) not in members:
                            members.append(int(parts[4]))
                        return self._send(201, {'subscriber': fake.subscribers[int(parts[4])]})
                    if len(parts) == 4 and parts[3] == 'subscribers' and method == 'GET':
                        ids = fake.tag_members[int(parts[2])]
                        return self._page([fake.subscribers[item] for item in ids], query)
                return self._send(404)

            def _list(self, query):
                items = sorted(fake.subscribers.values(), key=lambda item: -item['id'])
                if query.get('status') != 'all':
                    items = [item for item in items if item['state'] == 'active']
                wanted = query.get('email_address')
                if wanted is not None:
                    items = [item for item in items if (item['email_address'] or '').lower() == wanted.lower()]
                return self._page(items, query)

            def _page(self, items, query):
                size = int(query.get('per_page', 500))
                start = 0
                if query.get('after'):
                    after = int(query['after'])
                    ids = [item['id'] for item in items]
                    start = ids.index(after) + 1 if after in ids else len(ids)
                chunk = items[start:start + size]
                more = start + size < len(items)
                listed = [dict(item, fields={key: '' if value is None else value
                                             for key, value in (item.get('fields') or {}).items()}) for item in chunk]
                return self._send(200, {'subscribers': listed, 'pagination': {
                    'has_previous_page': start > 0, 'has_next_page': more,
                    'start_cursor': str(chunk[0]['id']) if chunk else None,
                    'end_cursor': str(chunk[-1]['id']) if chunk else None, 'per_page': size}})

            def do_GET(self):
                self._dispatch('GET')

            def do_POST(self):
                self._dispatch('POST')

            def do_PUT(self):
                self._dispatch('PUT')

            def do_DELETE(self):
                self._dispatch('DELETE')

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self

    @property
    def url(self):
        return 'http://127.0.0.1:{}'.format(self.server.server_address[1])

    def stop(self):
        if self.server is not None:
            self.server.shutdown()
            self.server.server_close()
