// Standard lib
const std = @import("std");
const fs = std.fs;
const heap = std.heap;
const fmt = std.fmt;

const sv = @import("./libsv.zig");

const stdout_file = std.io.getStdOut().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

const OsuFileIOError = error{
    FileTooLarge, // If the file is too big to work on
    IncompleteFile, // If the file either ends in an unexpected place or does not have some vital data (ex. missing metadata fields)
};

const OsuSectionError = error{
    SectionDoesNotExist, // Trying to access a section that does not exist
    FoundTooManySections, // If more than 8 sections are found
};

const OsuTimingPointError = error{
    FoundTooManyFields,
};

// Get section offsets for the .osu file
// This is a horrible way of doing this... I really need to make it
//      1) More memory efficient
//      and,
//      2) A whole lot faster
pub fn FindSectionOffsets(filepath: []u8, offsets: []usize) !void {
    var buffer_arena = heap.ArenaAllocator.init(std.heap.c_allocator); // Arena for buffer !! Might be best to change these back to page_allocator to avoid libc dependencies
    defer buffer_arena.deinit(); // Make sure this is freed once we exit
    const buffer_alloc = buffer_arena.allocator(); // Create the allocator
    var buffer = try buffer_alloc.alloc(u8, 512); // Give this some memory

    const file = try fs.openFileAbsolute( // Open the file at `filepath`
        filepath,
        .{
            .mode = .read_only, // We only need this as read only
        },
    );

    defer file.close(); // Close it when we go out of scope

    // Check if the file is too big
    var file_size: u64 = try file.getEndPos();
    if ((file_size / 1024) >= 1500) { // Don't want to spend forever processing and or hog a ton or memory
        std.debug.print("\x1b[31mERROR: This file is WAAAYY too large to work on... (1.5Mb)\x1b[0m\n", .{});
        return OsuFileIOError.FileTooLarge; // Return an error
    }

    try file.seekTo(0); // Make sure we're at the start

    var n_offsets: u4 = 0; // How many offsets we have... max number here should be 7
    var bytes_read: usize = 512; // Var to hold how many bytes we just read
    var j: usize = 0; // This will count the passes we made in order to calculate the offset properly

    while (bytes_read >= 512) { // If we have read less than 1000 bytes then we have hit the end of the file
        bytes_read = try file.readAll(buffer); // Read in all the bytes that the buffer will hold

        for (buffer, 1..buffer.len + 1) |c, k| { // Read char by char to find the end of a header section
            if (c == ']') {
                if (n_offsets > 8) {
                    return OsuSectionError.FoundTooManySections;
                }

                offsets[n_offsets] = (512 * j) + 1 + k;
                n_offsets += 1;
            }
        }

        _ = buffer_arena.reset(.free_all); // Dump the arena
        buffer = try buffer_alloc.alloc(u8, 512); // Remake it so that we can put more data in it
        j += 1; // Increment our passes
    }
}

