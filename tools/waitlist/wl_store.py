"""The Waitlist's store: Kit (US-WL06, OQ1 Option A) and a synthetic stand-in for tests (US-WL07).

Both stores answer the same questions and none ever hands the producer an address: a listing returns a
`Subscriber` that holds only the id, the confirmation state, the creation time and the four stored answers,
because the email is dropped where the response is parsed. The two places an address is read on purpose are
`email_of` (the founder's `show`) and the exact-match `find_id_by_email` (the founder's `remove`).

What Kit's API does and does not do is recorded in `artifacts/reports/US-WL06/spike.md`: it cannot delete a
subscriber, so `erase` unsubscribes, overwrites the address with a placeholder that is not an address, and
blanks the first name and every custom field (decision D2). Kit's web app can delete one, which only the founder
does; `exists` is how the tooling checks afterwards that a deleted id no longer answers. A single-record read
carries Kit's own unsubscribe time (`canceled_at`, null until the subscriber unsubscribes; a list carries it only
for `status=cancelled` with `include=canceled_at`), which `canceled_at` reads; Kit records no time for a spam
complaint. A list trails a fresh
write by up to a couple of minutes, a single-record read does not. A list returns a blank custom field as an empty
string where a single-record read returns null, so a blank value is either.

An error raised here names the step and the HTTP status. It never carries a response body, a URL with an
address in its query, or the credential.
"""
import http.client
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
# A subscriber's own page in Kit's web app, where the founder deletes an erased one. Kit's subscriber list hides
# unsubscribed subscribers by default, and every erased one is unsubscribed, so the page is reached by its id.
KIT_SUBSCRIBER_PAGE = 'https://app.kit.com/subscribers/{}'
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

# Kit's subscriber states. `inactive` is a sign-up that has not confirmed; `cancelled` is an unsubscribed one;
# `complained` is one whose holder marked a Kit email as spam; Kit sends nothing to a `bounced` or `complained` one
# either, so an erased record may be in any of those three.
ACTIVE, INACTIVE, CANCELLED, BOUNCED, COMPLAINED = 'active', 'inactive', 'cancelled', 'bounced', 'complained'
UNMAILED = (CANCELLED, BOUNCED, COMPLAINED)
# The states a removal request puts a sign-up in: an unsubscribe, and a spam complaint, which the captain decided
# (2026-10-20) is a removal request too. A bounce is not one; it stays until the retention date.
REMOVAL_REQUESTED = (CANCELLED, COMPLAINED)
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


def is_blank(value):
    """No value: null, or the empty string a Kit listing returns for a blank custom field."""
    return value is None or (isinstance(value, str) and not value.strip())


def is_scrubbed(address, first_name, fields):
    """Nothing identifying is left: no address, no first name and no value in any custom field."""
    return ((not isinstance(address, str) or '@' not in address) and is_blank(first_name)
            and all(is_blank(value) for value in fields.values()))


def subscriber_in(answer):
    """The subscriber record a single-record answer carries, or None."""
    item = answer.get('subscriber') if isinstance(answer, dict) else None
    return item if isinstance(item, dict) else None


def fields_of(item):
    fields = item.get('fields') if isinstance(item, dict) else None
    return fields if isinstance(fields, dict) else {}


# What `security find-generic-password` answers when the item is not there (errSecItemNotFound), and what it says
# when the Keychain is locked and it may not ask for the password (errSecInteractionNotAllowed: this Mac's login
# Keychain locks on sleep, so a scheduled run that starts on wake, before the founder unlocks, meets it).
SECURITY_ITEM_NOT_FOUND = 44
SECURITY_LOCKED_EXITS = (36, 51, 128)
SECURITY_LOCKED_TEXT = 'user interaction is not allowed'


