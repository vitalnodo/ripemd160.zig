const std = @import("std");
const mem = std.mem;

pub const Ripemd160 = struct {
    const Self = @This();
    pub const block_length = 64;
    pub const digest_length = 20;
    pub const Options = struct {};

    s: [5]u32,
    // Streaming Cache
    buf: [64]u8 = undefined,
    buf_len: u8 = 0,
    total_len: u64 = 0,

    pub fn init(options: Options) Self {
        _ = options;
        return Self{
            .s = [_]u32{
                0x67452301,
                0xEFCDAB89,
                0x98BADCFE,
                0x10325476,
                0xC3D2E1F0,
            },
        };
    }

    pub fn update(d: *Self, b: []const u8) void {
        var off: usize = 0;

        // Partial buffer exists from previous update. Copy into buffer then hash.
        if (d.buf_len != 0 and d.buf_len + b.len >= 64) {
            off += 64 - d.buf_len;
            mem.copy(u8, d.buf[d.buf_len..], b[0..off]);

            d.round(d.buf[0..]);
            d.buf_len = 0;
        }

        // Full middle blocks.
        while (off + 64 <= b.len) : (off += 64) {
            d.round(b[off..][0..64]);
        }

        // Copy any remainder for next pass.
        mem.copy(u8, d.buf[d.buf_len..], b[off..]);
        d.buf_len += @intCast(u8, b[off..].len);

        d.total_len += b.len;
    }

    fn blockToWords(block: *const [block_length]u8) [16]u32 {
        var words: [16]u32 = undefined;
        for (words) |_, i| {
            // zig fmt: off
            words[i] = 0;
            words[i] |= (@as(u32, block[i * 4 + 3]) << 24);
            words[i] |= (@as(u32, block[i * 4 + 2]) << 16);
            words[i] |= (@as(u32, block[i * 4 + 1]) << 8);
            words[i] |= (@as(u32, block[i * 4 + 0]) << 0);
            // zig fmt: on
        }
        return words;
    }

    fn func(j: usize, x: u32, y: u32, z: u32) u32 {
        return switch (j) {
            // f(j, x, y, z) = x XOR y XOR z                (0 <= j <= 15)
            0...15 => x ^ y ^ z,
            // f(j, x, y, z) = (x AND y) OR (NOT(x) AND z)  (16 <= j <= 31)
            16...31 => (x & y) | (~x & z),
            // f(j, x, y, z) = (x OR NOT(y)) XOR z          (32 <= j <= 47)
            32...47 => (x | ~y) ^ z,
            // f(j, x, y, z) = (x AND z) OR (y AND NOT(z))  (48 <= j <= 63)
            48...63 => (x & z) | (y & ~z),
            // f(j, x, y, z) = x XOR (y OR NOT(z))          (64 <= j <= 79)
            // !!! omg xor and or 64
            64...79 => x ^ (y | ~z),
            else => unreachable,
        };
    }

    fn round(d: *Self, b: *const [block_length]u8) void {
        var leftA = d.s[0];
        var leftB = d.s[1];
        var leftC = d.s[2];
        var leftD = d.s[3];
        var leftE = d.s[4];

        var rightA = d.s[0];
        var rightB = d.s[1];
        var rightC = d.s[2];
        var rightD = d.s[3];
        var rightE = d.s[4];

        const left_selecting_words = [80]u32{
            0, 1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
            7, 4,  13, 1,  10, 6,  15, 3,  12, 0, 9,  5,  2,  14, 11, 8,
            3, 10, 14, 4,  9,  15, 8,  1,  2,  7, 0,  6,  13, 11, 5,  12,
            1, 9,  11, 10, 0,  8,  12, 4,  13, 3, 7,  15, 14, 5,  6,  2,
            4, 0,  5,  9,  7,  12, 2,  10, 14, 1, 3,  8,  11, 6,  15, 13,
        };

        const right_selecting_words = [80]u32{
            5,  14, 7,  0, 9, 2,  11, 4,  13, 6,  15, 8,  1,  10, 3,  12,
            6,  11, 3,  7, 0, 13, 5,  10, 14, 15, 8,  12, 4,  9,  1,  2,
            15, 5,  1,  3, 7, 14, 6,  9,  11, 8,  12, 2,  10, 0,  4,  13,
            8,  6,  4,  1, 3, 11, 15, 0,  5,  12, 2,  13, 9,  7,  10, 14,
            12, 15, 10, 4, 1, 5,  8,  7,  6,  2,  13, 14, 0,  3,  9,  11,
        };

        const left_tmp_shift_amount = [80]u32{
            11, 14, 15, 12, 5,  8,  7,  9,  11, 13, 14, 15, 6,  7,  9,  8,
            7,  6,  8,  13, 11, 9,  7,  15, 7,  12, 15, 9,  11, 7,  13, 12,
            11, 13, 6,  7,  14, 9,  13, 15, 14, 8,  13, 6,  5,  12, 7,  5,
            11, 12, 14, 15, 14, 15, 9,  8,  9,  14, 5,  6,  8,  6,  5,  12,
            9,  15, 5,  11, 6,  8,  13, 12, 5,  12, 13, 14, 11, 8,  5,  6,
        };

        const right_tmp_shift_amount = [80]u32{
            8,  9,  9,  11, 13, 15, 15, 5,  7,  7,  8,  11, 14, 14, 12, 6,
            9,  13, 15, 7,  12, 8,  9,  11, 7,  7,  12, 7,  6,  15, 13, 11,
            9,  7,  15, 11, 8,  6,  6,  14, 12, 13, 5,  14, 13, 13, 7,  5,
            15, 5,  8,  11, 14, 14, 6,  14, 6,  9,  12, 9,  12, 5,  15, 8,
            8,  5,  12, 9,  12, 5,  14, 6,  8,  13, 6,  5,  15, 13, 11, 11,
        };

        const left_K = [5]u32{ 0x00000000, 0x5A827999, 0x6ED9EBA1, 0x8F1BBCDC, 0xA953FD4E };
        const right_K = [5]u32{ 0x50A28BE6, 0x5C4DD124, 0x6D703EF3, 0x7A6D76E9, 0x00000000 };

        var words: [16]u32 = blockToWords(b);
        var tmp: u32 = undefined;
        var j: usize = 0;
        while (j < 80) : (j += 1) {
            // zig fmt: off
            tmp = std.math.rotl(u32, leftA 
                    +% func(j, leftB, leftC, leftD) 
                    +% words[left_selecting_words[j]] 
                    +% left_K[j / 16],
                left_tmp_shift_amount[j]) +% leftE;
            // zig fmt: on
            leftA = leftE;
            leftE = leftD;
            leftD = std.math.rotl(u32, leftC, 10);
            leftC = leftB;
            leftB = tmp;

            // zig fmt: off
            tmp = std.math.rotl(u32, rightA 
                    +% func(79 - j, rightB, rightC, rightD) 
                    +% words[right_selecting_words[j]] 
                    +% right_K[j / 16], 
                right_tmp_shift_amount[j]) +% rightE;
            // zig fmt: on
            rightA = rightE;
            rightE = rightD;
            rightD = std.math.rotl(u32, rightC, 10);
            rightC = rightB;
            rightB = tmp;
        }

        tmp = d.s[1] +% leftC +% rightD;
        d.s[1] = d.s[2] +% leftD +% rightE;
        d.s[2] = d.s[3] +% leftE +% rightA;
        d.s[3] = d.s[4] +% leftA +% rightB;
        d.s[4] = d.s[0] +% leftB +% rightC;
        d.s[0] = tmp;
    }

    pub fn final(d: *Self, out: *[digest_length]u8) void {
        // The buffer here will never be completely full.
        mem.set(u8, d.buf[d.buf_len..], 0);

        // Append padding bits.
        d.buf[d.buf_len] = 0x80;
        d.buf_len += 1;

        // > 448 mod 512 so need to add an extra round to wrap around.
        if (64 - d.buf_len < 8) {
            d.round(d.buf[0..]);
            mem.set(u8, d.buf[0..], 0);
        }

        // Append message length in more simple way
        const len = (d.total_len * 8);
        std.mem.writeIntLittle(u64, d.buf[56..64], len);

        d.round(d.buf[0..]);

        for (d.s) |s, j| {
            mem.writeIntLittle(u32, out[4 * j ..][0..4], s);
        }
    }

    pub fn hash(b: []const u8, out: *[digest_length]u8, options: Options) void {
        var d = Ripemd160.init(options);
        d.update(b);
        d.final(out);
    }
};

