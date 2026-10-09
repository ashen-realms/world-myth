# MVP 0.1 verification

Reference environment: Fedora 43 / GNOME on 2026-10-09, Crystal 1.21.1 and the
versions in development.md. These checks were run, not inferred from compilation.

| Check | Result |
|---|---|
| `crystal spec` | 34 examples, zero failures/errors |
| Specs with DISPLAY and WAYLAND_DISPLAY unset | Pass |
| `crystal tool format --check` | Pass |
| `shards build` | CLI and GTK executables built |
| CLI validate of example-world | Valid |
| CLI build of example-world | SQLite and manifest produced |
| Consecutive example builds | Identical SQLite and manifest SHA-256 values |
| CLI `ldd` inspection | No GTK/Adwaita dependency |
| Minimal native window | Launched; Cairo/Pango glyphs and GtkSource highlighting visually inspected |
| Native GUI integration scenario | Launched on GNOME/Wayland; passed |
| Real mouse/keyboard scenario | Launched on isolated X11/Xvfb display; passed |
| Terminal Preview integration | GTK Preview button launched Kitty on GNOME/Wayland; unsaved edits, pan, Q and snapshot cleanup passed |

## Core coverage

Creation without overwriting an existing directory; YAML/map serialization;
terrain, object and collision painting/erasing; continuous stroke undo/redo;
stale revision rejection; comments/normalization; malformed YAML preservation;
external changes; schema versions and unexpected keys; duplicate IDs/YAML keys;
map dimensions, legends and references; entity types/properties/positions;
qualified reference ambiguity; UTF-8 glyph separation; viewport zoom coordinates;
CLI help/errors/format behavior; read-only SQLite content and integrity;
repeatable builds; publication rollback and interrupted-build recovery;
concurrent compiler exclusion; pre-replacement save failure; Markdown preservation;
Git-optional behavior; all entity/layer content in the example; read-only preview
of unsaved terrain and entities; object placements; preview reference errors;
terminal viewport clipping on a 256×256 map and fixed columns for wide glyphs.

## Native verification

`scripts/gui_check.cr` opens a disposable copy of Eldoria in actual GTK widgets.
It exercises painting, erasure, native Undo/Redo/Save buttons, pan/zoom, source
editing, validation diagnostics, explicit normalization and undo restoring
comments, entity inspector changes, GUI compilation, and Cancel on the native
unsaved-changes dialog. It renders and captures the workspace using GTK's own
snapshot/renderer API. Both ordinary and wide Unicode glyphs were visually checked.

`scripts/input_check.cr` uses XTest to deliver real pointer and keyboard events:
drag painting, middle-button pan, Ctrl-scroll zoom, Ctrl+Z/Ctrl+Shift+Z, Ctrl+S,
and source-editor undo. It also exercises Create/Open World through native file
dialogs. Tests select paths only under temporary directories. Dialog tests force
GC while open to cover callback lifetime handling. XTest is not part of the app.

On the 256×256 GUI fixture, viewport culling drew 312–403 cells at the tested
window sizes; observed frame time was about 1.3–1.7 ms and stroke commit/refresh
about 48–64 ms in the development build.
These are local observations, not a cross-machine performance guarantee. There is
one DrawingArea and no per-cell widget allocation.

`scripts/preview_check.cr` clicks the actual native Preview button, opens a real
Kitty window running the CLI, and inspects rendered terminal text through Kitty's
test-only local control socket. It verifies an unsaved source edit, unchanged disk
files, arrow/WASD panning, Q exit and removal of the temporary snapshot. Test
world/configuration paths include spaces. This scenario passed on GNOME/Wayland.

## Limits and follow-up

- Tested on the documented Fedora/GNOME toolchain. Other Linux versions and
  cross-platform packaging are unverified.
- New world creation is graphical. Additional region/map/entity definitions can
  be authored as source files; dedicated creation/rename wizards are a useful next
  increment.
- YAML normalization intentionally removes comments only after explicit consent.
  Comment-preserving structural edits are a future improvement.
- The SQLite format is internal. Define reader compatibility with Axiom before
  introducing gameplay-specific fields or integration promises.
- Build publication recovers ordinary failures and interrupted renames; see
  compilation.md for the power-loss/concurrent-reader limitation.
- No procedural generator, gameplay preview, multiplayer, or player state is
  implemented. The generator boundary is documentation only, as specified.
- Additional usability work could add flood fill, rectangle selection, entity
  creation dialogs, and per-document viewport persistence without changing Core.
