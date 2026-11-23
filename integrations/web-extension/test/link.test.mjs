// node --test integrations/web-extension/test/
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  MAX_LINK_CHARS,
  MAX_SELECTION_CHARS,
  MAX_TITLE_CHARS,
  buildSaveLink,
  isSavableUrl,
} from '../link.js';

const params = (link) => new URL(link).searchParams;

test('a page link carries the encoded url and title, and nothing else', () => {
  const { link, truncated } = buildSaveLink({
    url: 'https://example.com/a path/?q=1&r=two#frag',
    title: '  Tom & Jerry:\n  “the”  chase ',
  });
  assert.equal(truncated, false);
  assert.ok(link.startsWith('coreader://save?url=https%3A%2F%2Fexample.com%2Fa%20path%2F%3Fq%3D1%26r%3Dtwo%23frag&title='));
  assert.equal(params(link).get('url'), 'https://example.com/a path/?q=1&r=two#frag');
  assert.equal(params(link).get('title'), 'Tom & Jerry: “the” chase');
  assert.deepEqual([...params(link).keys()], ['url', 'title']);
  // Spaces are %20, never "+", so a decoder that leaves "+" alone still works.
  assert.ok(!link.includes('+'));
});

test('a selection keeps its paragraph breaks', () => {
  const { link, truncated } = buildSaveLink({
    url: 'https://example.com/',
    title: 'T',
    selection: '  first line\r\nsecond & third\n\nnew paragraph  ',
  });
  assert.equal(truncated, false);
  assert.equal(params(link).get('selection'), 'first line\nsecond & third\n\nnew paragraph');
  assert.equal(params(link).get('truncated'), null);
});

test('a long selection is cut to the limit and flagged', () => {
  const { link, truncated } = buildSaveLink({
    url: 'https://example.com/',
    selection: 'a'.repeat(MAX_SELECTION_CHARS + 500),
  });
  assert.equal(truncated, true);
  assert.equal(params(link).get('selection').length, MAX_SELECTION_CHARS);
  assert.equal(params(link).get('truncated'), '1');
});

test('text that grows when encoded still fits the link limit, without broken characters', () => {
  const { link, truncated } = buildSaveLink({
    url: 'https://example.com/',
    title: '読書',
    selection: '読書ノート😀'.repeat(400),
  });
  assert.equal(truncated, true);
  assert.ok(link.length <= MAX_LINK_CHARS, `link is ${link.length} characters`);
  const selection = params(link).get('selection');
  assert.ok(selection.length > 100);
  assert.ok(!selection.includes('�'));
  assert.ok('読書ノート😀'.repeat(400).startsWith(selection));
});

test('titles are bounded and whitespace-only selections are dropped', () => {
  const { link } = buildSaveLink({
    url: 'https://example.com/',
    title: 'x'.repeat(MAX_TITLE_CHARS * 2),
    selection: ' \n\t ',
  });
  assert.equal(params(link).get('title').length, MAX_TITLE_CHARS);
  assert.equal(params(link).has('selection'), false);
});

test('only http and https pages can be saved', () => {
  assert.equal(isSavableUrl('https://example.com'), true);
  assert.equal(isSavableUrl('HTTP://example.com'), true);
  for (const url of ['chrome://extensions', 'file:///etc/hosts', 'about:blank', 'javascript:alert(1)', '', undefined]) {
    assert.equal(isSavableUrl(url), false);
    assert.equal(buildSaveLink({ url, title: 't' }), null);
  }
});
