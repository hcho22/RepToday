"""The Waitlist's store: Kit (US-WL06, OQ1 Option A) and a synthetic stand-in for tests (US-WL07).

Both stores answer the same questions and none ever hands the producer an address: a listing returns a
`Subscriber` that holds only the id, the confirmation state, the creation time and the four stored answers,
because the email is dropped where the response is parsed. The two places an address is read on purpose are
`email_of` (the founder's `show`) and the exact-match `find_id_by_email` (the founder's `remove`).

What Kit's API does and does not do is recorded in `artifacts/reports/US-WL06/spike.md`: it cannot delete a
subscriber, so `erase` unsubscribes, overwrites the address with a placeholder that is not an address, and
blanks every custom field (decision D2). A list trails a fresh write by up to a couple of minutes, a
single-record read does not.

An error raised here names the step and the HTTP status. It never carries a response body, a URL with an
address in its query, or the credential.
"""
import json
import os
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import namedtuple
from pathlib import Path

from wl_common import NETWORK_TIMEOUT_SECONDS, WaitlistError, field_key, load_contract, write_private_atomic

KIT_BASE_URL = 'https://api.kit.com'
BASE_URL_ENV = 'WAITLIST_KIT_BASE_URL'  # loopback only, so a test can point the real client at a local fake
KEYCHAIN_SERVICE_ENV = 'WAITLIST_KIT_KEYCHAIN_SERVICE'
DEFAULT_KEYCHAIN_SERVICE = 'com.reptoday.waitlist.kit'
KEYCHAIN_ACCOUNT = 'api-key'
API_KEY_HEADER = 'X-Kit-Api-Key'

PAGE_SIZE = 1000
MAX_PAGES = 200
# A busy answer is retried a bounded number of times: 502-504 twice, and 429 (Kit's rate limit) up to five times,
# waiting as long as Kit's `Retry-After` asks, never more than MAX_RETRY_WAIT_SECONDS a time. The run's own time limit
# still ends a run that keeps being told to wait.
RETRY_STATUSES = (429, 502, 503, 504)
RETRY_PAUSES = (1.0, 2.0)
RATE_LIMIT_RETRIES = 5
MAX_RETRY_WAIT_SECONDS = 30.0

# Kit's subscriber states. `inactive` is a sign-up that has not confirmed; `cancelled` is an unsubscribed one.
ACTIVE, INACTIVE, CANCELLED = 'active', 'inactive', 'cancelled'
# The Kit custom-field keys, named once in contract.json: the three the form posts and the one the producer writes.
_CONTRACT = load_contract()
FIELD_KEYS = {'fit': field_key(_CONTRACT, 'fit'), 'beta': field_key(_CONTRACT, 'beta_opt_in'),
              'source': field_key(_CONTRACT, 'source'), 'entry': _CONTRACT['kit_producer_fields']['entry']}

Subscriber = namedtuple('Subscriber', 'id state created_at fit beta source entry scrubbed')


class StoreError(WaitlistError):
    pass


def placeholder_for(subscriber_id):
    """What replaces an erased subscriber's address: a value Kit accepts that is not an address."""
    return 'removed-{}'.format(subscriber_id)


def read_api_key(service=None):
    """The Kit API key from the macOS Keychain. The value goes into a request header and nowhere else."""
    service = service or os.environ.get(KEYCHAIN_SERVICE_ENV) or DEFAULT_KEYCHAIN_SERVICE
    try:
        done = subprocess.run(['security', 'find-generic-password', '-s', service, '-a', KEYCHAIN_ACCOUNT, '-w'],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=NETWORK_TIMEOUT_SECONDS * 3)
    except (OSError, subprocess.SubprocessError):
        done = None
    key = done.stdout.decode('utf-8', 'replace').strip() if done is not None and done.returncode == 0 else ''
    if not key:
        raise StoreError('no Kit API key in the Keychain (service {}, account {})'.format(service, KEYCHAIN_ACCOUNT))
    return key


