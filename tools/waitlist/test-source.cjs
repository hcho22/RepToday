#!/usr/bin/env node
'use strict';
// Tests for the landing pages' Source logic (US-WL04): which path names a tag, and how a
// tab keeps the tag it last arrived by; and for the page view event (US-WL05): where it goes,
// what it carries, and that a failing send never throws. It loads gtm/03-site/waitlist.js into a bare `vm`
// context (no browser, no network, no storage but the fakes below) and calls the two pure
// functions the script exposes on window.RepTodayWaitlist.
//
//   node tools/waitlist/test-source.cjs

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const repo = path.resolve(__dirname, '..', '..');
const source = fs.readFileSync(path.join(repo, 'gtm', '03-site', 'waitlist.js'), 'utf8');
const contract = JSON.parse(fs.readFileSync(path.join(__dirname, 'contract.json'), 'utf8'));

function memoryStorage(initial) {
  const values = Object.assign({}, initial);
  return {
    values,
    getItem: (key) => (key in values ? values[key] : null),
    setItem: (key, value) => { values[key] = String(value); },
  };
}

function load(pathname, storage, options = {}) {
  const writes = [];
  const sent = [];
  const fetchStub = options.fetch || ((url, init) => { sent.push({ url, init }); return Promise.resolve({}); });
  const document = new Proxy({ querySelectorAll: () => [] }, {
    set(target, key, value) { writes.push(key); target[key] = value; return true; },
  });
  const window = { location: { pathname, hostname: options.hostname || 'reptoday.test' }, sessionStorage: storage };
  vm.runInNewContext(source, { window, document, console, URLSearchParams, URL, fetch: fetchStub });
  return { api: window.RepTodayWaitlist, writes, sent };
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

test('a query string or utm_* value never reaches the tag (only the pathname is read)', () => {
  // The script is handed location.pathname, which has no query; the page's own call site is checked below.
  assert.ok(/resolveVisit\(window\.location\.pathname,/.test(source));
  assert.ok(!/location\.(search|href|hash)|document\.referrer|utm_/.test(source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '')));
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

test('the tag lives only in sessionStorage: no cookie is written and one key is used', () => {
  const storage = memoryStorage();
  const loaded = load('/tiktok', storage);
  assert.deepStrictEqual(loaded.writes, []);
  assert.deepStrictEqual(Object.keys(storage.values), ['reptoday.source']);
  assert.ok(!/document\.cookie|localStorage|indexedDB/.test(source));
});

const PRODUCTION_EVENTS = 'https://sensible-spider-810.convex.site/webEvent';

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
  const init = load('/tiktok', memoryStorage(), { hostname: 'reptoday.app' }).sent[0].init;
  assert.strictEqual(init.method, 'POST');
  assert.strictEqual(init.mode, 'no-cors');
  assert.strictEqual(init.credentials, 'omit');
  assert.strictEqual(init.keepalive, true);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(init.headers)), { 'Content-Type': 'text/plain' });
  assert.deepStrictEqual(Object.keys(JSON.parse(init.body)).sort(), ['name', 'props']);
  assert.ok(!/Secret|X-RepToday|document\.cookie/.test(source));
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
  await new Promise((resolve) => setImmediate(resolve));
  assert.strictEqual(calls, 1);
  assert.doesNotThrow(() => load('/', memoryStorage(), { hostname: 'reptoday.app', fetch: () => { throw new Error('sync'); } }));
  assert.doesNotThrow(() => load('/', memoryStorage(), { hostname: 'reptoday.app', fetch: () => new Promise(() => {}) }));
  assert.doesNotThrow(() => load('/', memoryStorage(), { hostname: 'reptoday.app', fetch: 'not a function' }));
});

test('the script holds no secret header, no entry identifier and no address in an event', () => {
  const code = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  const trackBody = code.slice(code.indexOf('function track'), code.indexOf('window.RepTodayWaitlist ='));
  assert.ok(!/email|entry|installId|Secret/i.test(trackBody));
});

let failed = 0;
(async () => {
  for (const [name, body] of tests) {
    try { await body(); console.log('ok   ' + name); } catch (error) { failed += 1; console.log('FAIL ' + name + '\n     ' + error.message.split('\n')[0]); }
  }
  console.log(failed ? failed + ' of ' + tests.length + ' failed' : tests.length + ' tests passed');
  process.exit(failed ? 1 : 0);
})();
