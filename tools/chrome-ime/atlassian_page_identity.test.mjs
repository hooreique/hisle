import assert from 'node:assert/strict';
import test from 'node:test';

import {
  confluencePageIdentity,
  findPageWithConfluenceIdentity,
  hasSameConfluencePageIdentity,
} from './atlassian_page_identity.mjs';

const requestedURL = 'https://example.atlassian.net/wiki/spaces/HISLE/pages/123456/Old+Title';

test('normalizes query, fragment, and trailing slash for a configured page', () => {
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/spaces/HISLE/pages/123456/Old+Title/?src=sidebar#comment-7',
      requestedURL,
    ),
    true,
  );
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/spaces/HISLE/pages/123456',
      requestedURL,
    ),
    true,
  );
});

test('uses the numeric page ID instead of a mutable title slug', () => {
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/spaces/HISLE/pages/123456/New+Title?focusedCommentId=7',
      requestedURL,
    ),
    true,
  );
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/spaces/OTHER/pages/123456/Renamed',
      requestedURL,
    ),
    true,
  );
});

test('recognizes view and edit URLs for the same numeric page ID', () => {
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/pages/edit-v2/123456',
      requestedURL,
    ),
    true,
  );
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/pages/viewpage.action?pageId=123456',
      requestedURL,
    ),
    true,
  );
});

test('rejects another page on the same Atlassian host', () => {
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/spaces/HISLE/pages/654321/Old+Title',
      requestedURL,
    ),
    false,
  );
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/spaces/HISLE/overview',
      requestedURL,
    ),
    false,
  );
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/pages/edit-v2/654321',
      requestedURL,
    ),
    false,
  );
});

test('requires the same origin', () => {
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://other.atlassian.net/wiki/spaces/HISLE/pages/123456/Old+Title',
      requestedURL,
    ),
    false,
  );
  assert.equal(
    hasSameConfluencePageIdentity(
      'http://example.atlassian.net/wiki/spaces/HISLE/pages/123456/Old+Title',
      requestedURL,
    ),
    false,
  );
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net:8443/wiki/spaces/HISLE/pages/123456/Old+Title',
      requestedURL,
    ),
    false,
  );
});

test('requires an anchored, recognized Confluence page route', () => {
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/plugins/servlet/pages/123456',
      requestedURL,
    ),
    false,
  );
  assert.equal(
    hasSameConfluencePageIdentity(
      'https://example.atlassian.net/wiki/spaces/HISLE/overview',
      'https://example.atlassian.net/wiki/spaces/HISLE/overview',
    ),
    false,
  );
});

test('rejects missing, nonnumeric, repeated, and different legacy page IDs', () => {
  for (const candidate of [
    'https://example.atlassian.net/wiki/pages/viewpage.action',
    'https://example.atlassian.net/wiki/pages/viewpage.action?pageId=abc',
    'https://example.atlassian.net/wiki/pages/viewpage.action?pageId=123456&pageId=123456',
    'https://example.atlassian.net/wiki/pages/viewpage.action?pageId=654321',
  ]) {
    assert.equal(hasSameConfluencePageIdentity(candidate, requestedURL), false);
  }
});

test('keeps large numeric page IDs as exact strings', () => {
  const largeRequested =
    'https://example.atlassian.net/wiki/spaces/HISLE/pages/9007199254740992/Title';
  const largeCandidate =
    'https://example.atlassian.net/wiki/spaces/HISLE/pages/9007199254740993/Title';

  assert.equal(hasSameConfluencePageIdentity(largeCandidate, largeRequested), false);
});

test('rejects browser-internal and malformed URLs', () => {
  assert.equal(hasSameConfluencePageIdentity('about:blank', requestedURL), false);
  assert.equal(hasSameConfluencePageIdentity('chrome://newtab/', requestedURL), false);
  assert.equal(confluencePageIdentity('not a URL'), null);
});

test('selects the exact page after ignoring same-host and browser tabs', () => {
  const wrongPage = {
    url: () => 'https://example.atlassian.net/wiki/spaces/HISLE/pages/654321/Wrong',
  };
  const browserPage = { url: () => 'chrome://newtab/' };
  const exactPage = {
    url: () => 'https://example.atlassian.net/wiki/spaces/HISLE/pages/123456/Renamed',
  };

  assert.equal(
    findPageWithConfluenceIdentity([wrongPage, browserPage, exactPage], requestedURL),
    exactPage,
  );
  assert.equal(
    findPageWithConfluenceIdentity([wrongPage, browserPage], requestedURL),
    null,
  );
});
