const std = @import("std");
const math = std.math;
const time = std.time;
const rand = std.rand.Random;
const RAND_GEN = std.rand.DefaultPrng;

// Just some shorthand shit to make things easier on me
const stdout_file = std.io.getStdOut().writer();
var bw = std.io.bufferedWriter(stdout_file);
const stdout = bw.writer();

//**********************************************************
//                        STRUCTS
//**********************************************************

pub const TimingPoint = struct {
    /// The time in ms from start of a map. Set to i64 to get around gimmick fuckery
    time: i32 = 0,
    /// Either the 60000/BPM (positive number), or -100/svValue (negative number)
    value: f32 = 1.0,
    /// Number of beats in the measure
    meter: u8 = 4,
    /// What sample set of sounds to use. This really shouldnt be higher than a 4 bit number or you have problems
    sampleSet: u8 = 1,
    /// This is pretty self explanitory
    volume: u8 = 100,
    /// If the point is inherited(1) or not(0). This is a u1 instead of a bool to make shit easier
    is_inh: u1 = 0,
    /// effect bitflag -- More docs on this later
    effects: u8 = 0,

    pub fn print_osu_formatted(self: *const TimingPoint) !void {
        try stdout.print("{},{d:.6},{},{},0,{},{},{}\n", .{ self.time, self.value, self.meter, self.sampleSet, self.volume, self.is_inh, self.effects });
        try bw.flush();
    }
};

//**********************************************************
//                        EFFECTS
//**********************************************************

// TODO - Add a way to scale SV values over changing bpms

// Internal function just to make some things cleaner. Inlined to try and help with performance
inline fn SvBpmAdjust(sv: f32, bpm_old: f32, bpm_new: f32) f32 {
    return ((bpm_old * sv) / bpm_new);
}

inline fn GetNumUninherited(sv_arr: []TimingPoint) u32 {
    var c: u32 = 0;
    for (sv_arr) |point| {
        if (point.is_inh == 0) {
            c += 1;
        }
    }
    return c;
}

// Linear increases/decreases | pass -1 to initial_bpm to turn off scale w/ bpm
pub fn Linear(sv_arr: []TimingPoint, sv_start: f32, sv_end: f32, initial_bpm: f32) !void {
    var curr_sv = sv_start;
    var n_uninh = GetNumUninherited(sv_arr);
    var sv_slope: f32 = ((sv_end - sv_start) / @as(f32, @floatFromInt(sv_arr.len - (1 + n_uninh))));
    var next_bpm: f32 = initial_bpm;
    for (0..sv_arr.len) |i| {
        if (sv_arr[i].is_inh == 1) { // If point is inherited
            sv_arr[i].value = -100 / SvBpmAdjust(curr_sv, initial_bpm, next_bpm);
            curr_sv += sv_slope;
        } else { // If point is uninherited
            if (initial_bpm > 0) { // If scale w/ bpm is on
                next_bpm = 60000 / sv_arr[i].value; // collect the next BPM so we can adjust off of that
            }
        }
    }
}

// Exponential increases/decreases
pub fn Exponential(sv_arr: []TimingPoint, sv_start: f32, sv_end: f32, initial_bpm: f32) !void {
    var next_bpm: f32 = initial_bpm;
    for (0..sv_arr.len) |i| {
        if (sv_arr[i].is_inh == 1) {
            sv_arr[i].value = -100.0 / SvBpmAdjust((sv_start * math.pow(f32, math.pow(f32, math.e, (@log(sv_end) - @log(sv_start)) / @as(f32, @floatFromInt(sv_arr[sv_arr.len - 1].time - sv_arr[0].time))), @as(f32, @floatFromInt(sv_arr[i].time - sv_arr[0].time)))), initial_bpm, next_bpm);
        } else {
            if (initial_bpm > 0) {
                next_bpm = 60000 / sv_arr[i].value;
            }
        }
    }
}

