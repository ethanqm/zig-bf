const std = @import("std");
const bf = @import("bf.zig");
const Allocator = std.mem.Allocator;

fn xorhash(s: []const u8) usize {
    var out: usize = 0;
    var i: usize = 0;
    // i don't know number theory
    // test for collisions
    while (i < s.len) : (i += 1) {
        out ^= @as(usize, s[i]);
        out *%= ~i +% 1;
        out ^= i;
    }
    return out;
}

const ClArgs = enum(usize) {
    help = xorhash("-h"),
    help_long = xorhash("--help"),
    input = xorhash("-i"),
    file = xorhash("-f"),
    output_file = xorhash("-o"),
    repl = xorhash("-r"),
    _, // other
};

fn handle_args(config: *bf.Config, allocator: Allocator) !void {
    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();

    //drop filename arg
    _ = args_it.next();
    while (args_it.next()) |arg| {
        switch (@as(ClArgs, @enumFromInt(xorhash(arg)))) {
            .help, .help_long => {
                const help_message =
                    \\-h            Display this help message
                    \\--help
                    \\-i            Paste text to execute immediately
                    \\-o            Output to file
                    \\-f            Execute file
                    \\-r            Enter REPL mode
                ;
                try std.io.getStdOut().writer().print("{s}\n", .{help_message});
                std.process.exit(0);
            },
            .input => { // paste text to run
                if (args_it.next()) |input_code| {
                    // Have to copy code out before it gets freed.
                    // This use case is not important enough to optimize.
                    // This copy keeps ownership in line with -f
                    const code_copy = try allocator.dupe(u8, input_code);
                    errdefer allocator.free(code_copy);
                    config.code = code_copy;
                } else {
                    std.debug.print("Expected BF code after -i\n", .{});
                }
            },
            .output_file => { // output file
                if (args_it.next()) |output_filepath| {
                    // config owns this file
                    const file = try std.fs.cwd().createFile(output_filepath, .{});
                    config.writer = file;
                } else {
                    std.debug.print("Expected filename to create after -o\n", .{});
                }
            },
            .file => { // input file to run
                if (args_it.next()) |input_filepath| {
                    const file_handle = try std.fs.cwd().openFile(input_filepath, .{});
                    defer file_handle.close();
                    config.code = try file_handle.readToEndAlloc(allocator, 0xFFFFFFFF);
                    errdefer allocator.free(config.code);
                } else {
                    std.debug.print("Expected filepath after -f\n", .{});
                }
            },
            .repl => {
                config.repl = true;
            },
            else => {
                std.debug.print("Unrecognised arg \"{s}\"\n", .{arg});
            },
        }
    }
}

const ReplArgs = enum(usize) {
    help = xorhash("!help"),
    load = xorhash("!load"),
    dump = xorhash("!dump"),
    exit = xorhash("!exit"),
    _, // other
};

pub fn start_repl(instance: *bf.Bf, allocator: Allocator) !void {
    const user_in = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Type !help\n", .{});
    while (true) {
        try stdout.print(">", .{});
        // delimiter 0xA = \n newline
        const input = user_in.readUntilDelimiterAlloc(allocator, 0xA, 0xFFFF) catch |err| switch (err) {
            error.EndOfStream => {
                // no longer crash on Ctrl-D
                try stdout.print("Goodbye!\n", .{});
                std.process.exit(0);
            },
            else => {
                return err;
            },
        };
        defer allocator.free(input);
        //try to recognise keyword in first position
        var words_it = std.mem.split(u8, input, " ");
        const keyword = xorhash(words_it.first());
        switch (@as(ReplArgs, @enumFromInt(keyword))) {
            .help => {
                const help_message =
                    \\!help             Display this help message
                    \\!load             Load and execute bf file
                    \\!dump             Show all memory
                    \\!exit             Exit this program
                ;
                try stdout.print("{s}\n", .{help_message});
            },
            .load => {
                if (words_it.next()) |filepath| {
                    const filehandle = try std.fs.cwd().openFile(filepath, .{});
                    defer filehandle.close();
                    const code = try filehandle.readToEndAlloc(allocator, 0xFFFFFFFF);
                    if (instance.code) |old_code| {
                        allocator.free(old_code);
                    }
                    instance.code = code;
                    try instance.run();
                } else {
                    try stdout.print("Expected filepath after !load\n", .{});
                }
            },
            .dump => {
                try instance.mem_dump();
                try stdout.print("\n", .{});
            },
            .exit => {
                try stdout.print("Goodbye!\n", .{});
                std.process.exit(0);
            },
            else => {
                //keyword not recognised, execute string as if bf code
                instance.code = input;
                try instance.run();
                try stdout.print("\n", .{});
            },
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // configure
    var config = bf.Config{
        .mem = null,
        .code = null,
        .writer = null,
        .repl = false,
    };
    defer {
        if (config.writer) |file| {
            file.close();
        }
    }

    try handle_args(&config, allocator);
    var bf_instance = bf.Bf{ .allocator = allocator, .code = config.code };
    if (config.writer) |writer| {
        bf_instance.writer = writer;
    }

    // run
    if (config.repl) {
        try start_repl(&bf_instance, allocator);
    } else {
        try bf_instance.run();
        if (config.code) |initialized_code| {
            allocator.free(initialized_code);
        }
    }
}
