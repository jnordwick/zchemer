const std = @import("std");

const c = @cImport({
    @cInclude("ucontext.h");
});

pub fn getcontext(ctx: *c.ucontext_t) !void {
    var r = c.getcontext(ctx);
    if (r == -1) {
        return std.os.UnexpectedError;
    }
}

pub fn setcontext(ctx: *const c.ucontext_t) !noreturn {
    var r = c.setcontext(ctx);
    if (r == -1) {
        return std.os.UnexpectedError;
    }
    unreachable;
}

pub fn makecontext(ctx: *c.ucontext_t, func: *anyopaque, argc: c_int, argv: anytype) !void {
    var r = try @call(.auto, c.makecontext, ctx ++ func ++ argc ++ argv);
    if (r == -1) {
        if (c.errno == .NOMEM) return error.SystemResources;
        unreachable;
    }
}

pub fn swapcontext(out: *c.context_t, in: *const c.context_t) void {
    var r = c.swapcontext(out, in);
    if (r == -1) {
        if (c.errno == .NOMEM) return error.SystemResources;
        unreachable;
    }
}

const Context = struct {
    const This = @This();

    var current: ?*Context = null;

    context: c.context = undefined,
    func: *anyopaque = undefined,

    pub fn get_context(s: *This) !void {
        try getcontext(&s.context);
    }

    pub fn set_context(s: *This) !noreturn {
        var old = This.current;
        This.current = s;
        errdefer This.current = old;
        try setcontext(s.context);
        unreachable;
    }

    pub fn make_context(s: *This, stack: *anyopaque, succ: ?*Context, func: *anyopaque, args: anytype) !void {
        s.context.uc_stack = stack;
        s.context.uc_link = if (succ) succ.context else null;
        const n = @typeInfo(@TypeOf(func)).Fn.fields.len;
        try makecontext(&s.context, func, n, args);
    }

    pub fn swap_context(from: *This, to: *This) !void {
        if (This.current != from) return error.NotCurrent;
        errdefer This.current = from;
        swap_context(&from.context, &to.context);
        This.current = to;
    }
};
