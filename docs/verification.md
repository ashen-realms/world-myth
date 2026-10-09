# World Myth 0.2 verification

Reference environment: Fedora 43 / GNOME, 2026-10-09, Crystal 1.21.1 and the
locked bindings documented in development.md. Results below are actual runs.

| Check | Result |
|---|---|
| Crystal Spec | 45 examples, zero failures/errors |
| Specs without DISPLAY/WAYLAND_DISPLAY | Passed |
| `crystal tool format --check` | Passed |
| `shards build` | Both applications built |
| CLI new, validate and build, temporary v2 world | Valid; SQLite v2 and manifest produced |
| Disposable v1/v2 fixtures in Specs | Validation, compilation and SQLite integrity passed |
| Repeated builds in Specs | Identical database bytes |
| Native legacy GUI scenario | Passed after converting test input to projected coordinates |
| Native isometric GUI scenario | Elevated painting, undo, sprite gestures, frame duplication and reload passed |
| Real X11/XTest input | Painting, pan, zoom, shortcuts, native Create/Open dialogs passed |
| Real GTK → Kitty scenario | Unsaved source, pan, animation, pause, surface/cutaway, exit and cleanup passed |

## Coverage

The original 30 core cases cover creation, serialization, validation, references,
source/history, comment normalization, external conflicts, Git-optional operation,
safe build publication/recovery, compiler locking and SQLite integrity. Preview
cases cover snapshot isolation, object rendering, clipping, unsupported legacy
glyph fallback and CLI argument errors.

Spatial cases cover v1-to-v2 copying without modifying originals, explicit consent
for comment normalization, new projects defaulting to v2, v1 edits excluding v2
fields, height/slope/wall/surface edits with undo/redo, sprite palette/timing/reference
validation, deterministic animation and directional fallback, non-looping clips,
elevated picking, transparency/depth composition, offscreen sprite anchors, render
consistency across prior camera views, bridge occupants/cutaway, runtime assets and
surface references, repeated builds, and safe creation of sprite source files.

## Native checks

`make gui-check` creates a disposable v1 world and exercises native buttons,
source diagnostics, explicit normalization, entity edits, compilation, a 256×256
map, and the unsaved-changes dialog. `make input-check` sends real XTest mouse and
keyboard events on an isolated Xvfb display, including native file selection.
The test-only FileChooserDialog inspection still emits GTK deprecation warnings;
production selection uses FileDialog.

`make isometric-check` creates a layered test world with real GTK widgets. It
creates an elevated surface and paints it, checks undo/redo, opens the native sprite
editor, emits its actual GTK drag signals, duplicates/reorders a frame, plays the
animation, and saves/reloads a valid world. Captures use GTK's own renderer and are
stored under `/tmp/world-myth-isometric-*.png`. This test does not claim physical
mouse input for sprite gestures; the separate XTest test covers map input.

`make preview-check` opens actual Kitty windows from the GTK Preview button. A
private test configuration enables a local Unix control socket used to inspect
rendered text and send keys. It verifies real animation changes and paused text,
selects an upper surface/cutaway, closes the viewer and checks snapshot cleanup.
Production does not enable this socket.

## Performance observations and limits

`make benchmark` uses 256×256 cells, three surfaces and 100 animated placements.
After introducing lazy geometry, an observed development run took about 98 ms for
analysis, 33–34 ms for preparation, and 3.1–4.3 ms median / 5.5–8.7 ms p95 per 120×40 glyph
frame across two runs (1,825 candidate primitives). A standalone native demo run
reported about 12.8 ms for a drawn GTK frame. The first view also creates its visible terrain
geometry; preparation is not the complete cold-render cost. Native drawing adds
Pango/Cairo and compositor work. Earlier GTK measurements under concurrent builds
varied substantially; these numbers are local observations, not a frame-rate
promise for every machine or terminal.

After replacing checked-in worlds with disposable fixtures, another run under
concurrent builds measured 177 ms analysis, 66 ms preparation and 7.6 ms median /
14.2 ms p95 rendering (1,824 candidates). The native layered fixture drew a frame
in 16.9 ms. These measurements include different test data and system load.

The renderer caches scene geometry and prepares terrain only for visible ranges;
it does not parse YAML during animation or create a widget per map tile. Terminal
updates emit changed cells. Map edits invalidate the scene cache; document parsing
and validation remain synchronous during visual editing.

Known boundaries: fixed camera orientation; restricted art alphabet; explicit
surface filtering rather than automatic room/roof detection; no arbitrary meshes,
physical simulation, pathfinding, multiplayer or Axiom integration. The schema is
an internal v2 contract. YAML visual edits still require explicit normalization of
comments. Additional map/entity creation beyond the existing GUI tools is available
through source files; no full asset-management system is implied.
