#!/usr/bin/env node
'use strict';
// Tests for the landing pages' Source logic (US-WL04): which path names a tag, and how a
// tab keeps the tag it last arrived by. It loads gtm/03-site/waitlist.js into a bare `vm`
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

function load(pathname, storage) {
  const writes = [];
  const document = new Proxy({ querySelectorAll: () => [] }, {
    set(target, key, value) { writes.push(key); target[key] = value; return true; },
  });
  const window = { location: { pathname, hostname: 'reptoday.test' }, sessionStorage: storage };
  vm.runInNewContext(source, { window, document, console, URLSearchParams, URL });
  return { api: window.RepTodayWaitlist, writes };
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

let failed = 0;
for (const [name, body] of tests) {
  try { body(); console.log('ok   ' + name); } catch (error) { failed += 1; console.log('FAIL ' + name + '\n     ' + error.message.split('\n')[0]); }
}
console.log(failed ? failed + ' of ' + tests.length + ' failed' : tests.length + ' tests passed');
process.exit(failed ? 1 : 0);
