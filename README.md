# World Myth

Offline world authoring tools in Crystal. YAML and Markdown are the source of
truth; validated worlds compile to a standalone SQLite runtime artifact.

```sh
shards install --frozen --skip-postinstall
shards build
crystal spec
bin/world-myth new my-world
bin/world-myth validate examples/example-world
bin/world-myth build examples/example-world
bin/world-myth fmt my-world --check
```

Requires Crystal 1.21.1+, Shards, SQLite and libyaml development libraries.
Core has no graphical dependencies. Source edits preserve original text until
explicit normalization; saves detect external changes. Generated artifacts are
ignored by Git, and failed builds preserve the previous valid artifact.

See [world format](docs/world-format.md), [compilation](docs/compilation.md), and
[design decisions](docs/adr/001-world-format.md). Apache-2.0; see [LICENSE](LICENSE).
