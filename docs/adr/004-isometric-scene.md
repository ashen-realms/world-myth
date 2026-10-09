# ADR 004: Shared isometric glyph scene and source v2

Status: accepted for World Myth 0.2; extends ADR 001 and supersedes ADR 003's
runtime schema version while preserving its deterministic publication contract.

Keep logical world coordinates independent of character art. Ground retains the
original dense tile layer; additional named surfaces use compact rows of terrain,
height, shape and collision. Positions reference supporting surfaces rather than
an ambiguous x/y under overlapping floors. Edge walls and stepped/sloped surfaces
provide building geometry. Decorative sprites do not define physical footprints.

Use one Crystal glyph renderer for GTK and terminal Preview. Fixed isometric
projection and per-fragment depth support overlapping floors and transparent
multi-character billboards. Camera rotation is not supported. Restrict new art to
a pinned text alphabet so native and terminal cells agree. New sprite definitions
have ASCII palette-key rows, colors, anchors, directional clips and timed frames.
The native sprite editor uses the existing document/history/save mechanisms.

New source projects and runtime artifacts use schema 2. Existing v1 source is
adapted in memory and remains editable in its original representation. Migration
creates a validated separate project and requires explicit consent for comment
normalization. No consumer compatibility with Axiom is claimed. Animation is
visual playback only, not simulation or player state.
