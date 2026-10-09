# Development

## Toolchain and commands

The reference environment is Fedora 43 Workstation / GNOME, Crystal 1.21.1,
Shards 0.20.0, GTK 4.20.4, Libadwaita 1.8.8, GtkSourceView 5.18.0,
GObject Introspection 1.84.0, Cairo 1.18.4, Pango 1.57.1 and SQLite 3.50.2.

Install the Fedora packages listed in README, then run `make setup`. Shards
installs the locked dependencies and builds GI-Crystal. `./bin/gi-crystal` reads
the system GIR files and the local binding configuration, writing generated code
under ignored `lib/gi-crystal/src/auto`. Run it again after system-library updates.
Generated bindings are not source-controlled.

`shards build` creates `bin/world-myth` and `bin/world-myth-gtk`.
`crystal spec` and the CLI need no display and do not import GTK. A CLI-only
installation uses `shards install --frozen --skip-postinstall` and
`shards build world-myth` to avoid binding generation entirely. SQLite, libyaml,
and the Crystal compiler's normal native dependencies are still needed.

`crystal tool format --check` checks repository Crystal sources. `make check`
runs Core/CLI specs, formatting, both builds and example validation/compilation.
`make gui-check` additionally opens native windows on the current display and
runs the integration scenario against temporary data. `scripts/native_smoke.cr`
is the original minimal GTK/Adwaita/SourceView/Cairo/Pango reproduction.

## Verified bindings and limitations

Locked bindings: gtk4.cr 0.18.0, gi-crystal 0.26.0, pango.cr 0.3.1,
harfbuzz.cr 0.2.1, hugopl/libadwaita.cr commit
`32d7c7de0d0a2bd9f4c0a03011f5cebf2868c859`, crystal-sqlite3 0.24.0,
crystal-db 0.15.0. See shard.lock for the complete resolution.

Upstream sources: [gtk4.cr](https://github.com/hugopl/gtk4.cr),
[libadwaita.cr](https://github.com/hugopl/libadwaita.cr),
[gi-crystal](https://github.com/hugopl/gi-crystal), and the
[GtkSource configuration in Tijolo](https://github.com/hugopl/tijolo/tree/main/src/bindings/gtksource).

Three binding details required narrow adaptations:

1. GtkSource 5.18's AnnotationProvider methods use `annotation` as a parameter
   name. GI-Crystal 0.26.0 generates a Crystal keyword in expression position and
   formatting fails. Our local binding configuration excludes AnnotationProvider,
   which the editor does not use. Buffer, View, syntax highlighting, line numbers
   and language/style managers compile and run. Generated files from an earlier
   failed attempt can persist: move the generated `gtk_source-5` directory aside
   before regenerating with the exclusion.
2. Cairo GIR exposes a context handle but not basic Cairo drawing methods.
   `gui/native.cr` declares a small set of `cairo.h` functions through Crystal FFI
   and uses the GTK-owned context. PangoCairo uses the generated bindings. Contexts
   are never manually freed by the canvas.
3. GI-Crystal's `AsyncPatternArgPlan` boxes asynchronous callbacks without
   registering the boxes with its closure lifetime manager. The small
   `NativeDialogs` adapter explicitly retains file-dialog callbacks until
   completion. Confirmation dialogs use ordinary registered response signals.
   Native integration checks force garbage collection while these dialogs are open.

No Libadwaita or source-editor fallback was necessary on this toolchain. Other
GTK/GIR versions are unverified; diagnose binding generation before changing the
UI. If optional bindings cannot be supported on another target, use GTK4 widgets
or TextView, never a browser replacement.

GI-Crystal runs the blocking GTK application loop in an isolated execution context.
Project-wide validation/build runs in a Crystal fiber outside GTK callbacks;
results are delivered using GLib idle callbacks. Widgets stay on the GTK thread.
No HTTP/IPC service is involved.

## Engineering conventions

Keep Core free of graphical requires. Modify project schemas, validators,
serialization, compilation and format documentation together. Exercise malformed
files and unsuccessful writes, not just happy paths. Never auto-commit or modify
Git history. Keep runtime state and Axiom gameplay responsibilities out of sources.

Source edits are authoritative; typed editors make transactional source changes.
Do not silently serialize a commented document or overwrite a changed disk file.
Every exposed GUI action should perform a real operation. Native rendering must
remain bounded by visible cells; do not allocate a widget for each map tile.

The SQLite schema is internal and versioned. Future schema changes must bump the
artifact version rather than silently changing reader expectations. Procedural
creation is only an architectural boundary, described in architecture.md.

## Real input checks

`scripts/input_check.cr` uses Crystal FFI to X11/XTest only as a test driver. It
sends actual pointer/button/key events to native GTK widgets, checks model effects,
and deletes its temporary project. It requires `libX11-devel`, `libXtst-devel`
and an X11 display. For reliable isolation on GNOME/Wayland, use Xvfb rather than
sending synthetic input into the user's active desktop:

```sh
sudo dnf install libX11-devel libXtst-devel xorg-x11-server-Xvfb
Xvfb :97 -screen 0 1600x1000x24 -nolisten tcp &
DISPLAY=:97 make input-check
```

The input test disables portals using `GDK_DEBUG=no-portals` so it can select
paths in in-process native file dialogs. Normal application runs retain desktop
portal support. GTK marks the test driver's FileChooserDialog inspection APIs
deprecated; the application uses FileDialog. The application also runs directly
on Wayland. XTest is a test-only
dependency and is never linked into the GUI or CLI executables. GUI test scripts
use temporary configuration as well as temporary world files.

## Terminal Preview

The Preview button/F7 needs Kitty (`sudo dnf install kitty`) and the compiled
`world-myth` CLI beside the GUI binary or on PATH. The launcher currently supports
Kitty only; `world-myth preview PATH --map REGION/MAP` can be used directly in
another ANSI/truecolor Linux terminal. CLI preview uses Linux `TIOCGWINSZ` and
Crystal raw console mode, restores the terminal on normal exit/errors, and handles
resizes, arrow/WASD panning, Q/Esc/Ctrl+C exit. It requires an interactive TTY.
All preview sources must validate. Glyph appearance and unusual multi-codepoint
cluster widths depend on the terminal/font; cells reserve two terminal columns.

`make preview-check` launches real GTK and Kitty windows with a disposable project
and isolated Kitty configuration. The test enables a private Unix control socket
for that Kitty instance only, inspects its rendered text, sends input, and checks
unsaved source preview and snapshot cleanup. It requires a graphical display and
Kitty. Production Preview does not enable remote control or any network service.