def read_api_key(service=None):
    """The Kit API key from the macOS Keychain. The value goes into a request header and nowhere else.
    A missing item, a locked Keychain and any other refusal are told apart in the error, which never holds a
    value: a locked Keychain is a run that retries on its own, a missing item is a setup fault."""
    service = service or os.environ.get(KEYCHAIN_SERVICE_ENV) or DEFAULT_KEYCHAIN_SERVICE
    item = '(service {}, account {})'.format(service, KEYCHAIN_ACCOUNT)
    try:
        done = subprocess.run(['security', 'find-generic-password', '-s', service, '-a', KEYCHAIN_ACCOUNT, '-w'],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=NETWORK_TIMEOUT_SECONDS * 3)
    except subprocess.TimeoutExpired:
        # `security` waited on an unlock dialog nobody answered.
        raise StoreError('the Keychain is locked, so the Kit API key {} could not be read; nothing was changed and '
                         'the next run tries again'.format(item))
    except (OSError, subprocess.SubprocessError):
        # No Keychain tool to ask (not macOS, or not on PATH): there is no key here.
        raise StoreError('no Kit API key in the Keychain {}: the security tool is not available'.format(item))
    key = done.stdout.decode('utf-8', 'replace').strip() if done.returncode == 0 else ''
    if key:
        return key
    said = done.stderr.decode('utf-8', 'replace').lower()
    if done.returncode == SECURITY_ITEM_NOT_FOUND:
        raise StoreError('no Kit API key in the Keychain {}'.format(item))
    if done.returncode in SECURITY_LOCKED_EXITS or SECURITY_LOCKED_TEXT in said:
        raise StoreError('the Keychain is locked, so the Kit API key {} could not be read; nothing was changed and '
                         'the next run tries again'.format(item))
    raise StoreError('the Kit API key {} could not be read (security exit {})'.format(item, done.returncode))


