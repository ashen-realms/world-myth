# World source formats 1 and 2

The initial sections describe the legacy v1 fields. The v2 extension below adds
surfaces, walls and sprites; new projects use v2.

A project is a directory containing `world.yaml`, `terrain.yaml`, `regions/`,
`entities/`, and `lore/`. YAML/Markdown files are authoritative. `.worldmyth/`
contains editor metadata and an ignored build lock, never player state.

## Identifiers and discovery

IDs match `[a-z][a-z0-9_.-]*`. Display names may contain Unicode and change
independently. Region IDs are world-wide; map IDs are unique within their region;
terrain and entity IDs are world-wide within their own categories. Object
placement IDs are unique within a map.

The editor discovers `regions/<directory>/region.yaml` and its `maps/*.yaml`
(or `.yml`), plus entity YAML recursively under `entities/`. Directory/filenames
locate documents; declared IDs identify them. Region manifests list map IDs.
Missing listed maps, unlisted discovered maps, duplicate IDs and duplicate YAML
keys are errors. World and terrain manifests retain their fixed filenames.
Cross-document map references use `region-id/map-id`. A bare map ID is accepted
only if exactly one map in the world declares it. Symlinks escaping the project
are rejected during discovery.

Legacy documents use `schema_version: 1`; v2 projects use `schema_version: 2`. Unknown structural fields
are errors. Entity `properties` is the explicit extension field. The supported
format is a single YAML document per file with string mapping keys.

## World and region

```yaml
schema_version: 1
id: eldoria
name: Eldoria
version: 0.1.0
description: A world at the edge of the woods.
default_region: heartlands
```

```yaml
schema_version: 1
id: heartlands
name: Heartlands
maps: [meadow, village]
```

## Terrain catalog

`terrain.yaml` defines logical types once:

```yaml
schema_version: 1
terrain:
  grass:
    glyph: "."
    foreground: "#88aa66"
    background: "#101816"
    passable: true
    movement_cost: 1.0
  wall:
    glyph: "#"
    foreground: "#aaaaaa"
    passable: false
    movement_cost: 0.0
```

Colors are `#RRGGBB`; background defaults to `#101816`. Movement cost must be
finite and nonnegative, and positive for passable terrain. A glyph is one Unicode
grapheme with no control characters. Its display width never changes coordinates:
Pango lays it out, and the renderer centers/clips it within the graphical cell.

## Maps and layers

```yaml
schema_version: 1
id: meadow
name: Quiet Meadow
width: 4
height: 3
default_terrain: grass
legend:
  g: grass
  w: wall
layers:
  terrain:
    - "gggg"
    - "gwwg"
    - "gggg"
  collision:
    - "...."
    - "..+."
    - "#..."
  objects:
    - id: forge
      entity: object.forge
      x: 1
      y: 0
```

All three layers share the explicitly declared map width and height. Coordinates
are zero-based: `(0,0)` is the top-left; x increases right, y down. Rows are y,
characters are x. Dimensions must be positive, with at most 4,194,304 cells.
The editor is exercised at 256×256; the larger guard prevents unbounded input
allocation and is not a performance promise.

Terrain rows use single printable, non-space ASCII **storage symbols**, mapped
through `legend` to terrain IDs. These symbols are unrelated to visible glyphs.
Each terrain/collision row must be ASCII and exactly `width` bytes long, with
exactly `height` rows. Repeated per-tile YAML objects are unnecessary.

Collision is tri-state: `.` inherits terrain passability, `#` blocks movement,
`+` explicitly permits movement. Collision is metadata, not a game simulation.
Object placements are sparse instances referring to entities of type `object`.
Multiple source placements may occupy a cell; the MVP object brush replaces the
placements in the painted cell with one chosen object. Erasing objects removes
placements at that cell. Entity default positions are independent of this layer.

Terrain erasure restores `default_terrain`, which must be present in the legend.
Collision erasure restores `.`. Maps contain no chunks or streaming data.

## Entities

Entities live under `entities/npcs`, `items`, `monsters`, or `objects`; the declared
`type` is authoritative. Supported types are `npc`, `item`, `monster`, `object`.

```yaml
schema_version: 1
id: npc.blacksmith.ulf
type: npc
name: Ulf
tags: [human, blacksmith]
position:
  map: heartlands/village
  x: 7
  y: 5
properties:
  greeting: Welcome, traveler.
  glyph: "@"
  foreground: "#eac981"
```

Name must be nonempty, tags nonempty and unique. Position is optional; when
present, the referenced map and coordinates must be valid. `properties` accepts
string keys and scalar string/boolean/integer/finite-float/null values; nested
objects/lists are rejected in v1. `glyph` and `foreground` have the terrain display
validation rules. Other properties are authoring metadata without gameplay
interpretation. Default glyphs are `@`, `!`, `M`, and `+` respectively.

## Source editing and normalization

