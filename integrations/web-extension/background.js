// Service worker: context menu items and keyboard shortcuts.

import { readSelection, saveTab } from './save.js';

const MENU_PAGE = 'coreader-save-page';
const MENU_SELECTION = 'coreader-save-selection';
const WEB_PAGES = ['http://*/*', 'https://*/*'];

chrome.runtime.onInstalled.addListener(() => {
  // Menus persist across worker restarts; rebuild only on install or update.
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_PAGE,
      title: 'Save page to Coreader',
      contexts: ['page', 'link', 'image'],
      documentUrlPatterns: WEB_PAGES,
    });
    chrome.contextMenus.create({
      id: MENU_SELECTION,
      title: 'Save selection to Coreader',
      contexts: ['selection'],
      documentUrlPatterns: WEB_PAGES,
    });
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (!tab) return;
  if (info.menuItemId === MENU_PAGE) {
    await report(tab, await saveTab(tab));
  } else if (info.menuItemId === MENU_SELECTION) {
    // The page keeps paragraph breaks; the menu's own copy flattens them.
    const selection = (await readSelection(tab.id)) || info.selectionText || '';
    await report(tab, await saveTab(tab, { selection }));
  }
});

chrome.commands.onCommand.addListener(async (command, tab) => {
  tab ??= (await chrome.tabs.query({ active: true, lastFocusedWindow: true }))[0];
  if (!tab) return;
  if (command === 'save-page') {
    await report(tab, await saveTab(tab));
  } else if (command === 'save-selection') {
    const selection = await readSelection(tab.id);
    await report(tab, await saveTab(tab, { selection }));
  }
});

// No popup is open on these paths, so the toolbar badge is the only feedback.
async function report(tab, result) {
  const tabId = tab.id;
  await chrome.action.setBadgeBackgroundColor({ tabId, color: result.ok ? '#3d5a40' : '#9b2c1f' });
  await chrome.action.setBadgeText({ tabId, text: result.ok ? '✓' : '!' });
  await chrome.action.setTitle({
    tabId,
    title: result.ok ? 'Sent to Coreader' : `Save to Coreader: ${result.reason}`,
  });
  setTimeout(() => {
    // The tab may be gone by now.
    chrome.action.setBadgeText({ tabId, text: '' }).catch(() => {});
    chrome.action.setTitle({ tabId, title: 'Save to Coreader' }).catch(() => {});
  }, 2500);
}
