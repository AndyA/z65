pub const NullInterruptSource = struct {
    pub const Self = @This();

    pub fn poll_irq(self: Self) bool {
        _ = self;
        return false; // No IRQ
    }

    pub fn poll_nmi(self: Self) bool {
        _ = self;
        return false; // No NMI
    }

    pub fn ack_nmi(self: *Self) void {
        _ = self; // No NMI to clear
    }
};
