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

// When deployed, we have to specify the full path, because 'sbin' will not be in our path.
const ZFS_SBIN = "/usr/sbin/zfs";

// In development, there is no sbin/zfs, so we use the kludge that the dev puts in our path.
const ZFS_IN_PATH = "zfs";


const Subcommand = enum
{
    lock,
    unlock,
    @"is-locked",
    @"is-unlocked"
};

pub fn main() !void
{
    const argv : []CString = std.os.argv;

    if (argv.len != 3)
    {
        try usage();
        std.os.exit(1);
    }

    var it = try std.process.ArgIterator.initWithAllocator(allocator);
    defer it.deinit();

    _ = it.next();

    const command = subcommand: {
        const subc_string = it.next()
        orelse
        {
            try usage();
            std.os.exit(1);
        };

        break :subcommand std.meta.stringToEnum(Subcommand, subc_string)
        orelse
        {
            try err.print("invalid command: {s}\n", .{subc_string});
            try usage();
            std.os.exit(1);
        };
    };
   
    const dataset = cstringToString(it.next().?);

    try switch (command)
    {
        .lock => lock(dataset),
        .unlock => unlock(dataset),
        .@"is-locked" => is_locked(dataset),
        .@"is-unlocked" => is_unlocked(dataset)
    };
}

fn usage() anyerror!void
{
    try err.print("usage: {s} command dataset\n", .{std.os.argv[0]});
    try err.print("where: command in (lock, unlock, is-locked, is-unlocked)\n", .{});
}

fn cstringToString(input: CString) String
{
    var length = std.mem.len(input);
    return input[0..length];
}

fn run(argv: []const String) !String
{
    var process = try child.exec(.{
        .allocator = allocator,
        .argv = argv
    });

    if (process.term.Exited != 0)
    {
        log.err("process returned exit status {}: {any}\n{s}", .{process.term.Exited, argv, process.stderr});
        return std.os.ExecveError.Unexpected;
    }

    // ???: need to dealloc captured stdout & stderr?

    return process.stdout;
}

const LockStatus = enum
{
    locked,
    unlocked,
    unknown
};

fn getLockStatus(dataset: String) !LockStatus
{
    var line = try run(&[_]String {
        zfs(), "get", "-H", "keystatus", dataset
    });

    const tab = std.mem.indexOf(u8, line, "\t") orelse return LockStatus.unknown;
    const afterTab = line[tab+1..];
    const tab2 = std.mem.indexOf(u8, afterTab, "\t") orelse return LockStatus.unknown;

    const statusEtc = afterTab[tab2+1..];
    log.debug("statusEtc = {s}", .{statusEtc});

    if (std.mem.startsWith(u8, statusEtc, "unavailable"))
    {
        return LockStatus.locked;
    }

    if (std.mem.startsWith(u8, statusEtc, "available"))
    {
        return LockStatus.unlocked;
    }

    return LockStatus.unknown;
}

fn is_locked(dataset: String) !void
{
    var status = try getLockStatus(dataset);
    log.info("{s} is {!}", .{dataset, status});

    switch (status)
    {
        .locked => std.os.exit(0),
        .unknown => std.os.exit(1),
        .unlocked => std.os.exit(2)
    }
}

fn is_unlocked(dataset: String) !void
{
    var status = try getLockStatus(dataset);
    log.info("{s} is {!}", .{dataset, status});

    switch (status)
    {
        .unlocked => std.os.exit(0),
        .unknown => std.os.exit(1),
        .locked => std.os.exit(2),
    }
}

fn concat(one: String, two: String) !String
{
    //var b = try std.Buffer.init(allocator, one);
    //try b.append(two);
    //return b;
    var result = try allocator.alloc(u8, one.len+two.len);
    std.mem.copy(u8, result[0..], one);
    std.mem.copy(u8, result[one.len..], two);
    return result;
}

fn zfs_load_key(dataset: String) !void
{
    var process = child.init(&[_]String{
        zfs(), "load-key", dataset
    }, allocator);
    {
        process.stdin_behavior = child.StdIo.Inherit;
        process.stdout_behavior = child.StdIo.Inherit;
        process.stderr_behavior = child.StdIo.Inherit;
    }
    
    try process.spawn();
    var status = try process.wait();
    
    if (status.Exited != 0)
    {
        log.err("exit-status {}: zfs load-key {s}", .{status.Exited, dataset});
        return std.os.ExecveError.Unexpected;
    }
    //???: process.deinit();
}

fn zfs_mount(dataset: String) !void
{
    var process = child.init(&[_]String{
        zfs(), "mount", dataset
    }, allocator);
    {
        process.stdin_behavior = child.StdIo.Ignore;
        process.stdout_behavior = child.StdIo.Inherit;
        process.stderr_behavior = child.StdIo.Inherit;
    }
    
    try process.spawn();
    var status = try process.wait();
    
    if (status.Exited != 0)
    {
        log.warn("exit-status {}: zfs mount {s}", .{status.Exited, dataset});
    }
    //???: process.deinit();
}

