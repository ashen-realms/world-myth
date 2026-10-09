# ADR 001: Versioned YAML with stable references

Status: accepted for Crystal MVP 0.1.

Schema version 1 uses world-wide region, terrain and entity IDs and region-scoped map IDs. Cross-project-document map references are `region/map`; a bare ID is accepted only when unambiguous. IDs match `[a-z][a-z0-9_.-]*`.

Maps use a local ASCII symbol legend, compact terrain rows, collision override rows, and sparse object instances referring to reusable world-object entities. All layers inherit explicit map dimensions. Coordinates are zero-based, top-left origin. Erasing terrain restores the map default; erasing collision restores inherited terrain passability. Extensions use a validated scalar property map; unknown structural keys are errors.
