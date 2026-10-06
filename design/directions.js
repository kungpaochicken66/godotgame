'use strict';
let currentDirection = 'a';
let exploring = false;
let chosenCategory = '';
const categories = [['Cabin', '⌂'], ['Furniture', '🪑'], ['Plants', '🌷'], ['Path', '▦'], ['Swing', '↔']];
function showDirection(direction) {
  currentDirection = direction;
  const closer = direction === 'a';
  document.querySelectorAll('[data-direction]').forEach(button => {
    button.setAttribute('aria-pressed', button.dataset.direction === direction);
  });
  document.querySelector('#comparison').innerHTML = `
    <div class="stage comparison-stage direction-${direction}${exploring ? ' play' : ''}">
      <img class="concept" src="scene-${direction}.png" alt="${closer ? 'A · A closer view' : 'B · A wider view'}">
      <div class="hud"><div class="pill">Shared home<small>3 / 4 friends · Example</small></div><div class="pill">✓ Home saved<small>Local preview state</small></div></div>
      <div class="hint" aria-live="polite">${exploring ? 'Explore mode preview. Walking will be implemented in Godot.' : chosenCategory ? 'Category selected. Try placement in the interactive preview.' : 'Choose a category to preview the catalog.'}</div>
      <div class="bottom"><div class="catalog-title"><strong>What would you like to place?</strong><small>All items free · Place duplicates</small></div>
        <div class="items">${categories.map(([name, symbol]) => `<button class="item" data-category="${name}" aria-pressed="${name === chosenCategory}"><b aria-hidden="true">${symbol}</b>${name}</button>`).join('')}</div>
        <div class="bottom-row"><button class="primary right" data-mode>${exploring ? 'Decorate' : 'Explore'}</button></div>
      </div>
    </div>
    <div class="direction-caption"><h2>${closer ? 'A · A closer view' : 'B · A wider view'}</h2>
    <p>${closer ? 'A closer camera emphasizes the characters. The catalog sits at the bottom.' : 'A higher camera shows more space. The catalog sits on the right.'}</p>
    <p>${closer ? 'Large layouts require moving the camera.' : 'Characters and furniture look smaller; details need a closer view.'}</p></div>`;
  localize();
}
document.querySelectorAll('[data-direction]').forEach(button => {
  button.addEventListener('click', () => { exploring = false; chosenCategory = ''; showDirection(button.dataset.direction); });
});
document.querySelector('#comparison').addEventListener('click', event => {
  const category = event.target.closest('[data-category]');
  if (category) chosenCategory = category.dataset.category;
  if (event.target.closest('[data-mode]')) exploring = !exploring;
  if (category || event.target.closest('[data-mode]')) showDirection(currentDirection);
});
document.addEventListener('localechange', () => showDirection(currentDirection));
showDirection('a');