fn do_post_unlock_followups(dataset: String) !void
{

    // NB: Assuming '/mnt/' prefix (TrueNAS)
    const mountPoint = try concat("/mnt/", dataset);
    defer allocator.free(mountPoint);

    log.debug("mountPoint: {s}", .{mountPoint});

    const followUpFile = try concat(mountPoint, "/.truenas-ear");
    defer allocator.free(followUpFile);

    log.debug("followUpFile: {s}", .{followUpFile});

    // look for list of services to start, and scripts to execute: "post-mount:/some/script.sh"
    var file = std.fs.cwd().openFile(followUpFile, .{})
    catch
    {
        log.info("dne: {s}", .{followUpFile});
        return;
    };
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();
    var buf: [2048]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line|
    {
        if (line.len == 0 or line[0] == '#' )
        {
            continue;
        }

        handle_post_unlock_followup_line(dataset, mountPoint, line)
        catch |e|
        {
            log.err("{s}: {!}", .{line, e});
        };
    }
}

fn handle_post_unlock_followup_line(dataset: String, mountPoint: String, line: String) !void
{
    //log.debug("handle_post_unlock_followup_line: {s}, {s}", .{dataset, line});
    
    const colon = std.mem.indexOf(u8, line, ":")
    orelse 
    {
        start_service(line)
        catch |e|
        {
            log.err("start_service: {s}: {!}", .{line, e});
        };
        return;
    };

    const before_colon = line[0..colon];

    if (!std.mem.eql(u8, before_colon, "post-mount"))
    {
        log.debug("ignore: {s}", .{line});
        return;
    }

    const after_colon = line[colon+1..];
    log.debug("after_colon: {s}", .{after_colon});

    try exec_user_shell_line(dataset, mountPoint, after_colon);
}

fn start_service(service_name: String) !void
{
    log.info("start_service: {s}", .{service_name});

    var process = child.init(&[_]String{
        "midclt", "call", "chart.release.scale", service_name, "{\"replica_count\": 1}"
    }, allocator);
    {
        process.stdin_behavior = child.StdIo.Ignore;
        process.stdout_behavior = child.StdIo.Inherit;
        process.stderr_behavior = child.StdIo.Inherit;
    }

    // NB: This (or one of the next lines) will throw 'error.FileNotFound' if midclt is not present.
    try process.spawn();
    var status = try process.wait();
    
    if (status.Exited != 0)
    {
        log.err("unable to start {s} service, midclt exit status {}", .{service_name, status.Exited});
    }
    //???: process.deinit();
}

fn exec_user_shell_line(dataset: String, mountPoint: String, shell_line: String) !void
{
    log.info("exec_user_shell_line: {s}, {s}, {s}", .{dataset, mountPoint, shell_line});

    // TODO: set "TRUENAS_EAR_DATASET" env var to 'dataset'
    // TODO: set pwd to 'mountPoint'
    var process = child.init(&[_]String{
        "bash", "-c", shell_line
    }, allocator);
    {
        process.stdin_behavior = child.StdIo.Ignore;
        process.stdout_behavior = child.StdIo.Inherit;
        process.stderr_behavior = child.StdIo.Inherit;
    }

    // NB: This (or one of the next lines) will throw 'error.FileNotFound' if midclt is not present.
    try process.spawn();
    var status = try process.wait();
    
    if (status.Exited != 0)
    {
        log.err("exist status {} from shell script line: {s}", .{status.Exited, shell_line});
    }
    //???: process.deinit();
}

fn fileExists(path: String) !bool {
    const file = std.fs.cwd().openFile(path, .{}) catch |e| switch (e) {
        error.FileNotFound => return false,
        else => return e,
    };

    file.close();

    return true;
}

test "fileExists()" {
    try std.testing.expect(try fileExists("/"));
    try std.testing.expect(!try fileExists("/this-is-a-file-name-which-really-should-not-exist"));
}

fn zfs() String {
    const exists = fileExists(ZFS_SBIN) catch { return ZFS_IN_PATH; };

    if (exists)
    {
        return ZFS_SBIN;
    }
    else
    {
        return ZFS_IN_PATH;
    }
}

fn unlock(dataset: String) !void
{
    log.info("unlock: {s}", .{dataset});

    try zfs_load_key(dataset);
    try zfs_mount(dataset);
    try do_post_unlock_followups(dataset);
    // ??? Wait for kubernetes to reach a stable state?
}

fn lock(dataset: String) !void
{
    log.info("lock: {s}", .{dataset});
    // stop services
    // wait?
    // unmount
    // unload key
}

