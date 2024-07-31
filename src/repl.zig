const std = @import("std");
const bf = @import("bf.zig");
const Allocator = std.mem.Allocator;
const xorhash = @import("main.zig").xorhash;

const ReplArgs = enum(usize) {
    help = xorhash("!help"),
    load = xorhash("!load"),
    dump = xorhash("!dump"),
    exit = xorhash("!exit"),
    _, // other
};

pub fn start_repl(instance: *bf.Bf(), allocator: Allocator) !void {
    const user_in = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    // Ownership:
    // instance.code should be freed after .run() and set to null

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
                    instance.code = code;
                    try instance.run();
                    allocator.free(instance.code.?);
                    instance.code = null;
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
                //free is already deferred
                try instance.run();
                instance.code = null;
                try stdout.print("\n", .{});
            },
        }
    }
}
