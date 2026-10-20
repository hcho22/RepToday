#!/usr/bin/env node
'use strict';
// Tests for the landing pages' script, gtm/03-site/waitlist.js: which path names a tag and how a
// tab keeps the tag it last arrived by (US-WL04); the sign-up post, Kit's answers and its guard
// (US-WL02); and the two web events (US-WL05). Each test runs the real script in a bare `vm`
// context against small fakes of the page (no browser, no network): a fake form it drives
// through submit, a fetch that records every request, storage and cookie stubs that record every
// write, and timers that only run when a test says so. Addresses are assembled from parts at run
// time, so no address-shaped string is committed.
//
//   node tools/waitlist/test-source.cjs

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const repo = path.resolve(__dirname, '..', '..');
const source = fs.readFileSync(path.join(repo, 'gtm', '03-site', 'waitlist.js'), 'utf8');
const contract = JSON.parse(fs.readFileSync(path.join(__dirname, 'contract.json'), 'utf8'));

const PRODUCTION_EVENTS = 'https://sensible-spider-810.convex.site/webEvent';
const KIT_SIGNUP = 'https://app.kit.com/forms/9786563/subscriptions';
const KIT_GUARD = 'https://app.kit.com/forms/guards/abc';
const ADDRESS = 'visitor' + '@' + 'example.test';
const FIT_TAGS = contract.fit_answers.map((answer) => answer.tag);

function memoryStorage(initial) {
  const values = Object.assign({}, initial);
  return {
    values,
    getItem: (key) => (key in values ? values[key] : null),
    setItem: (key, value) => { values[key] = String(value); },
  };
}

function element(props) {
  const attributes = {};
  const listeners = {};
  return Object.assign({
    hidden: false, textContent: '', value: '', checked: false, disabled: false, attributes,
    setAttribute(key, value) { attributes[key] = String(value); },
    getAttribute(key) { return key in attributes ? attributes[key] : null; },
    removeAttribute(key) { delete attributes[key]; },
    addEventListener(type, listener) { (listeners[type] = listeners[type] || []).push(listener); },
    dispatch(type, event) { for (const listener of listeners[type] || []) { listener(event); } },
  }, props);
}

// The markup one placement carries, as far as the script reads it.
function fakeForm(page) {
  const email = element({ validity: { valid: true }, focus() { page.focused = 'email'; } });
  const radios = FIT_TAGS.map((tag, i) => element({ value: tag, focus() { page.focused = 'fit' + i; } }));
  const fields = element();
  const status = element({ focus() { page.focused = 'status'; } });
  const guard = element({ hidden: true, children: [], appendChild(child) { this.children.push(child); child.parent = this; } });
  const parts = {
    email, radios, fields, status, guard,
    emailError: element({ hidden: true }),
    fitError: element({ hidden: true }),
    beta: element(),
    source: element(),
    button: element({ textContent: 'Join the waitlist' }),
  };
  const selectors = {
    'input[type="email"]': parts.email,
    '[data-wl-error="email"]': parts.emailError,
    '[data-wl-error="fit"]': parts.fitError,
    'input[type="checkbox"]': parts.beta,
    'input[type="hidden"]': parts.source,
    'button[type="submit"]': parts.button,
    '[data-wl-status]': parts.status,
    '[data-wl-guard]': parts.guard,
  };
  const form = element({
    hidden: true,
    parts,
    querySelector: (selector) => selectors[selector] || null,
    querySelectorAll: (selector) => (selector === 'input[type="radio"]' ? radios : selector === '[data-wl-fields]' ? [fields] : []),
    reset() { email.value = ''; parts.beta.checked = false; for (const radio of radios) { radio.checked = false; } },
  });
  return form;
}

