# World Myth

An offline, native Crystal + GTK4 worldbuilding editor for a terminal ASCII MMORPG.
Author maps, entities and lore in ordinary YAML/Markdown files, validate them, and
compile a standalone SQLite world package. The desktop and headless CLI share the
same domain code. No server, browser or web framework is involved.

## Build on Fedora

```sh
sudo dnf install crystal shards gcc make pkgconf-pkg-config \
  gtk4-devel libadwaita-devel gtksourceview5-devel \
  gobject-introspection-devel cairo-devel pango-devel sqlite-devel libyaml-devel
make setup
shards build
bin/world-myth-gtk
```

Requires Crystal 1.21.1 or later. Tested dependency versions and binding limitations
are in [development](docs/development.md). Building fetches Shards dependencies;
installed applications work offline.

For a CLI-only build, GTK development packages and a display are unnecessary:

```sh
shards install --frozen --skip-postinstall
shards build world-myth
```

## CLI

```sh
bin/world-myth new my-world
bin/world-myth validate my-world
bin/world-myth build my-world
bin/world-myth preview my-world --map heartlands/meadow
bin/world-myth fmt my-world --check
bin/world-myth --help
```

`build` produces `dist/world.sqlite` and `dist/manifest.json`. It preserves the
previous successful output if validation or compilation fails. `fmt` skips YAML
comments unless explicitly authorized with `--allow-comment-loss`.

## Editor

Create or open a project directory, then choose a map from the explorer. Select a
layer, tool and palette entry. Drag to paint, choose Eraser to restore default
terrain, and use Select to inspect cells. Middle-drag or Space-drag pans;
Ctrl-scroll or the +/− buttons zooms. Visibility toggles independently show terrain,
objects, collision overrides and grid lines. Red collision overlays block movement;
green overlays explicitly allow it.

Click **Preview** beside Map/Source (or press F7) to open the selected map in a
separate Kitty terminal. The preview includes unsaved terrain, object and entity
edits through a temporary snapshot; it does not save or change the world. The world
must validate first. Arrows or WASD pan, Q/Esc closes. The terminal resizes live and
uses a shared isometric Unicode renderer with per-character depth and truecolor.
Space pauses animation; Tab selects a surface; C cuts above it; R toggles roofs;
uppercase A cycles animation clips. It is a read-only scene viewer.

The desktop launcher currently requires `kitty` (`sudo dnf install kitty`) and
the `world-myth` CLI beside the GUI binary or on PATH. The CLI command above runs
directly in any interactive ANSI/truecolor Linux terminal. Actual glyph appearance
depends on the terminal font and its Unicode support. Reopen Preview to see later
edits; the snapshot is removed when the terminal or editor exits normally.

Select entities to edit name, tags, position and scalar properties in the inspector.
Use Source for raw YAML or Markdown. Invalid files remain editable, and validation
errors navigate to source locations. Visual editing of commented YAML requires an
explicit, undoable normalization preview. Saving detects external file changes and
provides reload/save-copy recovery instead of silently overwriting another editor.

Shortcuts: Ctrl+N new, Ctrl+O open, Ctrl+S save all, Ctrl+Z undo,
Ctrl+Shift+Z redo, F5 validate, F6 build, F7 terminal preview. Window/layout/rendering preferences and
recent projects are local to your XDG configuration directory. Git status is
read-only; Git itself is optional.

## Verification

```sh
crystal spec
crystal tool format --check
shards build
make gui-check  # requires a real graphical display
```

The GUI check launches native widgets and creates a disposable test world.
All fixtures are generated in temporary directories. See [verification](docs/verification.md)
for measured results and their limits.

## Layout and boundaries

- `src/world_myth/core/`: models, project discovery, document/history, validation,
  editing, Git status and SQLite compilation; no GTK imports.
- `src/world_myth/gui/`: Libadwaita workspace, GtkSourceView, Cairo/Pango canvas.
- `src/world_myth/cli/`: argument handling using the same Core.
- `spec/`: headless Crystal Specs; `scripts/`: native integration checks.
- `spec/support/`: temporary world fixtures for core and native integration checks.
- `docs/`: [architecture](docs/architecture.md), [world format](docs/world-format.md),
  [runtime package](docs/compilation.md), [development](docs/development.md).

Scope deliberately excludes gameplay simulation, multiplayer, player state,
procedural generation, and Axiom integration. Map/entity creation beyond the
initial world can be done through ordinary source files; new files are discovered
on returning to the editor. This is an initial Linux desktop implementation, not a
cross-platform packaged release.

Apache-2.0; see [LICENSE](LICENSE).

## Isometric editing (0.2)

Create a world from the welcome screen and open **Quiet Meadow**. Add surfaces
for floors, bridges or roofs; select the active surface and enable **Cut above
active** to inspect lower levels. **Roofs** controls roof visibility. Geometry,
Unicode sprites, colors and animation are shared by the native map canvas and
terminal Preview. World projects are kept outside the application's source tree.

New projects use source format v2. For an existing project use **Create v2 copy…**
or `bin/world-myth migrate old-world --output new-world`. Comments require explicit
normalization consent; the original world remains unchanged.

Use **Add surface…**, then paint its footprint with the Terrain brush. Layer
choices also include Height, Slope / stairs and Walls. Walls' palette entries
include material, edge and height. The Entity inspector assigns sprite ID,
animation, supporting surface and facing. Object placements have a facing control
on the map inspector. Opening `terrain.yaml` lets you assign top/side sprite patterns.

**New sprite…** creates a sprite document. Its native editor supports palette ink
(glyph/foreground/optional background), brush, transparent eraser, foot anchor,
resize, eight directions, named animations, frame duplication/deletion/reordering,
duration and looping. **Add direction** copies the default frames before editing
a separate direction. Space in source frame rows means transparency, not a literal
space glyph. Use **Map** to return from source to the sprite grid. All source
changes share document undo/redo and conflict-aware saving.

```sh
make isometric-check  # real GTK sprite/surface editing; requires a display
make preview-check    # real Kitty, animation, pause, cutaway and cleanup
make benchmark        # 256×256, three surfaces, 100 animated placements
```

Camera orientation is fixed. The art alphabet is deliberately limited to ASCII,
box/block characters and tested text symbols; emoji and combining sequences are
unsupported. There is no automatic room detection, arbitrary mesh editor, pathfinding
or gameplay execution. Source and SQLite v2 are documented in `docs/`.