def checked_base_url(url):
    """Kit's own origin, or a loopback address a test serves a fake on. Anything else is refused, so a stray
    setting can never send the credential somewhere else."""
    parsed = urllib.parse.urlparse(url)
    if url.rstrip('/') == KIT_BASE_URL:
        return KIT_BASE_URL
    if parsed.scheme == 'http' and parsed.hostname in ('127.0.0.1', 'localhost', '::1'):
        return url.rstrip('/')
    raise StoreError('the Kit base URL must be Kit\'s own origin or a loopback address')


def normalize_state(value):
    return value if isinstance(value, str) else ''


class KitStore(object):
    def __init__(self, api_key, base_url=None, timeout=NETWORK_TIMEOUT_SECONDS):
        self._key = api_key
        self._base = checked_base_url(base_url or os.environ.get(BASE_URL_ENV) or KIT_BASE_URL)
        self._timeout = timeout

    @classmethod
    def from_keychain(cls, service=None):
        return cls(read_api_key(service))

    # One request. `label` names the step in an error; the path may carry an address, so it is never printed.

    def _call(self, label, method, path, body=None, expect=(200, 201, 204)):
        data = json.dumps(body).encode('utf-8') if body is not None else None
        attempt = 0
        while True:
            request = urllib.request.Request(self._base + path, data=data, method=method, headers={
                API_KEY_HEADER: self._key, 'Accept': 'application/json', 'Content-Type': 'application/json'})
            retry_after = None
            try:
                with urllib.request.urlopen(request, timeout=self._timeout) as response:
                    status, raw = response.status, response.read()
            except urllib.error.HTTPError as error:
                status, raw = error.code, b''
                retry_after = error.headers.get('Retry-After') if error.headers else None
                error.close()
            except (urllib.error.URLError, OSError):
                raise StoreError('Kit request failed ({}: no answer)'.format(label))
            allowed = RATE_LIMIT_RETRIES if status == 429 else len(RETRY_PAUSES)
            if status in RETRY_STATUSES and attempt < allowed:
                time.sleep(self._pause(attempt, retry_after))
                attempt += 1
                continue
            if status not in expect:
                raise StoreError('Kit request failed ({}: HTTP {})'.format(label, status))
            if not raw:
                return None
            try:
                return json.loads(raw.decode('utf-8'))
            except ValueError:
                raise StoreError('Kit request failed ({}: unreadable answer)'.format(label))

    @staticmethod
    def _pause(attempt, retry_after):
        """How long to wait before the next try: Kit's `Retry-After` when it gave a number, else a short growing pause."""
        try:
            asked = float(retry_after)
        except (TypeError, ValueError):
            asked = None
        pause = asked if asked is not None else RETRY_PAUSES[min(attempt, len(RETRY_PAUSES) - 1)] * (attempt + 1)
        return max(0.0, min(pause, MAX_RETRY_WAIT_SECONDS))

    def _pages(self, label, path):
        """Every page of a cursor-paginated listing. A listing that cannot be read to its end is an error, never a
        shorter list."""
        cursor = None
        for _ in range(MAX_PAGES):
            joiner = '&' if '?' in path else '?'
            url = '{}{}per_page={}'.format(path, joiner, PAGE_SIZE)
            if cursor:
                url += '&after=' + urllib.parse.quote(cursor)
            page = self._call(label, 'GET', url)
            if not isinstance(page, dict):
                raise StoreError('Kit request failed ({}: unreadable answer)'.format(label))
            for item in page.get('subscribers') or page.get('tags') or []:
                yield item
            pagination = page.get('pagination') or {}
            cursor = pagination.get('end_cursor')
            if not pagination.get('has_next_page') or not cursor:
                return
        raise StoreError('Kit request failed ({}: more pages than expected)'.format(label))

    @staticmethod
    def _parse(item):
        fields = item.get('fields') if isinstance(item.get('fields'), dict) else {}
        values = {role: fields.get(key) for role, key in FIELD_KEYS.items()}
        address = item.get('email_address')
        scrubbed = (not isinstance(address, str) or '@' not in address) and all(value is None for value in values.values())
        return Subscriber(str(item.get('id')), normalize_state(item.get('state')), item.get('created_at'),
                          values['fit'], values['beta'], values['source'], values['entry'], scrubbed)

    def list_subscribers(self):
        return [self._parse(item) for item in self._pages('list subscribers', '/v4/subscribers?status=all')]

    def set_entry(self, subscriber_id, entry):
        self._call('write entry', 'PUT', '/v4/subscribers/{}'.format(subscriber_id), {'fields': {FIELD_KEYS['entry']: entry}})

    def unsubscribe(self, subscriber_id):
        self._call('unsubscribe', 'POST', '/v4/subscribers/{}/unsubscribe'.format(subscriber_id), {})

    def erase(self, subscriber_id):
        """Unsubscribe, replace the address with a placeholder and blank every custom field, then read the record
        back and refuse to call it erased unless the address and the answers are gone."""
        self.unsubscribe(subscriber_id)
        self._call('overwrite record', 'PUT', '/v4/subscribers/{}'.format(subscriber_id), {
            'email_address': placeholder_for(subscriber_id), 'first_name': None,
            'fields': {key: None for key in FIELD_KEYS.values()}})
        record = self._call('read back', 'GET', '/v4/subscribers/{}'.format(subscriber_id))
        item = (record or {}).get('subscriber') if isinstance(record, dict) else None
        if not isinstance(item, dict) or not self._parse(item).scrubbed or normalize_state(item.get('state')) != CANCELLED:
            raise StoreError('Kit record was not erased (read back)')

    def find_id_by_email(self, address):
        """The id of the one subscriber whose address is exactly `address` (ignoring case), or None."""
        wanted = address.strip().lower()
        query = '/v4/subscribers?status=all&email_address=' + urllib.parse.quote(address.strip())
        found = [item for item in self._pages('find by address', query)
                 if isinstance(item.get('email_address'), str) and item['email_address'].strip().lower() == wanted]
        if len(found) > 1:
            raise StoreError('more than one Kit record matches that address')
        return str(found[0]['id']) if found else None

    def email_of(self, subscriber_id):
        record = self._call('read subscriber', 'GET', '/v4/subscribers/{}'.format(subscriber_id))
        item = (record or {}).get('subscriber') if isinstance(record, dict) else None
        address = item.get('email_address') if isinstance(item, dict) else None
        if not isinstance(address, str) or '@' not in address:
            raise StoreError('that sign-up holds no address')
        return address

    def state_of(self, subscriber_id):
        record = self._call('read subscriber', 'GET', '/v4/subscribers/{}'.format(subscriber_id))
        item = (record or {}).get('subscriber') if isinstance(record, dict) else None
        return normalize_state(item.get('state') if isinstance(item, dict) else None)

    def ensure_tag(self, label):
        tag = self._call('create tag', 'POST', '/v4/tags', {'name': label}).get('tag')
        if not isinstance(tag, dict) or 'id' not in tag:
            raise StoreError('Kit request failed (create tag: unreadable answer)')
        return str(tag['id'])

    def tag_subscribers(self, label, subscriber_ids):
        tag_id = self.ensure_tag(label)
        for subscriber_id in subscriber_ids:
            self._call('tag subscriber', 'POST', '/v4/tags/{}/subscribers/{}'.format(tag_id, subscriber_id), {})

    def tag_members(self, label):
        """The ids tagged `label` (Kit's listing trails a write by up to a couple of minutes)."""
        tag_id = self.ensure_tag(label)
        return sorted(str(item['id']) for item in self._pages('list tag members', '/v4/tags/{}/subscribers?status=all'.format(tag_id)))


