const std = @import("std");

pub fn Range(start: anytype, endx: @TypeOf(start)) type {
    const T = RangeIter(@TypeOf(start));
    return T.init(start, endx);
}

pub fn Slice(sl: anytype) type {
    const T = SliceIter(SliceOf(sl));
    return T.init(sl);
}

pub fn AnyFunc(func: anytype, ud: anyopaque) type {
    const T = FuncIter(ReturnType(func)).?;
    return T.inint(func, ud);
}

pub fn Sink(comptime DerivT: type, comptime InT: type, comptime OutT: type) type {
    return struct {
        pub const Source = DerivT;
        pub const In = InT;
        pub const Out = OutT;

        pub fn sink_copy(s: DerivT) Out {
            var copy = s;
            return copy.sink();
        }
    };
}

pub fn Iter(comptime DerivT: type, comptime InT: type, comptime OutT: type) type {
    return struct {
        pub const Source = DerivT;
        pub const In = InT;
        pub const Out = OutT;

        // converters
        pub fn filter(s: DerivT, pred: FilterFunc(Out)) FilterIter(DerivT) {
            return .{ .src = s, .func = pred };
        }

        pub fn map(s: DerivT, comptime f: anytype) MapIter(DerivT, ReturnTypeFn(f)) {
            return .{ .src = s, .func = f };
        }

        // sinks
        pub fn reduce(s: DerivT, comptime f: anytype, initial: ReturnTypeFn(f)) ReduceSink(DerivT, ReturnTypeFn(f)) {
            return .{ .src = s, .func = f, .initial = initial };
        }

        pub fn collect(s: DerivT, comptime f: anytype, u: anytype) CollectSink(DerivT, @TypeOf(f), @TypeOf(u)) {
            return .{ .src = s, .func = f, .u = u };
        }

        pub fn append_to(s: DerivT, a: *std.ArrayList(In)) void {
            s.collect(&appender, a);
        }
    };
}

pub fn SliceIter(comptime Element: type) type {
    return struct {
        const B = Iter(@This(), void, Element);
        pub usingnamespace B;

        slice: *[]B.Out,
        pos: usize,

        pub fn init(sl: *[]B.Out) @This() {
            return .{ .slice = sl, .pos = 0 };
        }

        pub fn next(s: *@This()) ?B.Out {
            if (s.pos >= s.slice.len)
                return null;
            const n = s.pos;
            s.pos += 1;
            return s.slice[n];
        }
    };
}

pub fn RangeIter(comptime T: type) type {
    return struct {
        const B = Iter(@This(), void, T);
        pub usingnamespace B;

        nextx: B.Out,
        end: B.Out,

        pub fn init(start: B.out, end: B.out) @This() {
            return .{ .nextx = start, .end = end };
        }

        pub fn next(s: *@This()) ?B.Out {
            if (s.nextx == s.end)
                return null;
            const n = s.nextx;
            s.nextx += 1;
            return n;
        }
    };
}

fn FuncFunc(comptime OT: type) type {
    return fn (anyopaque) ?OT;
}

pub fn FuncIter(comptime T: type) type {
    return struct {
        const B = Iter(@This(), void, T);
        pub usingnamespace B;

        const Func = FuncFunc(B.Out);

        func: Func,
        ud: anyopaque,

        pub fn init(func: Func, ud: anyopaque) @This() {
            return .{ .func = func, .ud = ud };
        }

        pub fn next(s: *@This()) ?B.Out {
            return s.func(s.ud);
        }
    };
}

fn FilterFunc(comptime T: type) type {
    return *const fn (x: T) bool;
}

pub fn FilterIter(comptime SourceT: type) type {
    return struct {
        const B = Iter(@This(), SourceT.Out, SourceT.Out);
        pub usingnamespace B;

        pub const Func = FilterFunc(B.In);

        src: SourceT,
        func: Func,

        pub fn next(s: *@This()) ?B.Out {
            var t = s.src.next();
            while (t != null and !s.func(t.?)) {
                t = s.src.next();
            }
            return t;
        }
    };
}

fn MapFunc(comptime IT: type, comptime RT: type) type {
    return *const fn (x: IT) RT;
}

