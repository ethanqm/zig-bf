const std = @import("std");
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const Allocator = std.mem.Allocator;

pub const Config = struct {
    mem: ?[]u8,
    code: ?[]const u8,
    file: ?std.fs.File,
    repl: bool = false,
};

pub fn Bf() type {
    return struct {
        const Self = @This();
        mem: [256]u8 = .{0} ** 256,
        ptr: usize = 0,
        code: ?[]const u8,
        allocator: Allocator,
        out_buf: std.ArrayList(u8),
        file: ?std.fs.File = std.io.getStdOut(),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .out_buf = std.ArrayList(u8).init(allocator),
                .code = null,
            };
        }
        pub fn deinit(self: *Self) void {
            self.out_buf.deinit();
        }

        pub fn run(self: *Self) !void {
            var stack = std.ArrayList(usize).init(self.allocator);
            defer stack.deinit();
            var i: usize = 0;
            execute: while (i < self.code.?.len) : (i += 1) {
                const tok = self.code.?[i];
                switch (tok) {
                    '+' => {
                        self.mem[self.ptr] +%= 1;
                    },
                    '-' => {
                        self.mem[self.ptr] -%= 1;
                    },
                    '[' => {
                        if (self.mem[self.ptr] != 0) {
                            // store beginning of loop
                            stack.append(i) catch |err| switch (err) {
                                error.OutOfMemory => {
                                    std.debug.print("Out of stack for loops\n", .{});
                                },
                            };
                        } else {
                            // skip to next ']'
                            while (i < self.code.?.len) {
                                if (self.code.?[i] != ']') {
                                    i += 1;
                                } else {
                                    // ']' found!
                                    // increment PAST ']'
                                    i += 1;
                                    continue :execute;
                                }
                            }
                            // reached end without finding matching ']'
                            return error.NoMatchingParen;
                        }
                    },
                    ']' => {
                        if (self.mem[self.ptr] == 0) {
                            // remove previous '[' index
                            _ = stack.pop();
                        } else {
                            // move back to previous '['
                            i = stack.getLast();
                        }
                    },
                    ',' => {
                        self.mem[self.ptr] = try std.io.getStdIn().reader().readByte();
                    },
                    '.' => {
                        try self.out_buf.append(self.mem[self.ptr]);
                        if (self.file) |file| {
                            try file.writer().print("{c}", .{self.mem[self.ptr]});
                        }
                    },
                    '>' => {
                        self.ptr = @mod(self.ptr + 1, self.mem.len);
                    },
                    '<' => {
                        self.ptr = @mod(self.ptr - 1, self.mem.len);
                    },
                    else => {},
                }
            }
            // stack contains an unmatched '[' index
            if (stack.items.len > 0) {
                return error.NoMatchingParen;
            }
        }
        pub fn mem_dump(self: *Self) !void {
            for (self.mem) |cell| {
                std.debug.print("{},", .{cell});
            }
        }
    };
}

test "hello world test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const hw_string = "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.";
    var a = Bf().init(allocator);
    defer a.deinit();
    a.code = hw_string;
    try a.run();
}

test "no loop test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // ASCII 33, 10 : !\n
    const code = "+++++++++++++++++++++++++++++++++.>++++++++++.";
    var a = Bf().init(allocator);
    defer a.deinit();
    a.code = code;
    try a.run();
    try std.testing.expectEqual(33, a.mem[0]);
    try std.testing.expectEqual(10, a.mem[1]);
}

test "comment test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const code = "Irrelevant Text1234567890!@#$%^&*()_={}|/?;:'\u{2764}++++++++++.";
    var a = Bf().init(allocator);
    defer a.deinit();
    a.code = code;
    try a.run();
    try std.testing.expectEqual(10, a.mem[0]);
}

test "no closing paren: skip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const code = "++++++++++.[";
    var a = Bf().init(allocator);
    defer a.deinit();
    a.code = code;
    try expectError(error.NoMatchingParen, a.run());
    try std.testing.expectEqual(10, a.mem[0]);
}

test "no closing paren: enter" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const code = "+[+++++++++.";
    var a = Bf().init(allocator);
    defer a.deinit();
    a.code = code;
    try expectError(error.NoMatchingParen, a.run());
}

test "code switching" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // !
    const code = "+++++++++++++++++++++++++++++++++.";
    // \n
    const code2 = ">++++++++++.";
    var a = Bf().init(allocator);
    defer a.deinit();
    a.code = code;
    try a.run();
    a.code = code2;
    try a.run();
    try std.testing.expectEqual(33, a.mem[0]);
    try std.testing.expectEqual(10, a.mem[1]);
}

test "run Hello, File! from file" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_file = try std.fs.cwd().openFile("testhf.bf", .{});
    defer test_file.close();

    const code = try test_file.readToEndAlloc(allocator, 0xFFFFFFFF);
    defer allocator.free(code);

    var a = Bf().init(allocator);
    defer a.deinit();
    a.code = code;
    try a.run();
}

test "input & output file test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_file = try std.fs.cwd().openFile("testhf.bf", .{});
    defer test_file.close();

    const code = try test_file.readToEndAlloc(allocator, 0xFFFFFFFF);
    defer allocator.free(code);

    const out_file = try std.fs.cwd().createFile("output.test.txt", .{});
    defer out_file.close();

    var a = Bf().init(allocator);
    defer a.deinit();
    a.code = code;
    a.file = out_file;
    try a.run();
}