class SyntheticStore(object):
    """A store held in a JSON file, for tests: `{"subscribers": [{"id", "email", "state", "created_at", "fields"}]}`.
    It behaves as the Kit store does, including what `erase` leaves behind, and is rewritten after every change so
    one process can leave work for the next. The file holds addresses, so it lives in a temporary directory a test
    makes and is never committed."""

    def __init__(self, path):
        self.path = Path(str(path))

    def _load(self):
        try:
            return json.loads(self.path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            raise StoreError('the synthetic store could not be read')

    def _save(self, data):
        write_private_atomic(self.path, json.dumps(data, indent=2, sort_keys=True).encode('utf-8'))

    @staticmethod
    def _fields(record):
        fields = record.get('fields') or {}
        return {role: fields.get(key) for role, key in FIELD_KEYS.items()}

    def _subscriber(self, record):
        values = self._fields(record)
        address = record.get('email')
        scrubbed = (not isinstance(address, str) or '@' not in address) and all(value is None for value in values.values())
        return Subscriber(str(record['id']), record.get('state', ''), record.get('created_at'),
                          values['fit'], values['beta'], values['source'], values['entry'], scrubbed)

    def _record(self, data, subscriber_id):
        for record in data['subscribers']:
            if str(record['id']) == str(subscriber_id):
                return record
        raise StoreError('no such subscriber')

    def list_subscribers(self):
        return [self._subscriber(record) for record in self._load()['subscribers']]

    def set_entry(self, subscriber_id, entry):
        data = self._load()
        record = self._record(data, subscriber_id)
        record.setdefault('fields', {})[FIELD_KEYS['entry']] = entry
        self._save(data)

    def unsubscribe(self, subscriber_id):
        data = self._load()
        self._record(data, subscriber_id)['state'] = CANCELLED
        self._save(data)

    def erase(self, subscriber_id):
        data = self._load()
        record = self._record(data, subscriber_id)
        record['state'] = CANCELLED
        record['email'] = placeholder_for(subscriber_id)
        record['fields'] = {key: None for key in FIELD_KEYS.values()}
        self._save(data)

    def find_id_by_email(self, address):
        wanted = address.strip().lower()
        found = [str(record['id']) for record in self._load()['subscribers']
                 if isinstance(record.get('email'), str) and record['email'].strip().lower() == wanted]
        if len(found) > 1:
            raise StoreError('more than one record matches that address')
        return found[0] if found else None

    def email_of(self, subscriber_id):
        address = self._record(self._load(), subscriber_id).get('email')
        if not isinstance(address, str) or '@' not in address:
            raise StoreError('that sign-up holds no address')
        return address

    def state_of(self, subscriber_id):
        return self._record(self._load(), subscriber_id).get('state', '')

    def tag_subscribers(self, label, subscriber_ids):
        data = self._load()
        for subscriber_id in subscriber_ids:
            tags = self._record(data, subscriber_id).setdefault('tags', [])
            if label not in tags:
                tags.append(label)
        self._save(data)

    def tag_members(self, label):
        return sorted(str(record['id']) for record in self._load()['subscribers'] if label in (record.get('tags') or []))


class RestrictedStore(object):
    """A store that sees only the subscribers whose ids were named. It is how a sweep or the producer is pointed at
    a shared test account without touching a subscriber the test did not create: a listing leaves the others out
    and every write to one is refused."""

    def __init__(self, store, ids):
        self._store = store
        self._ids = set(str(item) for item in ids)

    def _allow(self, subscriber_id):
        if str(subscriber_id) not in self._ids:
            raise StoreError('that subscriber is outside the named set')

    def list_subscribers(self):
        return [item for item in self._store.list_subscribers() if item.id in self._ids]

    def set_entry(self, subscriber_id, entry):
        self._allow(subscriber_id)
        self._store.set_entry(subscriber_id, entry)

    def unsubscribe(self, subscriber_id):
        self._allow(subscriber_id)
        self._store.unsubscribe(subscriber_id)

    def erase(self, subscriber_id):
        self._allow(subscriber_id)
        self._store.erase(subscriber_id)

    def find_id_by_email(self, address):
        found = self._store.find_id_by_email(address)
        return found if found in self._ids else None

    def email_of(self, subscriber_id):
        self._allow(subscriber_id)
        return self._store.email_of(subscriber_id)

    def state_of(self, subscriber_id):
        self._allow(subscriber_id)
        return self._store.state_of(subscriber_id)

    def tag_subscribers(self, label, subscriber_ids):
        for subscriber_id in subscriber_ids:
            self._allow(subscriber_id)
        self._store.tag_subscribers(label, subscriber_ids)

    def tag_members(self, label):
        return [item for item in self._store.tag_members(label) if item in self._ids]