// Loads the script once, as a page would. `options` sets the host, the location's other parts,
// the referrer, the fetch, and whether the page carries a form.
function load(pathname, storage, options = {}) {
  const writes = [];
  const sent = [];
  const page = { focused: null };
  const timers = new Map();
  let nextTimer = 1;
  const windowListeners = {};
  const fetchStub = options.fetch || ((url, init) => {
    sent.push({ url, init });
    return Promise.resolve(options.answer ? options.answer(url, init) : {});
  });
  const forms = options.form ? [fakeForm(page)] : [];
  const document = new Proxy({
    referrer: options.referrer || '',
    querySelectorAll: (selector) => (selector === 'form[data-waitlist-form]' ? forms : []),
    createElement: (tag) => element({ tag, style: {}, remove() { this.parent.children.splice(this.parent.children.indexOf(this), 1); } }),
  }, {
    set(target, key, value) { writes.push(String(key)); target[key] = value; return true; },
  });
  const localStorage = { setItem(key) { writes.push('localStorage:' + key); }, getItem: () => null };
  const location = Object.assign({ pathname, hostname: options.hostname || 'reptoday.test', search: '', hash: '', href: '' }, options.location);
  const window = {
    location,
    sessionStorage: storage,
    localStorage,
    addEventListener(type, listener) { (windowListeners[type] = windowListeners[type] || []).push(listener); },
    removeEventListener(type, listener) { windowListeners[type] = (windowListeners[type] || []).filter((other) => other !== listener); },
    setTimeout(callback, ms) { const id = nextTimer++; timers.set(id, { callback, ms }); return id; },
    clearTimeout(id) { timers.delete(id); },
  };
  vm.runInNewContext(source, { window, document, console, URLSearchParams, URL, AbortController, fetch: fetchStub });
  return {
    api: window.RepTodayWaitlist,
    writes,
    sent,
    page,
    form: forms[0],
    timers,
    post(message) { for (const listener of windowListeners.message || []) { listener(message); } },
    show(event) { for (const listener of windowListeners.pageshow || []) { listener(event); } },
    elapse() { for (const [id, timer] of Array.from(timers)) { timers.delete(id); timer.callback(); } },
    submit() { forms[0].dispatch('submit', { preventDefault() {} }); },
  };
}

const settle = () => new Promise((resolve) => setImmediate(resolve));
const signups = (loaded) => loaded.sent.filter((request) => request.url === KIT_SIGNUP);
const events = (loaded) => loaded.sent.filter((request) => request.url === PRODUCTION_EVENTS).map((request) => JSON.parse(request.init.body));
const answer = (status, body) => ({ ok: status >= 200 && status < 300, status, json: () => Promise.resolve(body) });

function fillIn(loaded, fit = FIT_TAGS[1]) {
  const { email, radios } = loaded.form.parts;
  email.value = ADDRESS;
  radios[FIT_TAGS.indexOf(fit)].checked = true;
}

const tests = [];
function test(name, body) { tests.push([name, body]); }

const bare = load('/', memoryStorage()).api;

test('the script keeps exactly the contract file\'s four tags, in order', () => {
  assert.deepStrictEqual(Array.from(bare.sourceTags), contract.source_tags);
});

test('the four links name their tag in any letter case, with or without a trailing slash', () => {
  const cases = { '/tiktok': 'tiktok', '/TikTok': 'tiktok', '/YOUTUBE': 'youtube', '/rEdDiT': 'reddit', '/Network': 'network', '/network/': 'network', '/TIKTOK/': 'tiktok' };
  for (const [pathname, tag] of Object.entries(cases)) { assert.strictEqual(bare.tagForPath(pathname), tag, pathname); }
});

test('nothing else names a tag', () => {
  const none = ['/', '', '/index-b', '/privacy', '/tiktk', '/tiktok/x', '/x/tiktok', '/tiktok.html', '//tiktok', '/%74iktok', '/tiktok%2F', '/tiktok-', '/fifth', '/unknown', '/none', '/TikTok ', '/tiktok;a=b'];
  for (const pathname of none) { assert.strictEqual(bare.tagForPath(pathname), null, JSON.stringify(pathname)); }
});

test('a query string, utm_* value, hash or referrer never sets the tag: only the path counts', () => {
  const misleading = {
    location: { search: '?utm_source=tiktok&source=reddit', hash: '#youtube', href: 'https://reptoday.app/?utm_source=tiktok#youtube' },
    referrer: 'https://www.tiktok.com/',
    hostname: 'reptoday.app',
    form: true,
  };
  const storage = memoryStorage();
  const plain = load('/', storage, misleading);
  assert.deepStrictEqual(events(plain), [{ name: 'landing_page_view', props: { referrer_source: 'none' } }]);
  assert.strictEqual(plain.form.parts.source.value, 'unknown');
  assert.deepStrictEqual(storage.values, {});
  const linked = load('/network', memoryStorage(), misleading);
  assert.deepStrictEqual(events(linked), [{ name: 'landing_page_view', props: { referrer_source: 'network' } }]);
  assert.strictEqual(linked.form.parts.source.value, 'network');
});

