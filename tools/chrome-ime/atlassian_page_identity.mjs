function normalizedPathname(pathname) {
  if (pathname.length > 1 && pathname.endsWith('/')) {
    return pathname.replace(/\/+$/, '');
  }
  return pathname;
}

function numericPageId(url) {
  const pathname = normalizedPathname(url.pathname);
  const viewMatch = pathname.match(
    /^\/wiki\/spaces\/[^/]+\/pages\/(\d+)(?:\/[^/]*)?$/,
  );
  if (viewMatch) {
    return viewMatch[1];
  }

  const editMatch = pathname.match(/^\/wiki\/pages\/edit-v2\/(\d+)$/);
  if (editMatch) {
    return editMatch[1];
  }

  const queryPageIds = url.searchParams.getAll('pageId');
  if (
    pathname === '/wiki/pages/viewpage.action' &&
    queryPageIds.length === 1 &&
    /^\d+$/.test(queryPageIds[0])
  ) {
    return queryPageIds[0];
  }

  return null;
}

export function confluencePageIdentity(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    return null;
  }

  if (url.protocol !== 'https:' && url.protocol !== 'http:') {
    return null;
  }

  return {
    origin: url.origin,
    pageId: numericPageId(url),
  };
}

export function hasSameConfluencePageIdentity(candidateValue, requestedValue) {
  const candidate = confluencePageIdentity(candidateValue);
  const requested = confluencePageIdentity(requestedValue);
  if (!candidate || !requested || candidate.origin !== requested.origin) {
    return false;
  }

  return candidate.pageId !== null && candidate.pageId === requested.pageId;
}

export function findPageWithConfluenceIdentity(pages, requestedValue) {
  return pages.find((candidate) =>
    hasSameConfluencePageIdentity(candidate.url(), requestedValue)
  ) ?? null;
}
