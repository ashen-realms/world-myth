# World source format 1

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

All structured documents require `schema_version: 1`. Unknown structural fields
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