// Sinusoidal waves
pub fn Sinusoidal(sv_arr: []TimingPoint, sv_trough: f32, sv_peak: f32, n_cycles: f32, initial_bpm: f32) !void {
    var next_bpm: f32 = initial_bpm;
    const amp: f32 = (sv_peak - sv_trough) / 2.0;
    const y_offset: f32 = sv_trough + amp;

    for (0..sv_arr.len) |i| {
        if (sv_arr[i].is_inh == 1) {
            sv_arr[i].value = -100.0 / SvBpmAdjust((amp * (math.sin(((2.0 * math.pi) * (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sv_arr.len - 1)))) * n_cycles)) + y_offset), initial_bpm, next_bpm);
        } else {
            if (initial_bpm > 0) {
                next_bpm = 60000 / sv_arr[i].value;
            }
        }
    }
}

// Cubic Bezier function | NOT WORKING | Need to implement BPM scaling (good luck w/ that shit)
pub fn CubicBezier(sv_arr: []TimingPoint, p1: *[2]f32, p2: *[2]f32, p3: *[2]f32, p4: *[2]f32) !void {

    // Turn the array indexes into 0 -> 1 values
    p1[0] = p1[0] / @as(f32, @floatFromInt(sv_arr.len));
    p2[0] = p2[0] / @as(f32, @floatFromInt(sv_arr.len));
    p3[0] = p3[0] / @as(f32, @floatFromInt(sv_arr.len));
    p4[0] = p4[0] / @as(f32, @floatFromInt(sv_arr.len));

    // TODO - For some reason this function generates blank values.... Figure out why and fix it
    std.debug.print("\x1b[31mWARNING: This function is currently NOT WORKING AS INTENDED!!!\nThe outcome may have some invalid values!!!\x1b[0m\n", .{});

    for (0..sv_arr.len) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sv_arr.len)); // Percentage of the way though the array since Bezier curves opperate between 0 - 1

        // This should be a value between 0 -> 1
        var curr_x: f32 = ((math.pow(f32, (1 - t), 3)) * p1[0]) + ((3 * math.pow(f32, (1 - t), 2) * t) * p2[0]) + ((3 * (1 - t) * math.pow(f32, t, 2)) * p3[0]) + (math.pow(f32, t, 3) * p4[0]);

        // This is the SV value
        var curr_y: f32 = ((math.pow(f32, (1 - t), 3)) * p1[1]) + ((3 * math.pow(f32, (1 - t), 2) * t) * p2[1]) + ((3 * (1 - t) * math.pow(f32, t, 2)) * p3[1]) + (math.pow(f32, t, 3) * p4[1]);

        // Inflate the X value from 0 -> 1 to 0 -> (sv_arr.len - 1)
        var curr_index: u32 = @as(u32, @intFromFloat(@floor(curr_x * @as(f32, @floatFromInt(sv_arr.len)))));
        //std.debug.print("index: {}\n", .{curr_index});

        sv_arr[curr_index].value = curr_y;
    }
}

// TODO - Implement BPM scaling
// Increase a section by a set ammount
pub fn AdjustSection(sv_arr: []TimingPoint, ammount: f32) !void {
    for (0..sv_arr.len) |i| {
        sv_arr[i].value = -100 / ((-100 / sv_arr[i].value) + ammount);
    }
}