// Hash using the specified hasher `H` asserting `expected == H(input)`.
fn assertEqualHash(comptime Hasher: anytype, comptime expected_hex: *const [Hasher.digest_length * 2:0]u8, input: []const u8) !void {
    var h: [Hasher.digest_length]u8 = undefined;
    Hasher.hash(input, &h, .{});

    try assertEqual(expected_hex, &h);
}

// Assert `expected` == hex(`input`) where `input` is a bytestring
fn assertEqual(comptime expected_hex: [:0]const u8, input: []const u8) !void {
    var expected_bytes: [expected_hex.len / 2]u8 = undefined;
    for (expected_bytes) |*r, i| {
        r.* = std.fmt.parseInt(u8, expected_hex[2 * i .. 2 * i + 2], 16) catch unreachable;
    }

    try std.testing.expectEqualSlices(u8, &expected_bytes, input);
}

test "test vectors" {
    var out: [Ripemd160.digest_length]u8 = undefined;
    Ripemd160.hash("", &out, .{});
    try assertEqualHash(Ripemd160, "9c1185a5c5e9fc54612808977ee8f548b2258d31", "");
    try assertEqualHash(Ripemd160, "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe", "a");
    try assertEqualHash(Ripemd160, "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc", "abc");
    try assertEqualHash(Ripemd160, "5d0689ef49d2fae572b881b123a85ffa21595f36", "message digest");
    try assertEqualHash(Ripemd160, "f71c27109c692c1b56bbdceb5b9d2865b3708dbc", "abcdefghijklmnopqrstuvwxyz");
    try assertEqualHash(Ripemd160, "12a053384a9c0c88e405a06c27dcf49ada62eb2b", "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
    try assertEqualHash(Ripemd160, "b0e20b6e3116640286ed3a87a5713079b21f5189", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
    try assertEqualHash(Ripemd160, "9b752e45573d4b39f4dbd3323cab82bf63326bfb", "1234567890" ** 8);
    try assertEqualHash(Ripemd160, "52783243c1697bdbe16d37f97f68f08325dc1528", "a" ** 1000000);
}

test "streaming" {
    var h = Ripemd160.init(.{});
    var out: [Ripemd160.digest_length]u8 = undefined;
    h.final(&out);
    try assertEqual("9c1185a5c5e9fc54612808977ee8f548b2258d31", out[0..]);

    h = Ripemd160.init(.{});
    h.update("abc");
    h.final(&out);
    try assertEqual("8eb208f7e05d987a9b044a8e98c6b087f15a0bfc", out[0..]);

    h = Ripemd160.init(.{});
    h.update("a");
    h.update("b");
    h.update("c");
    h.final(&out);
    try assertEqual("8eb208f7e05d987a9b044a8e98c6b087f15a0bfc", out[0..]);
}

test "aligned" {
    var block = [_]u8{0} ** Ripemd160.block_length;
    var out: [Ripemd160.digest_length]u8 = undefined;

    var h = Ripemd160.init(.{});
    h.update(&block);
    h.final(out[0..]);
}
