//!zig@0.11

const std = @import("std");
const log = std.log;
const out = std.io.getStdOut().writer();
const err = std.io.getStdErr().writer();
const child = std.process.Child;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

const Subcommand = enum {
    offer,
    @"is-locked",
    @"is-unlocked"
};

pub fn main() !void {
    const argv = std.os.argv;

    if (argv.len != 3) {
        try usage();
        std.os.exit(1);
    }

    var it = try std.process.ArgIterator.initWithAllocator(allocator);
    defer it.deinit();

    _ = it.next();

    const command = subcommand: {
        const subc_string = it.next() orelse {
            try usage();
            std.os.exit(1);
        };

        break :subcommand std.meta.stringToEnum(Subcommand, subc_string) orelse {
            try err.print("invalid command: {s}\n", .{subc_string});
            try usage();
            std.os.exit(1);
        };
    };

    const dataset = it.next().?;

    try switch (command) {
        .offer => offer(dataset),
        .@"is-locked" => is_locked(dataset),
        .@"is-unlocked" => is_unlocked(dataset)
    };
}

fn usage() anyerror!void {
    try err.print("usage: {s} command dataset\n", .{std.os.argv[0]});
    try err.print("where: command in (offer, is-locked, is-unlocked)\n", .{});
}

fn is_locked(dataset: [*:0]const u8) !void {
    log.info("is_locked?: {s}", .{dataset});
    var process = try child.exec(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "echo", "hello" }
        //.argv = &[_][]const u8{ "zfs", "get", "-H", "keystatus", dataset }
    });
    log.info("stdout is: {s}", .{process.stdout});
}

fn is_unlocked(dataset: [*:0]const u8) void {
    log.info("is_unlocked?: {s}", .{dataset});
}

fn offer(dataset: [*:0]const u8) void {
    log.info("offer: {s}", .{dataset});
}