// TODO - Implement BPM scaling
// Scale a given TimingPoint array from its previous bounds to a new set of bounds (ex. [1.5x, 3.0x] -> [1.0x, 1.25x])
pub fn ScaleSection(sv_arr: []TimingPoint, l_bound: f32, u_bound: f32) !void {

    // Remember 10 is the max sv and 0 is the min
    var old_sv_low: f32 = 11; // Old sv lower bound
    var old_sv_up: f32 = 0; // Old sv upper bound
    var old_sv_dist: f32 = 0; // Difference between the old bounds
    var new_sv_dist: f32 = u_bound - l_bound; // Difference between the new bounds

    // Find your max and mins
    for (0..sv_arr.len) |i| {
        sv_arr[i].value = -100.0 / sv_arr[i].value; // Convert back to normal numbers
        if (sv_arr[i].value > old_sv_up) {
            old_sv_up = sv_arr[i].value;
        }
        if (sv_arr[i].value < old_sv_low) {
            old_sv_low = sv_arr[i].value;
        }
    }

    old_sv_dist = old_sv_up - old_sv_low; // Calculate the difference

    // Deflate value between 0 - 1
    for (0..sv_arr.len) |i| {
        sv_arr[i].value = (sv_arr[i].value - old_sv_low) / old_sv_dist; // Subtract the old lower bound and divide by the old distance
    }

    // Inflate value between new bounds
    for (0..sv_arr.len) |i| {
        sv_arr[i].value = -100.0 / ((sv_arr[i].value * new_sv_dist) + l_bound); // Multiply by the new distance and then add the new lower bound
    }
}

// TODO - Implement BPM scaling
// Randomize the output of a given function between two different values
pub fn BoundedRandom() type {
    return struct {

        // Internal function to randomize a number between two values
        inline fn Rand_Point(pos_bound: f32, neg_bound: f32, curr_point_val: f32) !f32 {
            var rnd = RAND_GEN.init(@as(u64, @truncate(math.absCast(time.nanoTimestamp())))); // Seed the rng (I LOVE GIGA STRICT TYPING)
            var rand_float: f32 = rnd.random().float(f32); // Get a random float 0-1
            return curr_point_val + (@as(f32, try math.mod(f32, rand_float, pos_bound - neg_bound)) + neg_bound);
        }

        // Generate random values based off a static initial value + or - the two bounds
        pub fn static(sv_arr: []TimingPoint, sv_val: f32, neg_bound: f32, pos_bound: f32) !void {
            for (0..sv_arr.len) |i| {
                sv_arr[i].value = -100.0 / try Rand_Point(pos_bound, neg_bound, sv_val); // Translate to human readable and then translate back to osu readable
            }
        }

        // Create a linear increase/decrease and then randomize the values + or - the two bounds
        pub fn linear(sv_arr: []TimingPoint, sv_start: f32, sv_end: f32, neg_bound: f32, pos_bound: f32) !void {
            try Linear(sv_arr, sv_start, sv_end); // Run a linear progression on it
            for (0..sv_arr.len) |i| {
                sv_arr[i].value = -100.0 / try Rand_Point(pos_bound, neg_bound, (-100.0 / sv_arr[i].value)); // Translate to human readable and then translate back to osu readable
            }
        }

        // Create an exponential increase/decrease and then randomize the values + or - the two bounds
        pub fn exponential(sv_arr: []TimingPoint, sv_start: f32, sv_end: f32, neg_bound: f32, pos_bound: f32) !void {
            try Exponential(sv_arr, sv_start, sv_end); // Run a linear progression on it
            for (0..sv_arr.len) |i| {
                sv_arr[i].value = -100.0 / try Rand_Point(pos_bound, neg_bound, (-100.0 / sv_arr[i].value)); // Translate to human readable and then translate back to osu readable
            }
        }

        // Create a sinusoidal wave and then randomize the values + or - the two bounds
        pub fn sinusoidal(sv_arr: []TimingPoint, sv_trough: f32, sv_peak: f32, n_cycles: f32, neg_bound: f32, pos_bound: f32) !void {
            try Sinusoidal(sv_arr, sv_trough, sv_peak, n_cycles); // Run a linear progression on it
            for (0..sv_arr.len) |i| {
                sv_arr[i].value = -100.0 / try Rand_Point(pos_bound, neg_bound, (-100.0 / sv_arr[i].value)); // Translate to human readable and then translate back to osu readable
            }
        }

        // TODO - add CubicBezier
    };
}
