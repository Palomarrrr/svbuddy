const std = @import("std");
const sv = @import("libosu/libsv.zig");
const osufile = @import("libosu/osufileio.zig");

// Short-hands for stdout n shit
const stdout_file = std.io.getStdOut().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

pub fn main() !void {
    //THINGS TO FIX -
    //
    //FAILS ON ...
    //
    //sola.osu -
    //  REASON: APPARENTLY OSU TIME VALUES ARENT ACTUALLY INTS
    //
    //hell.osu -
    //  REASON: nanaparty
    //

    var filepath = "/home/koishi/Coding/Zig/svbuddy/osu_testfiles/quarks.osu".*; // WHAT THE HELL OK I GUESS
    var offsets: [10]usize = undefined;
    try osufile.FindSectionOffsets(&filepath, &offsets); // BOTH MUST BE PASSED AS REFERENCE

    //std.debug.print("{}\n", .{offsets[6]});
    var points: [200]sv.TimingPoint = undefined;

    var newoffset: u64 = try osufile.LoadTimingPointArray(&filepath, offsets[5], &points);
    _ = newoffset;
    //_ = try osufile.LoadTimingPointArray(&filepath, @as(usize, @intCast(newoffset)), &points);

    for (points) |p| {
        try p.print_osu_formatted();
    }
}
