import { MAX_SELECTION_CHARS } from './link.js';
import { isSavableUrl, readSelection, saveTab } from './save.js';

const $ = (id) => document.getElementById(id);
const pageButton = $('save-page');
const selectionButton = $('save-selection');
const status = $('status');

function say(text, kind = '') {
  status.textContent = text;
  status.dataset.kind = kind;
}

async function run(tab, options) {
  pageButton.disabled = selectionButton.disabled = true;
  const result = await saveTab(tab, options);
  if (!result.ok) {
    say(result.reason, 'bad');
    return;
  }
  say(
    result.truncated
      ? `Sent to Coreader. The selection was cut to fit ${MAX_SELECTION_CHARS.toLocaleString()} characters.`
      : 'Sent to Coreader.',
    'ok',
  );
  // Long enough to read when the browser has already been told to always open Coreader.
  setTimeout(() => window.close(), result.truncated ? 2600 : 1100);
}

async function showShortcut() {
  const commands = await chrome.commands.getAll();
  const shortcut = commands.find((command) => command.name === 'save-page')?.shortcut;
  if (!shortcut) return;
  const hint = $('shortcut');
  hint.append('Shortcut: ');
  const key = document.createElement('kbd');
  key.textContent = shortcut;
  hint.append(key);
  hint.hidden = false;
}

async function init() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  $('page-title').textContent = tab?.title || 'Untitled page';

  if (!tab || !isSavableUrl(tab.url)) {
    $('page-host').textContent = '';
    say('Only web pages can be saved. Open an article and try again.');
    return;
  }
  $('page-host').textContent = new URL(tab.url).hostname.replace(/^www\./, '');

  pageButton.disabled = false;
  pageButton.addEventListener('click', () => run(tab));
  pageButton.focus();

  const selection = (await readSelection(tab.id)).trim();
  if (selection) {
    const count = Array.from(selection).length;
    selectionButton.disabled = false;
    selectionButton.textContent = `Save selection (${count.toLocaleString()} characters)`;
    selectionButton.addEventListener('click', () => run(tab, { selection }));
    if (count > MAX_SELECTION_CHARS) {
      say(`Only the first ${MAX_SELECTION_CHARS.toLocaleString()} characters of the selection are sent.`);
    }
  } else {
    selectionButton.title = 'Select some text on the page first';
  }
  showShortcut();
}

init().catch((error) => say(`Something went wrong: ${error.message}`, 'bad'));
