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

fn handle_args(config: *bf.Config, allocator: Allocator) !void {
    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();
    //drop filename arg
    _ = args_it.next();
    while (args_it.next()) |arg| {
        switch (xorhash(arg)) {
            xorhash("-f") => { // input file to run
                if (args_it.next()) |input_filepath| {
                    const file_handle = try std.fs.cwd().openFile(input_filepath, .{});
                    defer file_handle.close();

                    config.code = try file_handle.readToEndAlloc(allocator, 0xFFFFFFFF);
                    errdefer allocator.free(config.code);
                } else {
                    std.debug.print("Expected filepath after -f\n", .{});
                }
            },
            xorhash("-i") => { // paste text to run
                if (args_it.next()) |input_code| {
                    // have to copy code out before it gets freed
                    const code_copy = try allocator.alloc(u8, input_code.len);
                    errdefer allocator.free(code_copy);
                    @memcpy(code_copy, input_code);
                    config.code = code_copy;
                } else {
                    std.debug.print("Expected BF code after -i\n", .{});
                }
            },
            else => {
                std.debug.print("Unrecognised arg \"{s}\"\n", .{arg});
            },
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    //
    var config = bf.Config{
        .mem = null,
        .code = null,
    };

    try handle_args(&config, allocator);

    var bf_instance = bf.Bf{ .allocator = allocator, .code = config.code.? };
    try bf_instance.run();
    if (config.code) |initialized_code| {
        allocator.free(initialized_code);
    }
}
