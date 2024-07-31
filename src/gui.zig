const std = @import("std");
const wui = @import("webui");
const bf = @import("bf.zig");

// Global :/
var BF = bf.Bf(){
    .code = null,
    .allocator = undefined,
    .out_buf = undefined,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    BF.allocator = allocator;
    BF.out_buf = std.ArrayList(u8).init(allocator);
    defer BF.deinit();

    var win = wui.newWindow();
    _ = win.setRootFolder("src/ui");

    _ = win.bind("bf_exec", bfExec);
    _ = win.bind("test", testJs);
    _ = win.bind("exit", exit);

    _ = win.show("index.html");
    //wait until window exit
    wui.wait();
    wui.clean();
}

pub fn bfExec(e: wui.Event) void {
    const val = e.getStringAt(0);
    BF.code = val;

    BF.run() catch {};
    const output: [:0]const u8 = BF.out_buf.toOwnedSliceSentinel(0) catch unreachable;
    std.debug.print("{s}\n", .{output});
    e.returnString(output);
}

fn exit(_: wui.Event) void {
    std.debug.print("Bye!\n", .{});
    wui.exit();
}
fn testJs(_: wui.Event) void {
    std.debug.print("TEST\n", .{});
}