test('arriving by a link keeps its tag for the tab', () => {
  const storage = memoryStorage();
  assert.strictEqual(load('/tiktok', storage).api.resolveVisit('/tiktok', storage), 'tiktok');
  assert.deepStrictEqual(storage.values, { 'reptoday.source': 'tiktok' });
});

test('looking around the site leaves the tag in place', () => {
  const storage = memoryStorage({ 'reptoday.source': 'tiktok' });
  for (const pathname of ['/', '/index-b', '/privacy', '/tiktk', '/anything']) {
    assert.strictEqual(bare.resolveVisit(pathname, storage), 'tiktok', pathname);
  }
  assert.deepStrictEqual(storage.values, { 'reptoday.source': 'tiktok' });
});

test('last touch: a later link replaces the earlier one', () => {
  const storage = memoryStorage();
  assert.strictEqual(bare.resolveVisit('/tiktok', storage), 'tiktok');
  assert.strictEqual(bare.resolveVisit('/', storage), 'tiktok');
  assert.strictEqual(bare.resolveVisit('/YouTube/', storage), 'youtube');
  assert.strictEqual(bare.resolveVisit('/index-b', storage), 'youtube');
});

test('a visit that never arrived by a link has no tag', () => {
  assert.strictEqual(bare.resolveVisit('/', memoryStorage()), null);
});

test('a stored value that is not one of the four tags is never used', () => {
  for (const poisoned of ['unknown', 'none', 'evil', 'TikTok', ' tiktok', '', 'tiktok,reddit']) {
    assert.strictEqual(bare.resolveVisit('/', memoryStorage({ 'reptoday.source': poisoned })), null, JSON.stringify(poisoned));
  }
});

test('unavailable storage costs only the memory across pages, never an error', () => {
  const broken = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } };
  assert.strictEqual(bare.resolveVisit('/reddit', broken), 'reddit');
  assert.strictEqual(bare.resolveVisit('/', broken), null);
  assert.doesNotThrow(() => load('/reddit', broken));
  const blockedWindow = { location: { pathname: '/network', hostname: 'reptoday.test' }, get sessionStorage() { throw new Error('blocked'); } };
  vm.runInNewContext(source, { window: blockedWindow, document: { querySelectorAll: () => [] }, console, URLSearchParams, URL });
});

test('the tag lives only in sessionStorage: no cookie or localStorage write, one key, through a whole sign-up', async () => {
  const storage = memoryStorage();
  const loaded = load('/tiktok', storage, { hostname: 'reptoday.app', form: true, answer: (url) => (url === KIT_SIGNUP ? answer(200, { status: 'success' }) : {}) });
  fillIn(loaded);
  loaded.submit();
  await settle();
  assert.strictEqual(loaded.form.getAttribute('data-wl-state'), 'done');
  assert.deepStrictEqual(loaded.writes, []);
  assert.deepStrictEqual(Object.keys(storage.values), ['reptoday.source']);
});

test('a page restored from the back/forward cache takes the tab\'s latest tag for its sign-up and its event', async () => {
  const storage = memoryStorage({ 'reptoday.source': 'tiktok' });
  const loaded = load('/', storage, { hostname: 'reptoday.app', form: true, answer: (url) => (url === KIT_SIGNUP ? answer(200, { status: 'success' }) : {}) });
  assert.strictEqual(loaded.form.parts.source.value, 'tiktok');
  storage.values['reptoday.source'] = 'youtube';
  loaded.show({ persisted: false });
  assert.strictEqual(loaded.form.parts.source.value, 'tiktok');
  loaded.show({ persisted: true });
  assert.strictEqual(loaded.form.parts.source.value, 'youtube');
  fillIn(loaded);
  loaded.submit();
  await settle();
  assert.strictEqual(Array.from(signups(loaded)[0].init.body.entries()).find(([key]) => key === contract.posted_fields.source)[1], 'youtube');
  assert.deepStrictEqual(events(loaded).map((event) => event.props.referrer_source), ['tiktok', 'youtube']);
});

