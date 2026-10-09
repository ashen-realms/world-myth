# ADR 002: One source document and explicit normalization

Status: accepted for Crystal MVP 0.1.

Crystal Core owns source text, typed projections, revisions, disk fingerprints and up to 100 history transactions per open document. Source and visual changes share this history. Invalid YAML disables visual editing without losing text.

Raw source saves preserve text. Before visual editing of commented or serialization-sensitive YAML, the user must explicitly review and accept normalization. Normalization is undoable and warns of comment loss. CLI fmt skips sensitive files unless `--allow-comment-loss` is provided. Unsupported YAML constructs remain source-only.

Save checks the disk hash and atomically replaces a file. Conflicts never force overwrite: reload with explicit discard or save a copy. Validation sees unsaved buffers; build uses saved files after Save All.