// Turn a string into a timing point
pub fn StrToTimingPoint(str: []u8) !sv.TimingPoint {
    var point = sv.TimingPoint{};
    var buffer_arena = heap.ArenaAllocator.init(heap.c_allocator); // Create an arena for the buffer
    var buffer_alloc = buffer_arena.allocator(); // Create an allocator
    var buffer = try buffer_alloc.alloc(u8, 20); // This shouldn't need more than 50 indexes but I can adjust it if needed

    var field: u8 = 0; // Current field we're filling out
    var i_buffer: u8 = 0; // Current index in the buffer

    for (str) |c| { // Loop through the given string char by char
        if (c == ',') { // If we reach a `,` that means we have reached the end of a field
            switch (field) { // Figure out which field we're on and apply the right function to it
                0 => blk: {
                    point.time = try fmt.parseInt(i32, buffer[0..i_buffer], 10); // Need to use a slice or the function will try and translate the blank spots of the buffer, resulting in an error
                    break :blk;
                },
                1 => blk: {
                    point.value = try fmt.parseFloat(f32, buffer[0..i_buffer]);
                    break :blk;
                },
                2 => blk: {
                    point.meter = try fmt.parseUnsigned(u8, buffer[0..i_buffer], 10);
                    break :blk;
                },
                3 => blk: {
                    point.sampleSet = try fmt.parseUnsigned(u8, buffer[0..i_buffer], 10);
                    break :blk;
                },
                4 => break,
                5 => blk: {
                    point.volume = try fmt.parseUnsigned(u8, buffer[0..i_buffer], 10);
                    break :blk;
                },
                6 => blk: {
                    point.is_inh = try fmt.parseUnsigned(u1, buffer[0..i_buffer], 10);
                    break :blk;
                },
                7 => blk: {
                    point.effects = try fmt.parseUnsigned(u8, buffer[0..i_buffer], 10);
                    break :blk;
                },
                else => {
                    return OsuTimingPointError.FoundTooManyFields;
                },
            }
            field += 1; // Increment the field
            i_buffer = 0; // Set the buffer index to 0
            _ = buffer_arena.reset(.free_all); // Dump the buffer for next go
            buffer = try buffer_alloc.alloc(u8, 20);
        } else {
            buffer[i_buffer] = c;
            i_buffer += 1;
        }
    }

    return point;
}

// Populate the timing point array and return the position that we ended on
pub fn LoadTimingPointArray(filepath: []u8, offset: u64, sv_array: []sv.TimingPoint) !u64 {
    var buffer_arena = heap.ArenaAllocator.init(std.heap.c_allocator); // Arena for buffer !! Might be best to change these back to page_allocator to avoid libc dependencies
    defer buffer_arena.deinit(); // Make sure this is all freed
    const buffer_alloc = buffer_arena.allocator(); // Create the allocator
    var buffer = try buffer_alloc.alloc(u8, 50); // Give this some memory
    //
    var str_arena = heap.ArenaAllocator.init(std.heap.c_allocator); // Arena for buffer !! Might be best to change these back to page_allocator to avoid libc dependencies
    defer str_arena.deinit(); // Make sure this is all freed
    const str_alloc = str_arena.allocator(); // Create the allocator
    var str_buff = try str_alloc.alloc(u8, 50); // Give this some memory

    const file = try fs.openFileAbsolute( // Open the file at `filepath`
        filepath,
        .{
            .mode = .read_only, // We only need this as read only
        },
    );

    defer file.close(); // Close it when we go out of scope

    try file.seekTo(offset + 1); // Go to the offset

    var i_strbuf: u8 = 0;
    for (0..sv_array.len) |curr_point| {
        var bytes_read = try file.readAll(buffer); // Read in the new data

        if (bytes_read < 50) { // We shouldn't read less than 50 bytes here
            return OsuFileIOError.IncompleteFile;
        }
        //std.debug.print("READ_BUFFER: {s}\n", .{buffer});
        for (buffer, 0..buffer.len) |c, i| {
            if (c == '\n' or c == '\r') {
                //std.debug.print("STR_BUFF COMPLETE\n FINAL STR_BUFF: {s}\n", .{str_buff});

                sv_array[curr_point] = try StrToTimingPoint(str_buff[0 .. i_strbuf + 1]); // Convert the string and load it into the array
                try file.seekBy(@as(i64, @intCast(i)) - @as(i64, @intCast(bytes_read)) + 2); // Seek back the difference so that we don't miss data. "Why + 2?" ZERO FUCKING CLUE it works though!
                i_strbuf = 0; // Set this iterator to 0
                _ = str_arena.reset(.free_all); // Dump the string buffer
                str_buff = try str_alloc.alloc(u8, 50); // Alloc new memory
                break;
            } else {
                //std.debug.print("CURRENT STR_BUFF: {s}\n", .{str_buff});

                str_buff[i_strbuf] = c;
                i_strbuf += 1;
            }
        }
        _ = buffer_arena.reset(.free_all); // Refresh the read buffer
        buffer = try buffer_alloc.alloc(u8, 50);
    }

    return try file.getPos() - 1; // Return the last position
}
