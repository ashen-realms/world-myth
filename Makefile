.PHONY: setup build test check run cli gui-check input-check preview-check

setup:
	shards install --frozen
	./bin/gi-crystal

build:
	shards build

cli:
	shards install --frozen --skip-postinstall
	shards build world-myth

test:
	crystal spec

check:
	crystal spec
	crystal tool format --check
	shards build
	bin/world-myth validate examples/example-world
	bin/world-myth build examples/example-world

run:
	bin/world-myth-gtk examples/example-world

gui-check:
	crystal build scripts/gui_check.cr -o bin/gui-check
	bin/gui-check

input-check:
	crystal build scripts/input_check.cr -o bin/input-check
	GDK_BACKEND=x11 GDK_DEBUG=no-portals bin/input-check

preview-check: build
	crystal build scripts/preview_check.cr -o bin/preview-check
	bin/preview-check