test('a sign-up posts exactly the contract\'s four fields to Kit, with no credential and no entry identifier', async () => {
  const loaded = load('/', memoryStorage(), { hostname: 'reptoday.app', form: true, answer: () => answer(200, { status: 'success' }) });
  fillIn(loaded, FIT_TAGS[1]);
  loaded.submit();
  await settle();
  const [request] = signups(loaded);
  assert.strictEqual(signups(loaded).length, 1);
  assert.strictEqual(request.init.method, 'POST');
  assert.strictEqual(request.init.credentials, 'omit');
  assert.deepStrictEqual(JSON.parse(JSON.stringify(request.init.headers)), { Accept: 'application/json' });
  const fields = contract.posted_fields;
  assert.deepStrictEqual(Array.from(request.init.body.entries()), [
    [fields.email, ADDRESS], [fields.fit, FIT_TAGS[1]], [fields.beta_opt_in, 'false'], [fields.source, 'unknown'],
  ]);
});

test('a local page posts its sign-up to the stub, never to Kit', async () => {
  const loaded = load('/', memoryStorage(), { hostname: 'localhost', form: true, answer: () => answer(200, { status: 'success' }) });
  fillIn(loaded);
  loaded.submit();
  await settle();
  assert.deepStrictEqual(loaded.sent.map((request) => request.url), ['http://127.0.0.1:8799/signup']);
});

test('a successful sign-up sends one waitlist_signup carrying only the tag: no address, entry or identifier', async () => {
  const loaded = load('/YouTube', memoryStorage(), { hostname: 'reptoday.app', form: true, answer: (url) => (url === KIT_SIGNUP ? answer(200, { status: 'success' }) : {}) });
  fillIn(loaded);
  loaded.submit();
  await settle();
  assert.deepStrictEqual(events(loaded), [
    { name: 'landing_page_view', props: { referrer_source: 'youtube' } },
    { name: 'waitlist_signup', props: { referrer_source: 'youtube' } },
  ]);
  const eventRequests = loaded.sent.filter((request) => request.url === PRODUCTION_EVENTS);
  for (const request of eventRequests) {
    assert.ok(!request.init.body.includes(ADDRESS));
    assert.deepStrictEqual(JSON.parse(JSON.stringify(request.init.headers)), { 'Content-Type': 'text/plain' });
  }
  assert.strictEqual(loaded.form.parts.status.textContent, 'Check your email to confirm your address.');
});

test('Kit refusing the address shows the email message, whatever the status, and allows a retry', async () => {
  for (const [status, body] of [[422, { errors: ['email_address contains an invalid email address'] }], [400, { errors: { email_address: ['is invalid'] } }], [200, { errors: ['invalid'] }]]) {
    const loaded = load('/', memoryStorage(), { hostname: 'reptoday.app', form: true, answer: (url) => (url === KIT_SIGNUP ? answer(status, body) : {}) });
    fillIn(loaded);
    loaded.submit();
    await settle();
    const { email, emailError, status: line, button } = loaded.form.parts;
    assert.strictEqual(emailError.hidden, false, String(status));
    assert.strictEqual(emailError.textContent, 'Add a valid email address.');
    assert.strictEqual(email.getAttribute('aria-invalid'), 'true');
    assert.strictEqual(email.value, ADDRESS);
    assert.strictEqual(loaded.page.focused, 'email');
    assert.strictEqual(line.textContent, '');
    assert.strictEqual(button.disabled, false);
    assert.strictEqual(events(loaded).filter((event) => event.name === 'waitlist_signup').length, 0);
    loaded.submit();
    await settle();
    assert.strictEqual(signups(loaded).length, 2);
  }
});

