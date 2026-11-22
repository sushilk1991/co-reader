// Shared by the popup and the service worker: read the tab, hand it to Coreader.

import { buildSaveLink, isSavableUrl } from './link.js';

export { isSavableUrl };

/** The text selected in the tab, or '' when the page cannot be read. */
export async function readSelection(tabId) {
  try {
    const [frame] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => String(window.getSelection() ?? ''),
    });
    return typeof frame?.result === 'string' ? frame.result : '';
  } catch {
    // Browser pages, the built-in PDF viewer and the extension store refuse scripts.
    return '';
  }
}

/**
 * Opens the coreader://save link for a tab.
 * @returns {Promise<{ok: true, truncated: boolean} | {ok: false, reason: string}>}
 */
export async function saveTab(tab, { selection = '' } = {}) {
  if (!tab?.id || !isSavableUrl(tab.url)) {
    return { ok: false, reason: 'Only web pages (http or https) can be saved.' };
  }
  const built = buildSaveLink({ url: tab.url, title: tab.title, selection });
  if (!built) return { ok: false, reason: 'This page cannot be saved.' };

  try {
    // Navigating to a custom scheme hands the link to macOS and leaves the page
    // where it is. The browser asks once whether Coreader may open.
    await chrome.tabs.update(tab.id, { url: built.link });
  } catch (error) {
    return { ok: false, reason: `The browser refused to open Coreader: ${error.message}` };
  }
  return { ok: true, truncated: built.truncated };
}