pub fn MapIter(comptime SourceT: type, comptime ReturnT: type) type {
    return struct {
        const B = Iter(@This(), SourceT.Out, ReturnT);
        pub usingnamespace B;
        pub const Func = MapFunc(B.In, B.Out);

        src: SourceT,
        func: Func,

        pub fn next(s: *@This()) ?B.Out {
            if (s.src.next()) |v| {
                return s.func(v);
            }
            return null;
        }
    };
}

pub fn EachPairIter(comptime SourceT: type) type {
    return struct {
        const B = Iter(@This(), SourceT.Out, [2]SourceT.Out);
        pub usingnamespace B;

        src: SourceT,
        last: B.In,

        pub fn next(s: *@This()) ?B.Out {
            if (s.src.next()) |v| {
                const r = s.last;
                s.last = v;
                return .{ r, v };
            }
            return null;
        }
    };
}

pub fn ByPairsIter(comptime SourceT: type) type {
    return struct {
        const B = Iter(@This(), SourceT.Out, [2]SourceT.Out);
        pub usingnamespace B;

        src: SourceT,

        pub fn next(s: *@This()) ?B.Out {
            if (s.src.next()) |v| {
                if (s.src.next()) |w| {
                    return .{ v, w };
                }
            }
            return null;
        }
    };
}

fn ReduceFunc(comptime IT: type, comptime RT: type) type {
    return *const fn (x: IT, prev: RT) RT;
}

pub fn ReduceSink(comptime SourceT: type, comptime ReturnT: type) type {
    return struct {
        const B = Sink(@This(), SourceT.Out, ReturnT);
        pub usingnamespace B;
        pub const Func = ReduceFunc(B.Out, ReturnT);

        src: SourceT,
        func: Func,
        initial: B.Out,

        pub fn sink(s: *@This()) B.Out {
            while (s.src.next()) |x| {
                s.initial = s.func(x, s.initial);
            }
            return s.initial;
        }
    };
}

fn CollectFunc(comptime IT: type) type {
    return *const fn (x: IT, c: anytype) void;
}

pub fn CollectSink(comptime SourceT: type, comptime funcT: type, comptime outT: type) type {
    return struct {
        const B = Sink(@This(), SourceT.Out, void);
        pub usingnamespace B;

        src: SourceT,
        f: funcT,
        u: outT,

        pub fn sink(s: *@This(), f: anytype, u: anytype) void {
            while (s.src.next()) |x| {
                f(x, u);
            }
        }
    };
}

fn ReturnTypeFn(comptime func: anytype) type {
    return ReturnType(@TypeOf(func));
}

fn ReturnType(comptime Func: type) type {
    switch (@typeInfo(Func)) {
        .Fn => |x| return x.return_type.?,
        .Pointer => |x| return ReturnType(x.child),
        else => @compileError("error: must be a function"),
    }
}

fn SliceOfVal(comptime sl: anytype) type {
    return SliceOf(@TypeOf(sl));
}

fn SliceOf(comptime Sl: type) type {
    switch (@typeInfo(Sl)) {
        .Array => |x| return x.child,
        .Pointer => |x| return SliceOf(x.child),
        else => @compileError("error: must be an array"),
    }
}

fn appender(x: anytype, a: *std.ArrayList(@TypeOf(x))) void {
    a.append(x) catch @panic("nope");
}

fn filtfn(x: i64) bool {
    return @mod(x, 11) == 0;
}

fn mapfn(x: i64) i64 {
    return (-x) * 2;
}

fn sum(x: i64, i: i64) i64 {
    return x + i;
}

test "appending" {
    //pub fn main() void {
    //var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    //const gpa = general_purpose_allocator.allocator();
    //var arr = std.ArrayList(i64).init(gpa);
    //_ = arr;

    var r = Range(@as(i64, 1), 25).filter(&filtfn).map(&mapfn).reduce(&sum, 0);
    var s = r.sink();
    //var rr = r.sink(); // Shoud work without the extra copy
    try std.testing.expectEqual(s, -66);

    // try std.testing.expectEqual(@as(usize, 2), arr.items.len);
    // try std.testing.expectEqual(@as(i64, 11), arr.items[0]);
    // try std.testing.expectEqual(@as(i64, 22), arr.items[1]);
}
