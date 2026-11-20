// Every English text the page itself can show (js/hud.js passes each through app.tr). Godot's bridge mirrors
// this list into the game's locales, so the six languages translate it; the hello message brings the
// translations. Texts that Godot sends (the action button's label, toasts, hints) arrive translated already.
// One plain string per line: the list is read by tools as well as imported.
export const PAGE_STRINGS = [
  "City",
  "Office",
  "Cafe",
  "Gym",
  "Bakery",
  "Bookstore",
  "Flower shop",
  "Ice cream",
  "Ride home",
  "Reset view",
  "Look around",
  "Stop looking",
  "Pause the city",
  "Resume",
  "Sunny",
  "Rain",
  "Night",
  "Rotate view left",
  "Rotate view right",
  "Zoom",
];
