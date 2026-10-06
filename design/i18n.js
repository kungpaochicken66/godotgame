'use strict';
// English is the source language; locale files contain all translated UI copy.
// Remember source text per node so switching languages never translates a translation.
const supportedLocales = ['en', 'zh-CN', 'ja', 'es', 'fr', 'de'];
const localeStorageKey = 'little-town-locale';
const sourceText = new WeakMap();
const sourceAttributes = new WeakMap();
let messages = {};
let locale = 'en';
let localeRequest = 0;
const localeSelect = document.querySelector('#language');

function translateText(source) {
  const text = source.trim();
  if (!text) return source;
  let translated = messages[text];
  if (translated === undefined) {
    // Only these two templates compose several independent messages in one node.
    const label = text.match(/^(Cabin|Chair|Flower pot|Tree|Path|Pond|Swing|Round table|Bed|Rug), Select to edit$/);
    const heading = text.match(/^(Sunny|Sky|Peach|Leaf) · (Cabin|Shared home)$/);
    if (label) translated = `${messages[label[1]] || label[1]}, ${messages['Select to edit'] || 'Select to edit'}`;
    if (heading) translated = `${messages[heading[1]] || heading[1]} · ${messages[heading[2]] || heading[2]}`;
    const prefix = '● ● ● ○';
    if (text.startsWith(prefix)) translated = `${prefix} ${messages['3 / 4 friends · Example'] || '3 / 4 friends · Example'}`;
  }
  return translated === undefined ? source : source.replace(text, translated);
}

function localize(root = document.documentElement) {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (node.parentElement.closest('script, style, [data-no-translate]')) continue;
    if (!sourceText.has(node)) sourceText.set(node, node.nodeValue);
    node.nodeValue = translateText(sourceText.get(node));
  }
  for (const element of [root, ...root.querySelectorAll('[aria-label], [alt], [title]')]) {
    if (element.closest('[data-no-translate]')) continue;
    if (!sourceAttributes.has(element)) {
      sourceAttributes.set(element, Object.fromEntries(['aria-label', 'alt', 'title']
        .filter(name => element.hasAttribute(name)).map(name => [name, element.getAttribute(name)])));
    }
    for (const [name, value] of Object.entries(sourceAttributes.get(element))) element.setAttribute(name, translateText(value));
  }
}

async function setLocale(next) {
  if (!supportedLocales.includes(next)) next = 'en';
  const request = ++localeRequest;
  try {
    const response = await fetch(`locales/${next}.json`);
    if (!response.ok) throw new Error(`Locale request failed: ${response.status}`);
    const dictionary = await response.json();
    if (request !== localeRequest) return;
    messages = dictionary;
    locale = next;
    document.documentElement.lang = locale;
    localeSelect.value = locale;
    try { localStorage.setItem(localeStorageKey, locale); } catch { /* Storage is optional. */ }
    localize();
    document.dispatchEvent(new CustomEvent('localechange', { detail: locale }));
  } catch (error) {
    console.error('Could not load language resources.', error);
    localeSelect.value = locale;
  }
}
localeSelect.addEventListener('change', () => setLocale(localeSelect.value));
let initialLocale = 'en';
try { initialLocale = localStorage.getItem(localeStorageKey) || 'en'; } catch { /* Use English. */ }
setLocale(initialLocale);

fetch('locales/languages.json').then(response => {
  if (!response.ok) throw new Error('Language names could not be loaded.');
  return response.json();
}).then(names => {
  for (const option of localeSelect.options) option.textContent = names[option.value] || option.textContent;
}).catch(error => console.error('Could not load language names.', error));