def checked_base_url(url):
    """Kit's own origin, or a loopback address a test serves a fake on. Anything else is refused, so a stray
    value can never send the credential somewhere else."""
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
        self._base = checked_base_url(base_url or KIT_BASE_URL)
        self._timeout = timeout

    @classmethod
    def from_keychain(cls, service=None):
        return cls(read_api_key(service))

    # One request. `label` names the step in an error; the path may carry an address, so it is never printed.

    def _call(self, label, method, path, body=None, expect=(200, 201, 204), with_status=False):
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
            except (urllib.error.URLError, OSError, http.client.HTTPException):
                raise StoreError('Kit request failed ({}: no answer)'.format(label))
            allowed = RATE_LIMIT_RETRIES if status == 429 else len(RETRY_PAUSES)
            if status in RETRY_STATUSES and attempt < allowed:
                time.sleep(self._pause(attempt, retry_after))
                attempt += 1
                continue
            if status not in expect:
                raise StoreError('Kit request failed ({}: HTTP {})'.format(label, status))
            payload = None
            if raw:
                try:
                    payload = json.loads(raw.decode('utf-8'))
                except ValueError:
                    raise StoreError('Kit request failed ({}: unreadable answer)'.format(label))
            return (status, payload) if with_status else payload

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
        fields = fields_of(item)
        values = {role: None if is_blank(fields.get(key)) else fields.get(key) for role, key in FIELD_KEYS.items()}
        return Subscriber(str(item.get('id')), normalize_state(item.get('state')), item.get('created_at'),
                          values['fit'], values['beta'], values['source'], values['entry'],
                          is_scrubbed(item.get('email_address'), item.get('first_name'), fields))

    def list_subscribers(self):
        return [self._parse(item) for item in self._pages('list subscribers', '/v4/subscribers?status=all')]

    def set_entry(self, subscriber_id, entry):
        self._call('write entry', 'PUT', '/v4/subscribers/{}'.format(subscriber_id), {'fields': {FIELD_KEYS['entry']: entry}})

    def unsubscribe(self, subscriber_id):
        self._call('unsubscribe', 'POST', '/v4/subscribers/{}/unsubscribe'.format(subscriber_id), {})

    def erase(self, subscriber_id):
        """Unsubscribe, replace the address with a placeholder and blank the first name and every custom field the
        record holds (the four this tooling names and any other the account has), then read the record back and
        refuse to call it erased unless the address, the name and every field are gone and Kit mails it nothing.
        A record Kit already mails nothing (`bounced`, `complained`) may refuse the unsubscribe call; the scrub then
        goes ahead, and the read-back is what decides."""
        path = '/v4/subscribers/{}'.format(subscriber_id)
        try:
            self.unsubscribe(subscriber_id)
        except StoreError:
            item = subscriber_in(self._call('read state', 'GET', path))
            if item is None or normalize_state(item.get('state')) not in UNMAILED:
                raise
        written = self._call('overwrite record', 'PUT', path, {
            'email_address': placeholder_for(subscriber_id), 'first_name': None,
            'fields': {key: None for key in FIELD_KEYS.values()}})
        others = [key for key, value in fields_of(subscriber_in(written)).items() if not is_blank(value)]
        if others:
            self._call('overwrite record', 'PUT', path, {'fields': {key: None for key in others}})
        item = subscriber_in(self._call('read back', 'GET', path))
        if item is None or not self._parse(item).scrubbed or normalize_state(item.get('state')) not in UNMAILED:
            raise StoreError('Kit record was not erased (read back)')

    def exists(self, subscriber_id):
        """Whether Kit still holds a record under this id: True when it answers, False when it answers 404 (the
        founder deleted it in Kit's web app). Any other answer is an error, never a guess."""
        status, _ = self._call('check deleted', 'GET', '/v4/subscribers/{}'.format(subscriber_id), expect=(200, 404),
                               with_status=True)
        return status == 200

    def canceled_at(self, subscriber_id):
        """Kit's own time for the subscriber's unsubscribe (`canceled_at`, an ISO 8601 time), or None when the record
        carries none."""
        item = subscriber_in(self._call('read cancel time', 'GET', '/v4/subscribers/{}'.format(subscriber_id)))
        value = item.get('canceled_at') if item is not None else None
        return value if isinstance(value, str) else None

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
        item = subscriber_in(self._call('read subscriber', 'GET', '/v4/subscribers/{}'.format(subscriber_id)))
        address = item.get('email_address') if item is not None else None
        if not isinstance(address, str) or '@' not in address:
            raise StoreError('that sign-up holds no address')
        return address

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
    """A store held in a JSON file, for tests: `{"subscribers": [{"id", "email", "first_name", "state", "created_at",
    "canceled_at", "fields"}]}`, the first name and the cancel time optional.
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
        return Subscriber(str(record['id']), record.get('state', ''), record.get('created_at'),
                          values['fit'], values['beta'], values['source'], values['entry'],
                          is_scrubbed(record.get('email'), record.get('first_name'), record.get('fields') or {}))

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
        if record.get('state') not in UNMAILED:
            record['state'] = CANCELLED
        record['email'] = placeholder_for(subscriber_id)
        record['first_name'] = None
        record['fields'] = {key: None for key in set(record.get('fields') or {}) | set(FIELD_KEYS.values())}
        self._save(data)

    def exists(self, subscriber_id):
        """Whether the record is still there; a test deletes it from the file as the founder does in Kit's web app."""
        return any(str(record['id']) == str(subscriber_id) for record in self._load()['subscribers'])

    def canceled_at(self, subscriber_id):
        value = self._record(self._load(), subscriber_id).get('canceled_at')
        return value if isinstance(value, str) else None

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

    def tag_subscribers(self, label, subscriber_ids):
        data = self._load()
        for subscriber_id in subscriber_ids:
            tags = self._record(data, subscriber_id).setdefault('tags', [])
            if label not in tags:
                tags.append(label)
        self._save(data)


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

    def exists(self, subscriber_id):
        self._allow(subscriber_id)
        return self._store.exists(subscriber_id)

    def canceled_at(self, subscriber_id):
        self._allow(subscriber_id)
        return self._store.canceled_at(subscriber_id)

    def find_id_by_email(self, address):
        found = self._store.find_id_by_email(address)
        return found if found in self._ids else None

    def email_of(self, subscriber_id):
        self._allow(subscriber_id)
        return self._store.email_of(subscriber_id)

    def tag_subscribers(self, label, subscriber_ids):
        for subscriber_id in subscriber_ids:
            self._allow(subscriber_id)
        self._store.tag_subscribers(label, subscriber_ids)
