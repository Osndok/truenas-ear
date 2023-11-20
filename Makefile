
build:
	zig build

run: build
	zig-out/bin/truenas-ear

test: build
	zig test src/*.zig

