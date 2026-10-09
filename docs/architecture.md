# Architecture

World Myth is an offline Crystal/GTK4 worldbuilding IDE. YAML and Markdown are the source of truth. SQLite is a disposable runtime artifact; no player state or gameplay simulation belongs here.

One Shards project provides `world-myth` (headless CLI) and `world-myth-gtk` (native desktop). `WorldMyth::Core` owns discovery, typed models, validation, source document sessions, reversible editing, conflict-safe persistence and compilation. Core never requires GTK. The GUI calls Core directly; there is no service or web stack.

Terminal Preview is a separate CLI viewer launched in Kitty using an argument
array, without a shell. Core's read-only Preview projection resolves terrain,
object placements and entity positions. The desktop passes a private temporary
JSON snapshot of source buffers so unsaved edits can be viewed without writing
world files. The viewer validates this snapshot independently. The launcher removes
it when Kitty exits, or when the editor exits normally. It is a point-in-time view,
not a live connection. No engine logic, player state or game simulation is involved.
Rendering and terminal input belong to CLI, not Core. Absolute cursor positioning
in two-column cells separates logical coordinates from terminal glyph widths;
the viewport draws only cells fitting the current terminal dimensions.

Each document owns exact source text, a revision, save baseline, disk hash and bounded undo history. Typed views are projections. One brush gesture is one transaction. Invalid source remains editable. Commented YAML requires an explicit, undoable normalization before visual changes. Validation sees unsaved buffers; compilation requires saved files. A worker handles project-wide work; GTK widgets are accessed only on the GTK main thread.

Maps use dense terrain/collision rows and sparse object placements. IDs, not filenames or names, resolve references. Per-document operations are the future storage boundary; MVP has no chunks or streaming.

Future generators receive seed, algorithm version and configuration and return a WorldPatch containing proposed document edits with expected source hashes. A diff preview and user approval precede application through document history. Generators never write source files. Region regeneration and preservation of manual edits belong to that future contract. No generator framework or Axiom compatibility is implied.

## Isometric scene pipeline (0.2)

Core now owns surface/height/wall data, the sprite library, and a shared glyph
renderer (`SceneRenderer`). A scene consumes validated definitions and an explicit
animation time. It projects `(x,y,z)` to `(4(x-y), x+y-z)` character coordinates;
terrain diamonds are 8 columns by 2 rows. Rendered depth is `x+y+z` and is
interpolated per character fragment. Sprites are vertical billboards with a foot
anchor. Foreground and background depths are composed separately so transparent
sprite backgrounds show the underlying world regardless of submission order.

Geometry is prepared lazily for visible tile ranges and spatially indexed in
screen-space buckets. Glyph frames include separate active-surface hit data for
painting. Walls and sprite overhangs have their own bounds. Changing a document
rebuilds the scene projection; animation does not parse YAML. GTK displays the
same composed cells through Cairo/Pango, with editor grid/collision/selection aids;
terminal Preview emits ANSI updates only for changed cells. Both cap playback at
30 Hz with monotonic elapsed time. Camera orientation is fixed.

The ground grid remains in `layers` for compatibility; extra surfaces are named
map-local grids. Cutaway hides surfaces whose minimum stored elevation exceeds
the active surface's minimum elevation. Roof visibility is independent. This is
an explicit surface filter, not an automatic room detector or geometric slicing
plane. A building is assembled from walls and surfaces, not a single facade sprite.

New projects use v2. The migration pipeline validates, converts in a temporary
sibling directory, validates again, then publishes a new project directory. It
never upgrades an existing directory in place. Future runtime consumers must
implement the documented SQLite v2 contract; no Axiom integration is implied.
