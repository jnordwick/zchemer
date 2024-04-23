const std = @import("std");

/// A wrapper function around creating a RangeIter and calling its init.
///
/// see: RangeIter
pub fn Range(start: anytype, end: @TypeOf(start)) RangeIter(@TypeOf(start)) {
    return .{ .nextx = start, .end = end };
}

/// A wrapper function around creating a SliceIter and calling its init.
///
/// see: SliceIter
pub fn Slice(sl: anytype) SliceIter(@TypeOf(sl)) {
    return .{ .slice = sl, .pos = 0 };
}

/// Iterates over a slice retuning a slice of `stride` elements at a
/// time. It uses pointer arithmatic to produce slices of them same
/// type as sl.
/// stride: The size of the reutrned subslice in elements not bytes.
/// The final succcessful return may have fewer.
pub fn Strided(sl: anytype, stride: u32) StridedIter(@TypeOf(sl)) {
    return .{ .ptr = sl.ptr, .end = sl.ptr + sl.len, .stride = stride };
}

/// A wrapper function around create an AnyFuncIter and calling its init.
///
/// see: AnyFuncIter
pub fn AnyFunc(func: anytype, ud: anyopaque) type {
    const T = FuncIter(ReturnType(func)).?;
    return T.inint(func, ud);
}

/// The base type of all sink types.
///
/// Sink types exectute the built up lazy chain of iterators. Wihtout a sink,
/// nothing gets executed. They return a value and represent the end of the
/// computation. Sinks accept all values from the chain, but they only produce
/// a single value.
///
/// DerivT: The derived type that will include this.
/// InT: The type that the sink will accept in each iteration.
/// OutT: The type that the sink will produce.
pub fn Sink(comptime DerivT: type, comptime InT: type, comptime OutT: type) type {
    return struct {
        pub const Source = DerivT;
        pub const In = InT;
        pub const Out = OutT;

        /// A covenience method that returns makes a cpoy of the iterator chain
        /// instance, calls its sink method, then returns tha value from it. On
        /// iterators that need to keep state, since Zig's arguments are const
        /// it cannot use the temporary passed into it and needs to give me a
        /// named memory address (variable binding).
        pub fn sink_copy(s: DerivT) Out {
            var copy = s;
            return copy.sink();
        }
    };
}

/// The base of all source and intermediate iterators - anything that
/// iteratively produces values.
///
/// This contains a function for each iterator type that simply returns
/// the appropriate struct. Each iterator that implements this uses
/// usingnamespace to pull in these functions and then can be called
/// again to generate the next iterator in the chain. This continues
/// until a Sink it called that will receive all the values. their
/// functions into each othter. At runtime, this results is a single
/// type instantiated on the stack, and it recursively contains all
/// the other step types. There is no runtime memory allocation, and
/// values are produced lazily. These are described as pull iterators
/// in that the sink dries the computation by pulling values.
///
/// DerivT: The derived type using this type.
/// InT: The type the iterator receives fro the previous step. For
/// source iterators, this should be void.
/// OutT: The type the interator produces.
pub fn Iter(comptime DerivT: type, comptime InT: type, comptime OutT: type) type {
    return struct {
        pub const Source = DerivT;
        pub const In = InT;
        pub const Out = OutT;

        // converters
        /// see: FilterIter
        pub fn filter(s: DerivT, pred: anytype) FilterIter(DerivT) {
            return .{ .src = s, .func = pred };
        }

        /// see: MapIter
        pub fn map(s: DerivT, f: anytype) MapIter(DerivT, ReturnTypeFn(f)) {
            return .{ .src = s, .func = f };
        }

        /// see: TakeIter
        pub fn take(s: DerivT, amt: u32) TakeIter(DerivT) {
            std.debug.assert(amt > 0);
            return .{ .src = s, .take = amt };
        }

        /// see: DropIter
        pub fn drop(s: DerivT, amt: u32) DropIter(DerivT) {
            return .{ .src = s, .amt = amt };
        }

        pub fn to_vec(s: DerivT, comptime dim: u32, fill: anytype) ToVecIter(DerivT, dim) {
            return .{ .src = s, .fill = @splat(fill) };
        }

        // sinks

        /// see: ReduceSink
        pub fn reduce(
            s: DerivT,
            comptime f: anytype,
            initial: ReturnTypeFn(f),
        ) ReduceSink(DerivT, ReturnTypeFn(f)) {
            return .{ .src = s, .func = f, .initial = initial };
        }

        /// see: CollectSink
        pub fn collect(s: DerivT, f: anytype, u: anytype) CollectSink(DerivT, @TypeOf(f), @TypeOf(u)) {
            return .{ .src = s, .func = f, .u = u };
        }

        /// helper function that creates a collect sink that appends to an ArrayList.
        /// see: CollectSink
        pub fn append_to(s: DerivT, a: *std.ArrayList(In)) void {
            s.collect(&appender, a);
        }
    };
}