test('any other failure shows the failure wording, keeps the entries and allows a retry', async () => {
  const failures = [
    () => Promise.resolve(answer(500, {})),
    () => Promise.resolve({ ok: false, status: 502, json: () => Promise.reject(new Error('not json')) }),
    () => Promise.resolve(answer(200, { status: 'something else' })),
    () => Promise.resolve(answer(200, { status: 'quarantined', url: 'https://evil.example/forms/guards/x' })),
    () => Promise.reject(new Error('offline')),
  ];
  for (const failure of failures) {
    const sent = [];
    const loaded = load('/', memoryStorage(), { hostname: 'reptoday.app', form: true, fetch: (url, init) => { sent.push(url); return url === KIT_SIGNUP ? failure() : Promise.resolve({}); } });
    fillIn(loaded);
    loaded.form.parts.beta.checked = true;
    loaded.submit();
    await settle();
    const { status, button, email, beta, guard } = loaded.form.parts;
    assert.strictEqual(status.textContent, 'That did not go through. Try again in a moment.');
    assert.strictEqual(button.disabled, false);
    assert.strictEqual(email.value, ADDRESS);
    assert.strictEqual(beta.checked, true);
    assert.strictEqual(guard.children.length, 0);
    loaded.submit();
    await settle();
    assert.strictEqual(sent.filter((url) => url === KIT_SIGNUP).length, 2);
  }
});

test('Kit\'s check shows in its iframe, and its confirmation, from Kit\'s origin only, completes the sign-up', async () => {
  const loaded = load('/reddit', memoryStorage(), { hostname: 'reptoday.app', form: true, answer: (url) => (url === KIT_SIGNUP ? answer(200, { status: 'quarantined', url: KIT_GUARD }) : {}) });
  fillIn(loaded);
  loaded.submit();
  await settle();
  const { guard, button } = loaded.form.parts;
  assert.strictEqual(guard.hidden, false);
  assert.strictEqual(guard.children.length, 1);
  assert.strictEqual(guard.children[0].src, KIT_GUARD);
  assert.strictEqual(button.disabled, true);
  loaded.post({ origin: 'https://evil.example', data: { name: 'ckjs:guard:confirmed' } });
  assert.notStrictEqual(loaded.form.getAttribute('data-wl-state'), 'done');
  loaded.post({ origin: 'https://app.kit.com', data: { name: 'ckjs:guard:confirmed' } });
  assert.strictEqual(loaded.form.getAttribute('data-wl-state'), 'done');
  assert.strictEqual(guard.hidden, true);
  assert.strictEqual(guard.children.length, 0);
  assert.strictEqual(loaded.timers.size, 0);
  assert.deepStrictEqual(events(loaded).map((event) => event.name), ['landing_page_view', 'waitlist_signup']);
});

test('a check that is never confirmed gives the form back after a bounded wait, with the failure wording and a retry', async () => {
  const loaded = load('/', memoryStorage(), { hostname: 'reptoday.app', form: true, answer: (url) => (url === KIT_SIGNUP ? answer(200, { status: 'quarantined', url: KIT_GUARD }) : {}) });
  fillIn(loaded);
  loaded.submit();
  await settle();
  const { guard, button, status, email } = loaded.form.parts;
  assert.strictEqual(button.disabled, true);
  loaded.submit();
  assert.strictEqual(signups(loaded).length, 1);
  const waits = Array.from(loaded.timers.values()).map((timer) => timer.ms);
  assert.strictEqual(waits.length, 1);
  assert.ok(waits[0] > 0 && waits[0] <= 300000, String(waits[0]));
  loaded.elapse();
  assert.strictEqual(guard.hidden, true);
  assert.strictEqual(guard.children.length, 0);
  assert.strictEqual(button.disabled, false);
  assert.strictEqual(button.textContent, 'Join the waitlist');
  assert.strictEqual(loaded.form.getAttribute('aria-busy'), 'false');
  assert.strictEqual(status.textContent, 'That did not go through. Try again in a moment.');
  assert.strictEqual(email.value, ADDRESS);
  loaded.post({ origin: 'https://app.kit.com', data: { name: 'ckjs:guard:confirmed' } });
  assert.notStrictEqual(loaded.form.getAttribute('data-wl-state'), 'done');
  loaded.submit();
  await settle();
  assert.strictEqual(signups(loaded).length, 2);
  assert.strictEqual(guard.children.length, 1);
});

