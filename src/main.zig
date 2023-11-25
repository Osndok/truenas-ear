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
    lock,
    unlock,
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
        .lock => lock(dataset),
        .unlock => unlock(dataset),
        .@"is-locked" => is_locked(dataset),
        .@"is-unlocked" => is_unlocked(dataset)
    };
}

fn usage() anyerror!void {
    try err.print("usage: {s} command dataset\n", .{std.os.argv[0]});
    try err.print("where: command in (lock, unlock, is-locked, is-unlocked)\n", .{});
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
    var status = try getLockStatus(dataset);
    log.info("{s} is {!}", .{dataset, status});

    switch (status) {
        .locked => std.os.exit(0),
        .unknown => std.os.exit(1),
        .unlocked => std.os.exit(2)
    }
}

fn is_unlocked(dataset: String) !void {
    var status = try getLockStatus(dataset);
    log.info("{s} is {!}", .{dataset, status});

    switch (status) {
        .unlocked => std.os.exit(0),
        .unknown => std.os.exit(1),
        .locked => std.os.exit(2),
    }
}

fn concat(one: String, two: String) !String {
    //var b = try std.Buffer.init(allocator, one);
    //try b.append(two);
    //return b;
    var result = try allocator.alloc(u8, one.len+two.len);
    std.mem.copy(u8, result[0..], one);
    std.mem.copy(u8, result[one.len..], two);
    return result;
}

fn unlock(dataset: String) !void {
    log.info("unlock: {s}", .{dataset});

    // read password from stdin (or just have child read our stdin?)
    var process = child.init(&[_]String{
        "zfs", "load-key", dataset
    }, allocator);
    {
        process.stdin_behavior = child.StdIo.Inherit;
        process.stderr_behavior = child.StdIo.Inherit;
    }
    
    try process.spawn();
    var status = try process.wait();
    
    if (status.Exited != 0) {
        log.err("exit-status {}: zfs load-key {s}", .{status.Exited, dataset});
        return std.os.ExecveError.Unexpected;
    }

    const mountPoint = try concat("/mnt/", dataset);
    defer allocator.free(mountPoint);

    log.debug("mountPoint: {s}", .{mountPoint});
    
    // zfs load key
    // zfs mount
    // look for list of services to start, and scripts to execute: "post-mount:/some/script.sh"
}

fn lock(dataset: String) !void {
    log.info("lock: {s}", .{dataset});
    // stop services
    // wait?
    // unmount
    // unload key
}