/// Source iterator that returns each element of
/// a slice in turn.
pub fn SliceIter(comptime SliceT: type) type {
    return struct {
        const C = @typeInfo(SliceT).Pointer.child;
        const B = Iter(@This(), void, C);
        pub usingnamespace B;

        slice: SliceT,
        pos: usize = 0,

        pub inline fn next(s: *@This()) ?B.Out {
            if (s.pos >= s.slice.len)
                return null;
            const n = s.pos;
            s.pos += 1;
            return s.slice[n];
        }
    };
}

pub fn StridedIter(comptime SliceT: type) type {
    return struct {
        const B = Iter(@This(), void, SliceT);
        pub usingnamespace B;

        const Pointer = @typeInfo(B.Out).Pointer;
        const item_size = @sizeOf(Pointer.child);

        ptr: Pointer,
        end: Pointer,
        stride: u32,

        pub fn init(sl: B.Out, stride: u32) @This() {
            return .{ .ptr = sl.ptr, .end = sl.ptr + sl.len, .stride = stride };
        }

        pub inline fn next(s: *@This()) ?B.Out {
            const ptr_int: usize = @intFromPtr(s.ptr);
            const end_int: usize = @intFromPtr(s.end);
            std.debug.assert(ptr_int <= end_int);
            if (ptr_int >= end_int)
                return null;
            const len = @min(s.end - s.ptr, s.stride);
            const cur_ptr = s.ptr;
            s.ptr += len;
            return cur_ptr[0..len];
        }
    };
}

/// A source that produces values from start to end (exclusive)
/// T: An integer type. Start and end have the same type.
pub fn RangeIter(comptime T: type) type {
    return struct {
        const B = Iter(@This(), void, T);
        pub usingnamespace B;

        nextx: B.Out,
        end: B.Out,

        /// start: must be integer type
        /// end: exclusive upper bound
        pub fn init(start: B.Out, end: B.Out) @This() {
            return .{ .nextx = start, .end = end };
        }

        pub inline fn next(s: *@This()) ?B.Out {
            if (s.nextx == s.end)
                return null;
            const n = s.nextx;
            s.nextx += 1;
            return n;
        }
    };
}

/// A source that is generated by a function call
/// T: the return type of the function
pub fn FuncIter(comptime T: type) type {
    return struct {
        const B = Iter(@This(), void, T);
        pub usingnamespace B;

        const Func = fn (anyopaque) ?B.Out;

        func: *const Func,
        ud: anyopaque,

        /// func: called repeatedly until it returns null.
        /// At that point it should keep returning null.
        pub fn init(func: Func, ud: anyopaque) @This() {
            return .{ .func = func, .ud = ud };
        }

        pub inline fn next(s: *@This()) ?B.Out {
            return s.func(s.ud);
        }
    };
}

pub fn FilterIter(comptime SourceT: type) type {
    return struct {
        const B = Iter(@This(), SourceT.Out, SourceT.Out);
        pub usingnamespace B;

        pub const Func = fn (B.Out) bool;

        src: SourceT,
        func: *const Func,

        pub inline fn next(s: *@This()) ?B.Out {
            var t = s.src.next();
            while (t != null and !s.func(t.?)) {
                t = s.src.next();
            }
            return t;
        }
    };
}

pub fn TakeIter(comptime SourceT: type) type {
    return struct {
        const B = Iter(@This(), SourceT.Out, SourceT.Out);
        pub usingnamespace B;

        src: SourceT,
        take: u32,

        pub inline fn next(s: *@This()) ?B.Out {
            const t = s.src.next();
            for (0..s.take - 1) |i| {
                _ = i;
                _ = s.src.next() orelse return null;
            }
            return t;
        }
    };
}

