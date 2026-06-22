pub fn Signal(comptime T: type) type {
    return struct {
        const Self = @This();
        const Handler = *const fn (ctx: *T) void;
        handler: Handler,
        context: *T,

        pub fn init(handler: Handler, context: *T) Self {
            return .{ .handler = handler, .context = context };
        }

        pub fn signal(self: Self) void {
            self.handler(self.context);
        }
    };
}