Raw YAML and Markdown saves retain the editor buffer exactly. Visual edits use
stable YAML serialization; a document containing comments, anchors, aliases or
explicit tags first requires an explicit normalization preview and acceptance.
Normalization is undoable. Unsupported structure remains editable in Source;
malformed YAML disables visual map editing rather than losing the text.

`fmt` canonicalizes supported YAML mapping order and serializer layout. It skips
sensitive files unless `--allow-comment-loss` is given and never formats Markdown.
`fmt --check` writes nothing and exits 1 if an eligible file needs formatting.
Skipped files are reported and do not alone make the command fail.

## Source format v2 (World Myth 0.2)

New projects use v2. All typed documents in a project must match the world
manifest's version. Existing v1 projects stay readable/editable; visual edits
serialize their original v1 fields. Rendering adapts them to flat ground and
legacy glyphs without rewriting sources. Use `world-myth migrate OLD --output NEW`
or **Create v2 copy…** for spatial editing. The destination must not exist.
Migration copies recognized world sources, not `.git`, build artifacts or unrelated
files. It includes dirty GUI buffers. YAML normalization requires explicit
`--allow-comment-loss` when comments/anchors are present; the original is untouched.

### Coordinates and surfaces

Map `layers.terrain` and `layers.collision` still describe the built-in surface
`ground`. In v2 it also has `elevation` (rows of space-separated integers) and
`shapes` (ASCII rows). A map's optional `surfaces` array contains additional grids:

```yaml
surfaces:
  - id: bridge
    kind: platform
    terrain: [" dd ", " dd "]
    collision: ["....", "...."]
    elevation: ["4 4 4 4", "4 4 4 4"]
    shapes: ["....", "...."]
walls:
  - id: north-wall
    surface: ground
    x: 1
    y: 1
    edge: N
    height: 6
    material: wall
```

Every grid has the map's full width and height. A space in an additional terrain
surface means absence, not a terrain type. Kinds are `ground`, `floor`, `platform`
and `roof`. Heights are integers from -64 to 64. Shapes: `.` flat; `n/e/s/w` slopes
rising one unit toward that map direction; uppercase `N/E/S/W` four-step stairs.
Map north is decreasing y, east increasing x. Walls occupy a cell edge N/E/S/W,
are 1–32 height units tall, and use a terrain material ID. Duplicate walls on an
edge are invalid. At most 32 surfaces and 4,194,304 grid cells across all surfaces
are supported. Grid dimensions are explicit even for sparse elevated floors.

Entity positions and object placements add `surface` (default `ground`) and
`facing` (`N NE E SE S SW W NW`, default `S`). The selected surface must exist and
contain terrain at that cell. The foot position is its center; z is sampled from
the surface shape. Decorative height does not create collision or support.
Erasing a supporting cell preserves placed content and reports invalid references
until it is moved or the cell is restored. Ground sides are solid visual faces;
other surfaces render thin slabs. This is an authoring model, not a physics engine.

### Unicode sprite library

Files under `sprites/**/*.yaml` define globally unique sprite IDs. Entities add
`sprite` and `animation` (default `idle`); terrain definitions optionally add
`sprite` for top patterns and `side_sprite` for side patterns.

```yaml
schema_version: 2
id: actor.simple
name: Simple actor
width: 3
height: 3
anchor_x: 1
anchor_y: 2
default_direction: S
palette:
  h: {glyph: o, foreground: '#e8bb87'}
  b: {glyph: '█', foreground: '#65a6bd'}
  l: {glyph: '/', foreground: '#d6bb8b'}
  r: {glyph: '\', foreground: '#d6bb8b'}
animations:
  idle:
    loop: true
    directions:
      S:
        - duration_ms: 400
          rows: [' h ', ' b ', 'l r']
```

Rows contain **ASCII palette keys**, not raw art. Spaces are transparent. A palette
entry with glyph `' '` and a background is opaque blank paint. Foreground is
`#RRGGBB`; omitted background preserves the surface beneath. Sprite dimensions
are 1–64 in both axes and every frame matches them. The anchor lies inside the
sprite and is shared by all frames. It attaches the bottom of its symbol cell
to the surface, preventing the terrain from clipping the feet.

Supported glyphs are printable ASCII, Unicode U+2500–U+259F, and `·♣♠♥♦⚒`.
This deliberately excludes emoji, combining sequences, wide characters and
control sequences. Legacy unsupported glyphs display `?` with a warning and are
preserved on disk. Terminal font/ambiguous-width settings can still affect appearance;
Kitty's standard monospace treatment is the reference.

Animations have ID names, looping or one-shot playback, and 1–256 frames per
provided direction. Durations are 1–60000 ms. Every animation supplies the sprite's
default direction; other absent directions fall back to it without mirroring.
An `idle` animation is required. Animation state/timing is visual authoring data;
it never moves NPCs or executes game behavior. Material patterns tile in projected
character coordinates; transparent texture pixels retain the material background.
