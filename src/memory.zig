pub const FlatMemory = struct {
    ram: []u8,
    const Self = @This();

    pub fn poke8(self: *Self, addr: u16, value: u8) void {
        self.ram[addr] = value;
    }

    pub fn peek8(self: *Self, addr: u16) u8 {
        return self.ram[addr];
    }
};