test('a landing page load sends exactly one landing_page_view carrying only the visit\'s tag or none', () => {
  const none = load('/', memoryStorage(), { hostname: 'reptoday.app' });
  assert.strictEqual(none.sent.length, 1);
  assert.strictEqual(none.sent[0].url, PRODUCTION_EVENTS);
  assert.deepStrictEqual(JSON.parse(none.sent[0].init.body), { name: 'landing_page_view', props: { referrer_source: 'none' } });
  for (const [pathname, tag] of [['/TikTok', 'tiktok'], ['/youtube/', 'youtube'], ['/reddit', 'reddit'], ['/NETWORK', 'network']]) {
    const sent = load(pathname, memoryStorage(), { hostname: 'www.reptoday.app' }).sent;
    assert.deepStrictEqual(JSON.parse(sent[0].init.body), { name: 'landing_page_view', props: { referrer_source: tag } }, pathname);
  }
});

test('a kept tag is what later page views carry, and a page never sends unknown', () => {
  const storage = memoryStorage({ 'reptoday.source': 'youtube' });
  const sent = load('/index-b', storage, { hostname: 'reptoday.app' }).sent;
  assert.strictEqual(JSON.parse(sent[0].init.body).props.referrer_source, 'youtube');
  for (const poisoned of ['unknown', 'evil']) {
    const body = JSON.parse(load('/', memoryStorage({ 'reptoday.source': poisoned }), { hostname: 'reptoday.app' }).sent[0].init.body);
    assert.strictEqual(body.props.referrer_source, 'none');
  }
});

test('the event is a simple, anonymous, no-cors POST with no cookie, secret, header or identifier', () => {
  const loaded = load('/tiktok', memoryStorage(), { hostname: 'reptoday.app' });
  const init = loaded.sent[0].init;
  assert.strictEqual(init.method, 'POST');
  assert.strictEqual(init.mode, 'no-cors');
  assert.strictEqual(init.credentials, 'omit');
  assert.strictEqual(init.keepalive, true);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(init.headers)), { 'Content-Type': 'text/plain' });
  assert.deepStrictEqual(Object.keys(JSON.parse(init.body)).sort(), ['name', 'props']);
  assert.deepStrictEqual(loaded.writes, []);
});

test('no event leaves localhost, a preview or any other host, unless a local test names a stub', () => {
  for (const hostname of ['localhost', '127.0.0.1', '[::1]', 'reptoday-site.pages.dev', 'abc123.reptoday-site.pages.dev', 'reptoday.app.evil.test', 'example.com', '']) {
    assert.deepStrictEqual(load('/tiktok', memoryStorage(), { hostname }).sent, [], hostname);
  }
  const stub = JSON.stringify({ eventsUrl: 'http://127.0.0.1:8799/event' });
  const local = load('/', memoryStorage({ 'waitlist.testEndpoints': stub }), { hostname: 'localhost' }).sent;
  assert.strictEqual(local.length, 1);
  assert.strictEqual(local[0].url, 'http://127.0.0.1:8799/event');
  // The override is honored on local hosts only.
  assert.deepStrictEqual(load('/', memoryStorage({ 'waitlist.testEndpoints': stub }), { hostname: 'reptoday-site.pages.dev' }).sent, []);
  const onSite = load('/', memoryStorage({ 'waitlist.testEndpoints': stub }), { hostname: 'reptoday.app' }).sent;
  assert.strictEqual(onSite[0].url, PRODUCTION_EVENTS);
});

test('a failing, slow or throwing send never throws into the page and is not retried', async () => {
  let calls = 0;
  const rejecting = () => { calls += 1; return Promise.reject(new Error('blocked')); };
  assert.doesNotThrow(() => load('/', memoryStorage(), { hostname: 'reptoday.app', fetch: rejecting }));
  await settle();
  assert.strictEqual(calls, 1);
  assert.doesNotThrow(() => load('/', memoryStorage(), { hostname: 'reptoday.app', fetch: () => { throw new Error('sync'); } }));
  assert.doesNotThrow(() => load('/', memoryStorage(), { hostname: 'reptoday.app', fetch: () => new Promise(() => {}) }));
  assert.doesNotThrow(() => load('/', memoryStorage(), { hostname: 'reptoday.app', fetch: 'not a function' }));
});

let failed = 0;
(async () => {
  for (const [name, body] of tests) {
    try { await body(); console.log('ok   ' + name); } catch (error) { failed += 1; console.log('FAIL ' + name + '\n     ' + error.message.split('\n')[0]); }
  }
  console.log(failed ? failed + ' of ' + tests.length + ' failed' : tests.length + ' tests passed');
  process.exit(failed ? 1 : 0);
})();
