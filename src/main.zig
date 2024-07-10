const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    try bw.flush();

    var arg_it = try std.process.argsWithAllocator(allocator);
    //TODO: hash the arg string so it works :p
    while (arg_it.next()) |arg| {
        switch (arg[1]) {
            'a' => {
                try stdout.print("totally handled argument: {s}\n", .{arg});
            },
            else => {
                try stdout.print("Unhandled argument '{s}'\n", .{arg});
            },
        }
    }
    try bw.flush();
}
