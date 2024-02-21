const std = @import("std");

const c = @cImport({
    @cInclude("setjmp.h");
});

pub fn kallcc(func: anytype, ud: anytype) @typeInfo(@TypeOf(func)).Fn.return_type.? {
    const Ret = @typeInfo(@TypeOf(func)).Fn.return_type.?;
    const Udata = @TypeOf(ud);

    var k: Kontinuation(Ret, Udata) = undefined;
    const r: c_int = c.setjmp(&k.env);
    if (r == 0) {
        _ = func(&k, ud);
    }
    return k.ret;
}

pub fn Kontinuation(comptime RetT: type, comptime UdataT: type) type {
    return struct {
        const Ret = RetT;
        const Udata = UdataT;
        const Func = *fn (*Kontinuation, Udata) void;

        env: c.jmp_buf,
        ret: Ret,
        n: c_int = 0,

        pub fn kallcc(s: *@This(), func: Func, ud: Udata) Ret {
            const r: c_int = c.setjmp(s.env);
            if (r == 0) {
                func(s, ud);
            }
            return s.ret;
        }

        pub fn kontinue(s: *@This(), ret: Ret) void {
            s.ret = ret;
            s.n += 1;
            c.longjump(s.env, s.n);
            noreturn;
        }
    };
}

// --- TESTING ---

fn return_num(k: anytype, ud: anytype) u32 {
    std.debug.print("\n---return num called---\n", .{});
    if (@hasDecl(@TypeOf(k), "kontinue")) {
        @call(.always_inline, k.kontinue, .{ k, 2 });
    } else if (@typeInfo(@TypeOf(k)) == .Fn) {
        return @call(.auto, k, .{ud});
    }
    std.debug.print("\n---return num returning---\n", .{});
    return 3;
}

test {
    const r = kallcc(return_num, void);
    std.debug.print("\n--- done --- {}", .{r});
}
