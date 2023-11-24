
build:
	zig build

run: build
	zig-out/bin/truenas-ear

test: build
	zig test src/*.zig

deploy: build
	sudo chmod u+s zig-out/bin/truenas-ear
	scp zig-out/bin/truenas-ear nas1:/mnt/main/
