# Our Little Town

A design preview for a planned **Godot 3D iPad game** in which 2–4 children decorate a shared town from separate home networks.

This repository currently contains requirements, art concepts and a browser interaction preview. It does **not** contain a playable Godot project, iPad build, multiplayer service or server-side game save.

## Run the preview

Requires Python 3; no package installation or build step is needed.

```sh
python3 -m http.server 8769 --bind 127.0.0.1
```

Open [the interactive preview](http://127.0.0.1:8769/design/index.html) or [the concept comparison](http://127.0.0.1:8769/design/directions.html). Use HTTP rather than opening the files directly because language catalogs are loaded with `fetch`.

## Languages

English is the default. Choose English, Simplified Chinese, Japanese, Spanish, French or German from the language menu. The browser remembers the selection if storage is available. Layouts use the existing `game1006-design-a-v2` storage key; locale changes do not reset them. Browser storage belongs to an origin, so a different host or port has a separate preview save.

Repository code, filenames, comments and documentation are English. Localized UI copy lives in `design/locales/`. Each language has the same message keys. See [the design specification](docs/design-spec.md) for behavior and limitations.

## Repository layout

```text
docs/                  Requirements, design decisions and validation evidence
design/                Static preview, original concept images and generation prompts
design/locales/        Six UI catalogs and native language names
scripts/check.py       Dependency-free repository and locale checks
```

- [Requirements and progress](docs/requirements.md)
- [Design specification](docs/design-spec.md)
- [Visual references](docs/visual-references.md)
- [Validation record](docs/validation.md)
- [Source upload procedure](docs/source-upload.md)

## Check

```sh
python3 scripts/check.py
node --check design/flow.js
node --check design/i18n.js
node --check design/directions.js
```

Node is only needed for JavaScript syntax checks, not to serve the preview. Browser verification is recorded separately and must not be reported as iPad or multiplayer verification.

## Progress boundary

Direction A is selected. Placement, furniture scale and localization have been revised in the preview. Final design acceptance and several gameplay rules remain open. Development phases have not been planned, and Godot implementation has not started. Git initialization and uploading these files do not constitute a game release.
