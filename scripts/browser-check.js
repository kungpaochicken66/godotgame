// Run in a disposable, isolated browser context on design/index.html.
// This resets only that context's preview save. It must not run in a user's active preview.
async function runPreviewChecks() {
  const results = [];
  function assert(value, message) { if (!value) throw new Error(message); }
  function click(selector) {
    const element = document.querySelector(selector);
    assert(element && !element.disabled, `Unavailable control: ${selector}`);
    element.click();
  }
  function selectScenario(value) {
    scenarioSelect.value = value;
    scenarioSelect.dispatchEvent(new Event('change'));
  }
  function inspectCoverage() {
    const walker = document.createTreeWalker(stage, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const node = walker.currentNode;
      const source = sourceText.get(node)?.trim();
      if (!source) continue;
      assert(messages[source] !== undefined || /^(Sunny|Sky|Peach|Leaf) · |^●/.test(source), `Uncataloged text: ${source}`);
    }
    for (const element of stage.querySelectorAll('[aria-label], [alt]')) {
      const source = sourceAttributes.get(element);
      for (const value of Object.values(source || {})) {
        assert(messages[value] !== undefined || /, Select to edit$/.test(value), `Uncataloged accessible text: ${value}`);
      }
    }
    assert(document.documentElement.scrollWidth <= innerWidth, 'Horizontal page overflow');
    const bounds = stage.getBoundingClientRect();
    for (const panel of stage.querySelectorAll('.welcome,.bottom,.hud,.hint,.dialog')) {
      const box = panel.getBoundingClientRect();
      assert(box.left >= bounds.left - 1 && box.right <= bounds.right + 1 && box.top >= bounds.top - 1 && box.bottom <= bounds.bottom + 1, `Panel outside scene: ${panel.className}`);
    }
  }
  for (const code of supportedLocales) {
    await setLocale(code);
    assert(document.querySelector('#scenario option[value="normal"]').textContent === messages['Normal play'], 'Scenario option translation');
    assert(document.querySelector('#language').getAttribute('aria-label') === messages.Language, 'Language accessibility label');
    click('#reset');
    click('[data-action="confirm-reset"]');
    click('[data-role="2"]');
    assert(role === 2, 'Character selection');
    inspectCoverage();
    click('[data-action="join"]');
    click('[data-action="build"]');
    click('[data-item="tree"]');
    const bounds = stage.getBoundingClientRect();
    stage.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: bounds.left + bounds.width * 0.24, clientY: bounds.top + bounds.height * 0.78 }));
    inspectCoverage();
    click('[data-action="place"]');
    assert(world.length === 1 && world[0].x === 24 && world[0].y === 78, 'Lower lawn tree regression');
    assert(!document.querySelector('.items'), 'Catalog should collapse');
    const treeId = world[0].id;
    click(`[data-object="${treeId}"]`);
    assert(document.querySelector(`[data-object="${treeId}"]`).getAttribute('aria-label') === `${messages.Tree}, ${messages['Select to edit']}`, 'Localized object label');
    click('[data-action="move"]');
    const pending = JSON.stringify(draft);
    await setLocale(code === 'en' ? 'de' : 'en');
    assert(JSON.stringify(draft) === pending && world.length === 1 && role === 2, 'Language switch must retain draft, objects and character');
    await setLocale(code);
    click('[data-action="cancel-draft"]');
    click(`[data-object="${treeId}"]`);
    click('[data-action="remove"]');
    inspectCoverage();
    click('[data-action="confirm-remove"]');
    assert(world.length === 0, 'Removal');
    click('[data-action="undo"]');
    assert(world.length === 1, 'Undo');
    click('[data-action="inside"]');
    click('[data-item="bed"]');
    click('[data-action="rotate"]');
    inspectCoverage();
    click('[data-action="place"]');
    assert(world.some(item => item.kind === 'bed' && item.room === 'inside'), 'Interior bed placement');
    assert(JSON.parse(localStorage.getItem(storeKey)).length === world.length, 'Local layout save');
    for (const scenario of ['occupied', 'full', 'offline', 'savefail', 'empty']) {
      selectScenario(scenario);
      inspectCoverage();
    }
    selectScenario('savefail');
    if (document.querySelector('[data-action="more"]')) click('[data-action="more"]');
    click('[data-item="flowers"]');
    click('[data-action="place"]');
    assert(saveFailed, 'Simulated save failure');
    click('[data-action="retry-save"]');
    assert(!saveFailed && JSON.parse(localStorage.getItem(storeKey)).length === world.length, 'Retry save');
    selectScenario('normal');
    click('[data-view="swing"]');
    click('[data-action="sit"]');
    inspectCoverage();
    assert(document.querySelector('.swing-motion'), 'Swing animation');
    click('[data-action="close"]');
    assert(!document.querySelector('.dialog'), 'Leave swing');
    assert(document.documentElement.lang === code && localStorage.getItem(localeStorageKey) === code, 'Locale state and persistence');
    results.push({ locale: code, passed: true, savedObjects: world.length });
  }
  return results;
}
