.PHONY: setup build test check run cli gui-check input-check preview-check isometric-check benchmark

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
	@check_root=$$(mktemp -d /tmp/world-myth-cli-check.XXXXXX) || exit 1; \
	trap 'rm -r "$$check_root"' EXIT; \
	bin/world-myth new "$$check_root/world" && \
	bin/world-myth validate "$$check_root/world" && \
	bin/world-myth build "$$check_root/world"

run:
	bin/world-myth-gtk

gui-check:
	crystal build scripts/gui_check.cr -o bin/gui-check
	bin/gui-check

input-check:
	crystal build scripts/input_check.cr -o bin/input-check
	GDK_BACKEND=x11 GDK_DEBUG=no-portals bin/input-check

preview-check: build
	crystal build scripts/preview_check.cr -o bin/preview-check
	bin/preview-check

isometric-check: build
	crystal build scripts/isometric_check.cr -o bin/isometric-check
	bin/isometric-check

benchmark:
	crystal run scripts/scene_benchmark.cr
