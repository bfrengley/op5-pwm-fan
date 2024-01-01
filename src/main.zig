const std = @import("std");
const fs = std.fs;
const parseInt = std.fmt.parseInt;

// PWM file locations.
// If you wish to use a different PWM device, modify these paths as appropriate.
const PWM2_EXPORT_FILE: []const u8 = "/sys/class/pwm/pwmchip2/export";
const PWM2_POLARITY_FILE: []const u8 = "/sys/class/pwm/pwmchip2/pwm0/polarity";
const PWM2_PERIOD_FILE: []const u8 = "/sys/class/pwm/pwmchip2/pwm0/period";
const PWM2_DUTY_CYCLE_FILE: []const u8 = "/sys/class/pwm/pwmchip2/pwm0/duty_cycle";
const PWM2_ENABLE_FILE: []const u8 = "/sys/class/pwm/pwmchip2/pwm0/enable";

// Thermal zone 0 is the SoC temperature.
const THERMAL_ZONE_FILE: []const u8 = "/sys/class/thermal/thermal_zone0/temp";

// Period is specified in nanoseconds.
// Noctua requires a 25kHz PWM signal; modify this if your fan requires a different frequency.
const PWM2_PERIOD: []const u8 = "40000";
const PWM2_PERIOD_INT: i64 = parseInt(i64, PWM2_PERIOD, 10) catch {
    @compileError("Invalid PWM period");
};

pub fn main() !void {
    enablePwm() catch {
        std.log.err("Failed to initialise PWM, aborting...", .{});
        return;
    };

    while (true) {
        updateDutyCycle();
        std.time.sleep(1_000_000_000);
    }
}

fn enablePwm() !void {
    // export the PWM (?)
    write(PWM2_EXPORT_FILE, "0") catch |err| {
        if (err == fs.File.WriteError.DeviceBusy) {
            std.log.info("Ignoring error {} while exporting PWM; PWM already active", .{err});
        } else {
            return err;
        }
    };

    // make sure the polarity is consistent
    // it doesn't matter if the polarity is normal or inversed, but it does affect our maths so
    // we just have to pick one and base the maths around that
    // in normal polarity, the duty cycle indicates the length of the active time
    // in inversed polarity, the duty cycle indicates the length of the inactive time
    // this can only be set when PWM is disabled, so disable it first
    write(PWM2_ENABLE_FILE, "0") catch |err| {
        if (err == fs.File.WriteError.InvalidArgument) {
            std.log.info("Ignoring error {} while disabling PWM; PWM already disabled", .{err});
        } else {
            return err;
        }
    };
    write(PWM2_POLARITY_FILE, "normal") catch |err| {
        if (err == fs.File.WriteError.InvalidArgument) {
            std.log.info("Ignoring error {} while setting PWM polarity; PWM already using normal polarity", .{err});
        } else {
            return err;
        }
    };

    // start with a 0 duty cycle; the next tick will increase it as necessary but this ensures
    // that we start quietly
    try write(PWM2_PERIOD_FILE, PWM2_PERIOD);
    try write(PWM2_DUTY_CYCLE_FILE, "0");

    // setup complete, so enabled the PWM
    try write(PWM2_ENABLE_FILE, "1");
}

fn updateDutyCycle() void {
    const tempFile = fs.openFileAbsolute(THERMAL_ZONE_FILE, .{}) catch |err| {
        std.log.warn("Failed to open file {s}: {}", .{ THERMAL_ZONE_FILE, err });
        return;
    };
    defer tempFile.close();

    var buf = [_]u8{0} ** 16;

    const n = tempFile.readAll(&buf) catch |err| {
        std.log.warn("Failed to read file {s}: {}", .{ THERMAL_ZONE_FILE, err });
        return;
    };

    if (n == buf.len) {
        std.log.warn("Read size larger than expected: read {d} bytes, expected ~5", .{n});
        return;
    }

    // the file ends with a newline character, so skip the final byte
    const temp = parseInt(i64, buf[0..(n - 1)], 10) catch {
        std.log.warn("Failed to parse temperature as int: {s}", .{&buf});
        return;
    };

    // temperatures are given in thousandths of a degree C
    // 50000 == 50C
    if (temp < 50000) {
        write(PWM2_DUTY_CYCLE_FILE, "0") catch {};
    } else if (temp >= 75000) { // 75000 == 75C
        write(PWM2_DUTY_CYCLE_FILE, PWM2_PERIOD) catch {};
    } else {
        // scale linearly between 50C to 75C
        const duty_cycle = @divTrunc(PWM2_PERIOD_INT * (temp - 50000), 25000);
        const dc_buf = std.fmt.bufPrint(&buf, "{d}", .{duty_cycle}) catch {
            unreachable;
        };
        write(PWM2_DUTY_CYCLE_FILE, dc_buf) catch {};
    }
}

fn write(file: []const u8, val: []const u8) !void {
    var f = fs.openFileAbsolute(file, .{ .mode = .write_only }) catch |err| {
        std.log.warn("Failed to open file {s} for writing: {}", .{ file, err });
        return err;
    };
    defer f.close();

    f.writeAll(val) catch |err| {
        std.log.warn("Failed to write to file {s}: {}", .{ file, err });
        return err;
    };
}
