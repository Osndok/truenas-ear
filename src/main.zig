//!zig@0.11

const std = @import("std");
const log = std.log;
const out = std.io.getStdOut().writer();
const err = std.io.getStdErr().writer();
const child = std.process.Child;

const String = []const u8;
const CString = [*:0]const u8;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

const Subcommand = enum {
    offer,
    @"is-locked",
    @"is-unlocked"
};

pub fn main() !void {
    const argv : []CString = std.os.argv;

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
   
    const dataset = cstringToString(it.next().?);

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

fn cstringToString(input: CString) String {
    var length = std.mem.len(input);
    return input[0..length];
}

fn run(argv: []const String) !String {
    var process = try child.exec(.{
        .allocator = allocator,
        .argv = argv
    });

    if (process.term.Exited != 0) {
        log.err("process returned exit status {}: {any}\n{s}", .{process.term.Exited, argv, process.stderr});
        return std.os.ExecveError.Unexpected;
    }

    return process.stdout;
}

const LockStatus = enum {
    locked,
    unlocked,
    unknown
};

fn getLockStatus(dataset: String) !LockStatus {
    var line = try run(&[_]String {
        "zfs", "get", "-H", "keystatus", dataset
    });

    const tab = std.mem.indexOf(u8, line, "\t") orelse return LockStatus.unknown;
    const afterTab = line[tab+1..];
    const tab2 = std.mem.indexOf(u8, afterTab, "\t") orelse return LockStatus.unknown;

    const statusEtc = afterTab[tab2+1..];
    log.debug("statusEtc = {s}", .{statusEtc});

    if (std.mem.startsWith(u8, statusEtc, "unavailable")) {
        return LockStatus.locked;
    }

    if (std.mem.startsWith(u8, statusEtc, "available")) {
        return LockStatus.unlocked;
    }

    return LockStatus.unknown;
}

fn is_locked(dataset: String) !void {
    log.info("is_locked?: {s}", .{dataset});

    var status = try getLockStatus(dataset);
    log.info("{s} is {!}", .{dataset, status});

    switch (status) {
        .locked => std.os.exit(0),
        .unknown => std.os.exit(1),
        .unlocked => std.os.exit(2)
    }
}

fn is_unlocked(dataset: String) !void {
    log.info("is_unlocked?: {s}", .{dataset});

    var status = try getLockStatus(dataset);
    log.info("{s} is {!}", .{dataset, status});

    switch (status) {
        .unlocked => std.os.exit(0),
        .unknown => std.os.exit(1),
        .locked => std.os.exit(2),
    }
}

fn offer(dataset: String) !void {
    log.info("offer: {s}", .{dataset});
}

