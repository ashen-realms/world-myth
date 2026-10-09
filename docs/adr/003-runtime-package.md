# ADR 003: Deterministic SQLite package

Status: accepted for Crystal MVP 0.1.

Compile a standalone SQLite schema version 1 plus manifest.json. Use relational metadata, coordinate-indexed cells, entities and placements, with canonical JSON scalar properties. No chunk storage or runtime-player tables.

Stable creation/insertion order, no timestamps, and a database SHA-256 make builds reproducible within the same Crystal/SQLite toolchain. Shards dependencies are locked; system SQLite version is documented. Validate staged output before recoverable directory replacement. Previous output survives ordinary failures. The package is an internal contract, not an Axiom integration promise.