pub fn DropIter(comptime SourceT: type) type {
    return struct {
        const B = Iter(@This(), SourceT.Out, SourceT.Out);
        pub usingnamespace B;

        src: SourceT,
        amt: u32,
        did: bool = false,

        pub inline fn next(s: *@This()) ?B.Out {
            if (!s.did) {
                for (0..s.amt) |i| {
                    _ = i;
                    _ = s.src.next() orelse return null;
                }
                s.did = true;
            }
            return s.src.next();
        }
    };
}

pub fn MapIter(comptime SourceT: type, comptime ReturnT: type) type {
    return struct {
        const B = Iter(@This(), SourceT.Out, ReturnT);
        pub usingnamespace B;

        pub const Func = fn (B.In) B.Out;

        src: SourceT,
        func: *const Func,

        pub inline fn next(s: *@This()) ?B.Out {
            if (s.src.next()) |v| {
                return s.func(v);
            }
            return null;
        }
    };
}

pub fn ToVecIter(comptime SourceT: type, comptime dim: u32) type {
    return struct {
        const B = Iter(@This(), SourceT.Out, Vec);
        pub usingnamespace B;

        const Element = @typeInfo(SourceT).Pointer.child;
        const Vec = @Vector(dim, Element);

        src: SourceT,
        fill: Vec,

        pub inline fn next(s: *@This()) ?B.Out {
            if (s.src.next()) |x| {
                if (x.len <= dim) {
                    return x.ptr.*;
                } else {
                    var v = s.fill;
                    const p = x.ptr;
                    const e = p + x.len;
                    const i: usize = 0;
                    while (p != e) : (p += 1) {
                        v[i] = p;
                        i += 1;
                    }
                    return v;
                }
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

pub fn ReduceSink(comptime SourceT: type, comptime ReturnT: type) type {
    return struct {
        const B = Sink(@This(), SourceT.Out, ReturnT);
        pub usingnamespace B;

        pub const Func = fn (new_value: B.Out, accum: ReturnT) ReturnT;

        src: SourceT,
        func: *const Func,
        initial: B.Out,

        pub fn sink(s: *@This()) B.Out {
            while (s.src.next()) |x| {
                s.initial = s.func(x, s.initial);
            }
            return s.initial;
        }
    };
}

pub fn CollectSink(comptime SourceT: type) type {
    return struct {
        const B = Sink(@This(), SourceT.Out, void);
        pub usingnamespace B;

        const Func = fn (item: B.Out, user_data: anytype) void;

        src: SourceT,
        f: *const Func,

        pub fn sink(s: *@This(), f: Func, u: anytype) void {
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

fn SliceOf(comptime sl: anytype) type {
    switch (@typeInfo(@TypeOf(sl))) {
        .Array => |x| return x.child,
        .Pointer => |x| return x.child,
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

const tt = std.testing;

test "appending" {
    //pub  fn main() void {
    //var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    //const gpa = general_purpose_allocator.allocator();
    //var arr = std.ArrayList(i64).init(gpa);
    //_ = arr;

    var r = Range(@as(i64, 1), 25);
    var f = r.filter(filtfn).map(mapfn).reduce(sum, 0);
    const s = f.sink();
    try std.testing.expectEqual(s, -66);

    // try std.testing.expectEqual(@as(usize, 2), arr.items.len);
    // try std.testing.expectEqual(@as(i64, 11), arr.items[0]);
    // try std.testing.expectEqual(@as(i64, 22), arr.items[1]);
}

test "drop then take" {
    var r = Range(@as(i32, 1), 10).drop(3).take(2);
    try tt.expectEqual(4, r.next());
    try tt.expectEqual(6, r.next());
    try tt.expectEqual(8, r.next());
    try tt.expectEqual(null, r.next());
    try tt.expectEqual(null, r.next());
}

test "slice" {
    const a = [_]u32{ 3, 1, 4 };
    const s: []const u32 = &a;
    var r = Slice(s);
    try tt.expectEqual(3, r.next());
    try tt.expectEqual(1, r.next());
    try tt.expectEqual(4, r.next());
    try tt.expectEqual(null, r.next());
    try tt.expectEqual(null, r.next());
}
