// Builds the coreader://save deep link. No browser APIs here, so Node can test it.

export const MAX_SELECTION_CHARS = 2000;
export const MAX_TITLE_CHARS = 300;
// Upper bound for the whole link. Non-Latin text grows up to nine times when
// percent-encoded, so the selection is cut again if the link would pass this.
export const MAX_LINK_CHARS = 8000;

/** Only pages the app can fetch for itself. */
export function isSavableUrl(url) {
  return typeof url === 'string' && /^https?:\/\//i.test(url);
}

/**
 * @param {{url: string, title?: string, selection?: string}} page
 * @returns {{link: string, truncated: boolean} | null} null when the page cannot be saved
 */
export function buildSaveLink({ url, title = '', selection = '' }) {
  if (!isSavableUrl(url)) return null;

  const cleanTitle = clip(collapse(title), MAX_TITLE_CHARS).text;
  let base = `coreader://save?url=${encodeURIComponent(url)}`;
  if (cleanTitle) base += `&title=${encodeURIComponent(cleanTitle)}`;

  const wanted = selection.replace(/\r\n?/g, '\n').trim();
  if (!wanted) return { link: base, truncated: false };

  let { text, truncated } = clip(wanted, MAX_SELECTION_CHARS);
  const room = MAX_LINK_CHARS - base.length - '&selection='.length - '&truncated=1'.length;
  while (text && encodeURIComponent(text).length > room) {
    // Drop a tenth at a time: a few rounds at most, and never mid-surrogate.
    text = clip(text, Math.floor(codePoints(text).length * 0.9)).text;
    truncated = true;
  }
  if (!text) return { link: base, truncated: true };

  let link = `${base}&selection=${encodeURIComponent(text)}`;
  if (truncated) link += '&truncated=1';
  return { link, truncated };
}

function collapse(text) {
  return String(text ?? '').replace(/\s+/g, ' ').trim();
}

function codePoints(text) {
  return Array.from(text);
}

// Counts code points, so an emoji is never cut in half into an invalid link.
function clip(text, limit) {
  const points = codePoints(text);
  if (points.length <= limit) return { text, truncated: false };
  return { text: points.slice(0, Math.max(0, limit)).join('').trimEnd(), truncated: true };
}
