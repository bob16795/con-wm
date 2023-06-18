const std = @import("std");

const math = @import("math.zig");
const drawer = @import("drawer.zig");

const c = @import("c.zig");

const VERSION = "0.1.0";

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const CONFIG = packed struct {
    const showbar = true;
    const topbar = true;
    const defaultcontainer = 3;
    const borderpx = 2;
    const broken = "BROKEN";
    const frametabs = true;

    var normbgcolor: []const u8 = "#222222";
    var normbordercolor: []const u8 = "#333333";
    var normfgcolor: []const u8 = "#888888";
    var selfgcolor: []const u8 = "#FFFFFF";
    var selbordercolor: []const u8 = "#4C7899";
    var selbgcolor: []const u8 = "#285577";

    const colors = [_][3]*[]const u8{
        .{ &selfgcolor, &selbgcolor, &selbordercolor },
        .{ &normfgcolor, &normbgcolor, &normbordercolor },
    };

    const MODKEY = c.Mod4Mask;

    const buttons = [_]Button{
        .{ .target = .ClientWin, .button = c.Button1, .mask = MODKEY, .func = moveMouse },
        .{ .target = .FrameWin, .button = c.Button1, .mask = MODKEY, .func = moveMouse },
        .{ .target = .FrameWin, .button = c.Button1, .func = moveMouse },

        .{ .target = .ClientWin, .button = c.Button3, .mask = MODKEY, .func = resizeMouse },
        .{ .target = .FrameWin, .button = c.Button3, .mask = MODKEY, .func = resizeMouse },
        .{ .target = .FrameWin, .button = c.Button3, .func = resizeMouse },
    };

    const signals = [_]Signal{
        .{ .signum = 8, .func = toggleBar },
        .{ .signum = 16, .func = killClient },
        .{ .signum = 17, .func = toggleFloating },
        .{ .signum = 98, .func = quit, .arg = .{ .i = 1 } },
        .{ .signum = 99, .func = quit, .arg = .{ .i = 0 } },

        .{ .signum = 115, .func = setContainer, .arg = .{ .i = 1 } },
        .{ .signum = 125, .func = setContainer, .arg = .{ .i = 2 } },
        .{ .signum = 135, .func = setContainer, .arg = .{ .i = 3 } },
        .{ .signum = 145, .func = setContainer, .arg = .{ .i = 4 } },
    };

    const rules = [_]Rule{};

    const containers = Container{
        .name = "ABCD",
        .x_start = 0.00,
        .y_start = 0.00,
        .x_end = 1.00,
        .y_end = 1.00,
        .ids = &.{ 1, 2, 3, 4 },
        .children = &.{
            .{
                .name = "AC",
                .x_start = 0.00,
                .y_start = 0.00,
                .x_end = 0.70,
                .y_end = 1.00,
                .ids = &.{ 1, 3 },
                .children = &.{
                    .{
                        .name = "A",
                        .x_start = 0.00,
                        .y_start = 0.00,
                        .x_end = 1.00,
                        .y_end = 0.20,
                        .ids = &.{1},
                        .children = &.{},
                    },
                    .{
                        .name = "C",
                        .x_start = 0.00,
                        .y_start = 0.20,
                        .x_end = 1.00,
                        .y_end = 1.00,
                        .ids = &.{3},
                        .children = &.{},
                    },
                },
            },
            .{
                .name = "BD",
                .x_start = 0.70,
                .y_start = 0.00,
                .x_end = 1.00,
                .y_end = 1.00,
                .ids = &.{ 2, 4 },
                .children = &.{
                    .{
                        .name = "B",
                        .x_start = 0.00,
                        .y_start = 0.00,
                        .x_end = 1.00,
                        .y_end = 0.50,
                        .ids = &.{2},
                        .children = &.{},
                    },
                    .{
                        .name = "D",
                        .x_start = 0.00,
                        .y_start = 0.50,
                        .x_end = 1.00,
                        .y_end = 1.00,
                        .ids = &.{4},
                        .children = &.{},
                    },
                },
            },
        },
    };
};

const Arg = union {
    i: c_int,
    ui: c_uint,
    f: f32,
    v: *void,
};

const Rule = struct {
    title: ?[]const u8 = null,
    class: ?[]const u8 = null,
    instance: ?[]const u8 = null,

    name: ?[]const u8 = null,
    center: bool = false,
    floating: bool = false,
    container: ?u8 = null,
};

const Container = struct {
    x_start: f32,
    y_start: f32,
    x_end: f32,
    y_end: f32,
    children: []const Container,
    name: []const u8,
    ids: []const u8,

    fn getBounds(self: *const Container, parent: math.Rect(c_int)) math.Rect(c_int) {
        var result: math.Rect(c_int) = undefined;

        result.x = parent.x + if (self.x_start <= 1.0)
            @floatToInt(c_int, @intToFloat(f32, parent.w) * self.x_start)
        else
            @floatToInt(c_int, self.x_start);

        result.w = parent.x + if (self.x_end <= 1.0)
            @floatToInt(c_int, @intToFloat(f32, parent.w) * self.x_end)
        else
            @floatToInt(c_int, self.x_end);
        result.w -= result.x;

        result.y = parent.y + if (self.y_start <= 1.0)
            @floatToInt(c_int, @intToFloat(f32, parent.h) * self.y_start)
        else
            @floatToInt(c_int, self.y_start);

        result.h = parent.y + if (self.y_end <= 1.0)
            @floatToInt(c_int, @intToFloat(f32, parent.h) * self.y_end)
        else
            @floatToInt(c_int, self.y_end);
        result.h -= result.y;

        return result;
    }
};

const Signal = struct {
    signum: c_uint,
    func: *const fn (*const ?Arg) void,
    arg: ?Arg = null,
};

const Button = struct {
    pub const ClickTarget = enum {
        TagBar,
        LtSymbol,
        StatusText,
        BarIcon,
        FrameWin,
        ClientWin,
        RootWin,
    };

    target: ClickTarget,
    mask: c_uint = 0,
    button: c_uint,
    func: *const fn (*const ?Arg) void,
    arg: ?Arg = null,
};

const Layout = struct {
    symbol: []const u8,
    arrange: ?*const fn (*Monitor) void,
};

var numLockMask: c_uint = 0;

pub fn updateNumlockMask() void {
    numLockMask = 0;

    var modmap = c.XGetModifierMapping(dpy);
    for (0..8) |i| {
        for (0..@intCast(usize, modmap.*.max_keypermod)) |j| {
            if (modmap.*.modifiermap[i * @intCast(usize, modmap.*.max_keypermod) + j] == c.XKeysymToKeycode(dpy, c.XK_Num_Lock))
                numLockMask = std.math.pow(c_uint, 2, @intCast(c_uint, i));
        }
    }

    _ = c.XFreeModifiermap(modmap);
}

const BUTTON_MASK = c.ButtonPressMask | c.ButtonReleaseMask;
const MOUSE_MASK = BUTTON_MASK | c.PointerMotionMask;

const Client = struct {
    const Self = @This();

    // display info
    realname: []const u8 = "",
    name: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    container: u8 = CONFIG.defaultcontainer,

    // something
    mina: f32 = 0,
    maxa: f32 = 0,

    // bounds
    bounds: math.Rect(c_int),
    oldBounds: math.Rect(c_int),

    // constraints
    baseSize: math.Vector(c_int) = .{},
    incSize: math.Vector(c_int) = .{},
    minSize: math.Vector(c_int) = .{},
    maxSize: math.Vector(c_int) = .{},

    // border
    bw: c_int = CONFIG.borderpx,
    oldBw: c_int,

    // tags
    tags: u32 = 1,

    // flags
    flags: packed struct {
        lockname: bool = false,
        lockicon: bool = false,
        frame: bool = true,
        fixed: bool = false,
        centered: bool = false,
        floating: bool = false,
        urgent: bool = false,
        neverfocus: bool = false,
        fullscreen: bool = false,
        oldfullscreen: bool = false,
    },

    // pid for closing
    pid: c.pid_t,

    // x11 stuff
    win: c.Window,
    frame: c.Window = undefined,

    // pointers
    mon: *Monitor,

    pub fn sendMon(self: *Self, mon: *Monitor) void {
        if (self.mon == mon) return;

        var copy = self.*;

        self.unfocus(true);

        for (self.mon.clients.items, 0..) |*client, index| {
            if (client == self) {
                _ = self.mon.clients.orderedRemove(index);
                break;
            }
        }

        copy.mon.arrange();
        copy.mon = mon;
        mon.clients.append(copy) catch {};
        focusNone();
        copy.mon.arrange();
    }

    fn unmanage(self: *Self, destroyed: bool) void {
        const mon = self.mon;

        var wc: c.XWindowChanges = undefined;

        if (!destroyed) {
            self.unframe();
            wc.border_width = self.oldBw;
            _ = c.XGrabServer(dpy);
            _ = c.XSetErrorHandler(xerrordummy);
            _ = c.XConfigureWindow(dpy, self.win, c.CWBorderWidth, &wc);
            _ = c.XUngrabButton(dpy, c.AnyButton, c.AnyModifier, self.win);
            self.setState(c.WithdrawnState);
            _ = c.XSync(dpy, 0);
            _ = c.XSetErrorHandler(xerror);
            _ = c.XUngrabServer(dpy);
        }

        for (mon.clients.items, 0..) |*client, index| {
            if (client == self) {
                _ = mon.clients.orderedRemove(index);
                break;
            }
        }

        focusNone();
        mon.arrange();
        //TODO: updateclientlist();
    }

    fn unframe(self: *Self) void {
        _ = c.XUnmapWindow(dpy, self.frame);
        _ = c.XReparentWindow(dpy, self.win, root, 0, 0);
        _ = c.XRemoveFromSaveSet(dpy, self.win);
        _ = c.XDestroyWindow(dpy, self.frame);

        var wc: c.XWindowChanges = undefined;
        wc.border_width = self.oldBw;
        _ = c.XConfigureWindow(dpy, self.win, c.CWBorderWidth, &wc);
    }

    inline fn isVisible(self: *const Self) bool {
        return self.tags & self.mon.tagset[seltags] != 0;
    }

    fn subResize(self: *Self, bounds: math.Rect(c_int)) void {
        var wc: c.XWindowChanges = undefined;
        self.oldBounds = self.bounds;
        self.bounds = bounds;

        wc.x = self.bounds.x;
        wc.y = self.bounds.y;
        wc.width = self.bounds.w;
        wc.height = self.bounds.h;
        wc.border_width = self.bw;
        _ = c.XConfigureWindow(dpy, self.frame, c.CWX | c.CWY | c.CWWidth | c.CWHeight, &wc);

        wc.x = 0;
        wc.y = 0;
        wc.width = bounds.w;
        wc.height = bounds.h;
        if (self.flags.frame) {
            _ = c.XMoveResizeWindow(dpy, self.frame, self.bounds.x, self.bounds.y, @intCast(c_uint, self.bounds.w), @intCast(c_uint, self.bounds.h));
            _ = c.XMoveResizeWindow(dpy, self.win, 0, bh, @intCast(c_uint, bounds.w), @intCast(c_uint, bounds.h - bh));
            wc.y = bh;
            wc.height -= bh;
        } else {
            _ = c.XMoveResizeWindow(dpy, self.frame, self.bounds.x, self.bounds.y, @intCast(c_uint, self.bounds.w), @intCast(c_uint, self.bounds.h));
            _ = c.XMoveResizeWindow(dpy, self.win, 0, bh, @intCast(c_uint, bounds.w), @intCast(c_uint, bounds.h));
        }
        _ = c.XConfigureWindow(dpy, self.win, c.CWX | c.CWY | c.CWWidth | c.CWHeight, &wc);
        _ = c.XSetWindowBorderWidth(dpy, self.frame, @intCast(c_uint, self.bw));
        self.configure();
        _ = c.XSync(dpy, 0);
        self.drawFrame();
    }

    fn applySizeHints(self: *Self, bounds: *math.Rect(c_int), interact: bool) bool {
        const copy = self.bounds;

        bounds.w = @max(1, bounds.w);
        bounds.h = @max(1, bounds.h);
        if (interact) {
            if (bounds.x > screenDims.x) bounds.x = screenDims.x - self.bounds.w - self.bw * 2;
            if (bounds.y > screenDims.y) bounds.y = screenDims.y - self.bounds.h - self.bw * 2;
            if (bounds.x + bounds.w + 2 * self.bw < 0) bounds.x = 0;
            if (bounds.y + bounds.h + 2 * self.bw < 0) bounds.y = 0;
        } else {
            if (bounds.x >= self.mon.window.x + self.mon.window.w) bounds.x = self.mon.window.x + self.mon.window.w - self.bounds.w - self.bw * 2;
            if (bounds.y >= self.mon.window.y + self.mon.window.h) bounds.y = self.mon.window.y + self.mon.window.h - self.bounds.h - self.bw * 2;
        }

        return copy.x != bounds.x or copy.y != bounds.y or
            copy.w != bounds.w or copy.h != bounds.h;
    }

    fn resize(self: *Self, bounds: math.Rect(c_int), interact: bool) void {
        var copy = bounds;

        if (self.flags.floating) {
            if (self.applySizeHints(&copy, interact))
                self.subResize(copy);
        } else {
            self.subResize(copy);
        }
        self.configure();
        self.drawFrame();
    }

    fn focus(self: *Self) void {
        var client = self;
        if (!self.isVisible()) {
            for (selmon.clients.items) |*check| {
                client = check;
                if (client.isVisible()) break;
            }
        }

        if (selmon.sel) |sel|
            if (sel != client)
                sel.unfocus(false);

        if (!client.isVisible()) return;

        if (client.mon != selmon) selmon = client.mon;
        if (client.flags.urgent) client.flags.urgent = false;
        client.grabButtons(true);
        _ = c.XSetWindowBorder(dpy, client.frame, schemes.get(.Active)[2].pixel);
        client.setFocus();

        selmon.sel = client;
        drawBars();
    }

    fn setFocus(self: *Self) void {
        if (!self.flags.neverfocus) {
            _ = c.XSetInputFocus(dpy, self.win, c.RevertToPointerRoot, c.CurrentTime);
            _ = c.XChangeProperty(dpy, root, netatom.get(.ActiveWindow), c.XA_WINDOW, 32, c.PropModeReplace, @ptrCast([*c]const u8, &self.win), 1);
        }
        _ = sendEvent(self.win, wmatom.get(.TakeFocus), c.NoEventMask, .{ @intCast(c_long, wmatom.get(.TakeFocus)), c.CurrentTime, 0, 0, 0 });
    }

    fn grabButtons(self: *Self, focused: bool) void {
        updateNumlockMask();

        const modifiers = [_]c_uint{ 0, c.LockMask, numLockMask, numLockMask | c.LockMask };

        _ = c.XUngrabButton(dpy, c.AnyButton, c.AnyModifier, self.frame);
        if (!focused) {
            _ = c.XGrabButton(dpy, c.AnyButton, c.AnyModifier, self.frame, 0, BUTTON_MASK, c.GrabModeSync, c.GrabModeSync, c.None, c.None);
        }

        for (CONFIG.buttons) |button| {
            for (modifiers) |modMask| {
                if (button.target == .FrameWin)
                    _ = c.XGrabButton(dpy, button.button, button.mask | modMask, self.frame, 0, BUTTON_MASK, c.GrabModeSync, c.GrabModeSync, c.None, c.None)
                else if (button.target == .ClientWin)
                    _ = c.XGrabButton(dpy, button.button, button.mask | modMask, self.win, 0, BUTTON_MASK, c.GrabModeAsync, c.GrabModeSync, c.None, c.None);
            }
        }
    }

    fn unfocus(self: *Self, setfocus: bool) void {
        self.grabButtons(false);
        _ = c.XSetWindowBorder(dpy, self.frame, schemes.get(.Inactive)[2].pixel);
        self.drawFrame();
        if (setfocus) {
            _ = c.XSetInputFocus(dpy, root, c.RevertToPointerRoot, c.CurrentTime);
            _ = c.XDeleteProperty(dpy, root, netatom.get(.ActiveWindow));
        }
    }

    fn drawFrame(self: *Self) void {
        if (self.flags.frame) {
            var total: usize = 0;
            for (self.mon.clients.items) |client| {
                if (client.isVisible() and client.container == self.container and !client.flags.floating) total += 1;
            }

            if (CONFIG.frametabs and !self.flags.floating and total > 1) {
                const tabWidth = @divFloor(@intCast(usize, self.bounds.w + 2 * self.bw), total);
                var current: usize = 0;
                for (self.mon.clients.items) |*client| {
                    if (client.isVisible() and client.container == client.container and !client.flags.floating) {
                        drw.setScheme(schemes.get(if (client.mon.sel == client) .Active else .Inactive));

                        var icon: []const u8 = if (client.flags.floating) "F" else "T";
                        if (client.icon) |icn| icon = icn;

                        _ = drw.drawText(.{
                            .x = @intCast(c_int, current * tabWidth),
                            .y = 0,
                            .w = @intCast(c_int, tabWidth),
                            .h = bh,
                        }, 0, " ", false);
                        _ = drw.drawText(.{
                            .x = @intCast(c_int, current * tabWidth) + drw.sizeText(" "),
                            .y = 0,
                            .w = @intCast(c_int, tabWidth) - drw.sizeText(" "),
                            .h = bh,
                        }, 0, client.name orelse client.realname, false);
                        _ = drw.drawText(.{
                            .x = @intCast(c_int, (current + 1) * tabWidth) - drw.sizeText(" ") - drw.sizeText(icon),
                            .y = 0,
                            .w = @intCast(c_int, tabWidth),
                            .h = bh,
                        }, 0, icon, false);
                        if (current != 0)
                            drw.drawRect(.{
                                .x = @intCast(c_int, current * tabWidth),
                                .y = 0,
                                .w = @intCast(c_int, self.bw),
                                .h = bh,
                            }, .Border, false);
                        if (current != total - 1)
                            drw.drawRect(.{
                                .x = @intCast(c_int, (current + 1) * tabWidth) - self.bw,
                                .y = 0,
                                .w = @intCast(c_int, self.bw),
                                .h = bh,
                            }, .Border, false);
                        drw.drawRect(.{
                            .x = @intCast(c_int, current * tabWidth),
                            .y = bh - self.bw,
                            .w = @intCast(c_int, tabWidth),
                            .h = bh,
                        }, .Border, false);
                        current += 1;
                    }
                }
            } else {
                drw.setScheme(schemes.get(if (selmon.sel == self) .Active else .Inactive));
                drw.drawRect(.{
                    .x = 0,
                    .y = 0,
                    .w = self.bounds.w + 2 * self.bw,
                    .h = bh,
                }, .Fill, false);

                var icon: []const u8 = if (self.flags.floating) "F" else switch (self.container) {
                    1 => "A",
                    2 => "B",
                    3 => "C",
                    4 => "D",
                    else => "T",
                };

                if (self.icon) |icn| icon = icn;

                _ = drw.drawText(.{
                    .x = 0,
                    .y = 0,
                    .w = self.bounds.w + 2 * self.bw,
                    .h = self.bw,
                }, 0, " ", false);

                _ = drw.drawText(.{
                    .x = self.bounds.w - drw.sizeText(icon) - drw.sizeText(" "),
                    .y = 0,
                    .w = drw.sizeText(icon),
                    .h = bh - self.bw,
                }, 0, icon, false);

                _ = drw.drawText(.{
                    .x = 0,
                    .y = 0,
                    .w = self.bounds.w - drw.sizeText(" ") * 2,
                    .h = bh - self.bw,
                }, @intCast(c_uint, drw.sizeText(" ")), self.name orelse self.realname, false);

                drw.drawRect(.{
                    .x = 0,
                    .y = bh - self.bw,
                    .w = self.bounds.w,
                    .h = self.bw,
                }, .Frame, false);
            }

            drw.map(self.frame, .{ .x = 0, .y = 0, .w = self.bounds.w + 2 * self.bw, .h = bh });
        }
    }

    fn updateTitle(self: *Self) void {
        if (!self.flags.lockname) {
            if (getTextProp(self.win, netatom.get(.WMName))) |_| {
                self.realname = getTextProp(self.win, c.XA_WM_NAME) orelse CONFIG.broken;
            }
        } else {
            if (getTextProp(self.win, netatom.get(.WMName))) |_| {
                self.name = getTextProp(self.win, c.XA_WM_NAME) orelse CONFIG.broken;
            }
        }

        if (!self.flags.lockicon) {
            if (self.realname.len != 0)
                self.icon = self.realname[0..1];
        }

        self.drawFrame();
    }

    fn applyRules(self: *Self) void {
        self.flags.floating = false;
        self.tags = 0;

        var ch: c.XClassHint = .{ .res_class = null, .res_name = null };
        _ = c.XGetClassHint(dpy, self.win, &ch);
        const class = if (ch.res_class != null) ch.res_class[0..std.mem.len(ch.res_class)] else CONFIG.broken;
        const instance = if (ch.res_name != null) ch.res_name[0..std.mem.len(ch.res_name)] else CONFIG.broken;

        for (CONFIG.rules) |rule| {
            if ((rule.title == null or std.mem.eql(self.name, rule.title)) and
                (rule.class == null or std.mem.eql(class, rule.class)) and
                (rule.instance == null or std.mem.eql(instance, rule.instance)))
            {
                if (rule.name) |name| {
                    self.realname = name;
                    self.name = name;
                    self.flags.lockname = true;
                }
                if (rule.icon) |icon| {
                    self.icon = icon;
                    self.flags.lockicon = true;
                }
                if (rule.container) |container|
                    self.container = container;

                self.flags.centered = rule.center;
                self.flags.floating = rule.floating;
            }
        }

        self.tags = selmon.tagset[seltags];
    }

    fn createFrame(self: *Self) void {
        var at: c.XSetWindowAttributes = undefined;

        at.background_pixel = schemes.get(.Inactive)[2].pixel;
        at.background_pixmap = c.ParentRelative;
        at.override_redirect = 1;
        at.bit_gravity = c.StaticGravity;
        at.event_mask = c.EnterWindowMask | c.SubstructureRedirectMask | c.SubstructureNotifyMask | c.ExposureMask | c.VisibilityChangeMask;
        if (self.flags.frame) {
            self.frame = c.XCreateWindow(
                dpy,
                root,
                self.bounds.x,
                self.bounds.y,
                @intCast(c_uint, self.bounds.w),
                @intCast(c_uint, self.bounds.h + bh),
                @intCast(c_uint, self.bw),
                c.CopyFromParent,
                c.CopyFromParent,
                c.CopyFromParent,
                c.CWOverrideRedirect | c.CWBackPixmap | c.CWEventMask,
                &at,
            );
        } else {
            self.frame = c.XCreateWindow(
                dpy,
                root,
                self.bounds.x,
                self.bounds.y,
                @intCast(c_uint, self.bounds.w),
                @intCast(c_uint, self.bounds.h),
                @intCast(c_uint, self.bw),
                c.CopyFromParent,
                c.CopyFromParent,
                c.CopyFromParent,
                c.CWOverrideRedirect | c.CWBackPixmap | c.CWEventMask,
                &at,
            );
        }

        _ = c.XAddToSaveSet(dpy, self.win);
        _ = c.XReparentWindow(dpy, self.win, self.frame, 0, bh);
        _ = c.XMapWindow(dpy, self.frame);
    }

    fn updateWindowType(self: *Self) void {
        _ = self;
        // TODO: implement
    }

    fn updateSizeHints(self: *Self) void {
        var size: c.XSizeHints = undefined;
        var msize: c_long = undefined;

        if (c.XGetWMNormalHints(dpy, self.win, &size, &msize) == 0) size.flags = c.PSize;

        if (size.flags & c.PBaseSize != 0) {
            self.baseSize.x = size.base_width;
            self.baseSize.y = size.base_height;
        } else if (size.flags & c.PMinSize != 0) {
            self.baseSize.x = size.min_width;
            self.baseSize.y = size.min_height;
        }

        if (size.flags & c.PMinSize != 0) {
            self.minSize.x = size.min_width;
            self.minSize.y = size.min_height;
        } else if (size.flags & c.PBaseSize != 0) {
            self.minSize.x = size.base_width;
            self.minSize.y = size.base_height;
        }

        if (size.flags & c.PAspect != 0) {
            self.mina = @intToFloat(f32, size.min_aspect.y) / @intToFloat(f32, size.min_aspect.x);
            self.maxa = @intToFloat(f32, size.max_aspect.y) / @intToFloat(f32, size.max_aspect.x);
        }

        self.flags.fixed = self.maxSize.x != 0 and self.maxSize.y != 0 and self.minSize.x == self.maxSize.x and self.minSize.y == self.maxSize.y;
    }

    fn setState(self: *Self, state: c_long) void {
        var data = [_]c_long{ state, c.None };

        _ = c.XChangeProperty(dpy, self.win, wmatom.get(.State), wmatom.get(.State), 32, c.PropModeReplace, @ptrCast(*const u8, &data), 2);
    }

    fn updateWMHints(self: *Self) void {
        _ = self;
        // TODO: implement
    }

    pub fn configure(self: *Self) void {
        if (self.flags.floating)
            self.flags.frame = !self.flags.fullscreen;

        var ce: c.XEvent = .{
            .xconfigure = .{
                .type = c.ConfigureNotify,
                .display = dpy,
                .event = self.frame,
                .window = self.frame,
                .x = self.bounds.x + self.bw,
                .y = self.bounds.y + self.bw,
                .width = self.bounds.w,
                .height = self.bounds.h - if (self.flags.frame) bh - self.bw else 0,
                .border_width = self.bw,
                .above = c.None,
                .override_redirect = 0,
                .serial = undefined,
                .send_event = undefined,
            },
        };

        _ = c.XSendEvent(dpy, self.frame, 0, c.StructureNotifyMask, &ce);
    }
};

const Monitor = struct {
    const Self = @This();

    num: usize,

    // bar position
    bary: c_int,

    // rects
    bounds: math.Rect(c_int),
    window: math.Rect(c_int),

    // layout stuff
    sellt: u32,
    tagset: [2]u32,
    showbar: bool,
    topbar: bool,

    clients: std.ArrayList(Client),
    order: std.ArrayList(*Client),
    sel: ?*Client,
    barwin: c.Window,
    lt: []const Layout,
    ltsymbol: []const u8,

    pub fn init() !Self {
        return .{
            .num = 0,
            .bary = undefined,
            .bounds = undefined,
            .tagset = .{ 1, 1 },
            .showbar = false,
            .topbar = CONFIG.topbar,
            .lt = &.{
                .{ .arrange = bud(0, 0, &CONFIG.containers), .symbol = "[+]" },
                .{ .arrange = bud(20, 20, &CONFIG.containers), .symbol = "-+-" },
                .{ .arrange = null, .symbol = "><>" },
            },
            .ltsymbol = "><>",
            .sellt = 0,
            .clients = std.ArrayList(Client).init(allocator),
            .order = std.ArrayList(*Client).init(allocator),
            .sel = null,
            .barwin = 0,
            .window = undefined,
        };
    }

    pub fn updateBarPos(self: *Self) void {
        self.updateBar();

        self.window.y = self.bounds.y;
        self.window.h = self.bounds.h;
        if (self.showbar) {
            self.window.h -= bh;
            self.bary = if (self.topbar) self.bounds.y else self.bounds.y + self.bounds.h;
            self.window.y = if (self.topbar) self.window.y + bh else self.window.y;
        } else {
            self.bary = -bh;
        }

        _ = c.XMoveResizeWindow(dpy, self.barwin, self.window.x, self.bary, @intCast(c_uint, self.window.w), @intCast(c_uint, bh));

        self.arrange();
    }

    pub fn updateBar(self: *Self) void {
        if (self.barwin != 0) return;

        var wa: c.XSetWindowAttributes = undefined;
        wa.override_redirect = 1;
        wa.background_pixmap = c.ParentRelative;
        wa.event_mask = c.ButtonPressMask | c.ExposureMask;

        var ch: c.XClassHint = .{
            .res_name = @constCast("conwm"),
            .res_class = @constCast("conwm"),
        };

        // TODO: systray

        self.barwin = c.XCreateWindow(dpy, root, self.window.x, self.bary, @intCast(c_uint, self.window.w), @intCast(c_uint, bh), 0, c.DefaultDepth(dpy, screen), c.CopyFromParent, c.DefaultVisual(dpy, screen), c.CWOverrideRedirect | c.CWBackPixmap | c.CWEventMask, &wa);
        _ = c.XDefineCursor(dpy, self.barwin, cursor.get(.Normal).cursor);
        _ = c.XMapRaised(dpy, self.barwin);
        _ = c.XSetClassHint(dpy, self.barwin, &ch);
    }

    pub fn arrange(self: *Self) void {
        if (self.lt[self.sellt].arrange) |arranger|
            arranger(self);

        self.restack();
    }

    pub fn restack(self: *Self) void {
        if (self.sel) |sel| {
            if (sel.flags.floating or self.lt[self.sellt].arrange != null) {
                _ = c.XRaiseWindow(dpy, sel.frame);
            }
            if (self.lt[self.sellt].arrange != null) {
                var wc: c.XWindowChanges = undefined;
                wc.stack_mode = c.Below;
                wc.sibling = self.barwin;
                for (self.clients.items) |client| {
                    if (!client.flags.floating and client.isVisible()) {
                        _ = c.XConfigureWindow(dpy, client.frame, c.CWSibling | c.CWStackMode, &wc);
                        wc.sibling = client.frame;
                    }
                }
            }
            _ = c.XSync(dpy, 0);
            var ev: c.XEvent = undefined;
            while (c.XCheckMaskEvent(dpy, c.EnterWindowMask, &ev) != 0) {}
        }
    }
};

var mons: std.ArrayList(Monitor) = undefined;
var dpy: ?*c.Display = null;
var root: c.Window = undefined;
var drw: drawer.Drawer = undefined;
var screen: c_int = 0;
var screenDims: math.Vector(c_int) = undefined;
var lrpad: c_int = 0;
var bh: c_int = 0;
var selmon: *Monitor = undefined;
var seltags: u32 = 1;
var utf8string: c.Atom = undefined;
var running: bool = true;
var restart: bool = false;

var handler: std.AutoHashMap(c_int, *const fn (*c.XEvent) void) = undefined;

const Cursors = enum {
    Normal,
    Resize,
    Moving,
};

const WMAtoms = enum {
    Protocols,
    Delete,
    State,
    TakeFocus,
    Floating,
};

const NETAtoms = enum {
    Supported,
    WMName,
    WMState,
    WMCheck,
    SystemTray,
    SystemTrayOP,
    SystemTrayOrientation,
    SystemTrayOrientationHorz,
    WMFullscreen,
    ActiveWindow,
    WMWindowType,
    WMWindowTypeDialog,
    ClientList,
    DesktopNames,
    DesktopViewport,
    NumberOfDesktops,
    CurrentDesktop,
};

const Schemes = enum {
    Inactive,
    Active,
};

var schemes = std.EnumArray(Schemes, [3]drawer.Clr).initUndefined();
var cursor = std.EnumArray(Cursors, drawer.Cur).initUndefined();
var wmatom = std.EnumArray(WMAtoms, c.Atom).initUndefined();
var netatom = std.EnumArray(NETAtoms, c.Atom).initUndefined();

var xcon: ?*c.xcb_connection_t = null;
var xerrorxlib: ?*const fn (?*c.Display, [*c]c.XErrorEvent) callconv(.C) c_int = null;

pub fn die(comptime msg: []const u8, args: anytype) noreturn {
    std.debug.print(msg ++ "\n", args);
    std.os.exit(0);
}

pub fn xerrordummy(_: ?*c.Display, _: ?*c.XErrorEvent) callconv(.C) c_int {
    return 0;
}

pub fn xerror(display: ?*c.Display, ee: ?*c.XErrorEvent) callconv(.C) c_int {
    if (ee.?.request_code == c.X_CopyArea and ee.?.error_code == c.BadDrawable) return 0;

    return xerrorxlib.?(display, ee);
}

pub fn xerrorstart(_: ?*c.Display, _: [*c]c.XErrorEvent) callconv(.C) c_int {
    die("budwm: another window manager is already running", .{});
    return -1;
}

pub fn checkOtherWM() !void {
    xerrorxlib = c.XSetErrorHandler(xerrorstart);
    // causes error if other wm is running
    _ = c.XSelectInput(dpy, c.DefaultRootWindow(dpy), c.SubstructureRedirectMask);
    _ = c.XSync(dpy, 0);
    _ = c.XSetErrorHandler(xerror);
    _ = c.XSync(dpy, 0);
}

pub fn xrdbLoadColor(xrdb: c.XrmDatabase, name: []const u8, color: *[]const u8) !void {
    var value: c.XrmValue = undefined;
    var kind: [*c]u8 = undefined;

    _ = color;

    if (c.XrmGetResource(xrdb, name.ptr, null, &kind, &value) == 1) {
        if (value.addr != null and c.strnlen(value.addr, 8) == 7 and value.addr[0] == '#') {
            // TODO: finish
        }
    }
}

pub fn loadxrdb() !void {
    if (c.XOpenDisplay(null)) |display| {
        if (c.XResourceManagerString(display)) |resm| {
            if (c.XrmGetStringDatabase(resm)) |xrdb| {
                try xrdbLoadColor(xrdb, "budwm.normbordercolor", &CONFIG.normbordercolor);
                // TODO: finish
            }
        }
    }
}

fn getTextProp(window: c.Window, atom: c.Atom) ?[]const u8 {
    var name: c.XTextProperty = undefined;

    var result: []const u8 = "";

    if (c.XGetTextProperty(dpy, window, &name, atom) == 0 or name.nitems == 0) return null;
    if (name.encoding == c.XA_STRING) {
        result = allocator.dupe(u8, name.value[0..std.mem.len(name.value)]) catch return null;
    } else {
        var list: [*c][*c]u8 = undefined;
        var n: c_int = 0;
        if (c.XmbTextPropertyToTextList(dpy, &name, &list, &n) >= c.Success and n > 0 and list.?.* != null) {
            result = allocator.dupe(u8, list.*[0..std.mem.len(list.*)]) catch return null;
            c.XFreeStringList(list);
        }
    }
    _ = c.XFree(name.value);

    return result;
}

fn drawBars() void {
    for (selmon.clients.items) |*client|
        client.drawFrame();
    // TODO: implement
}

fn focusNone() void {
    _ = c.XSetInputFocus(dpy, root, c.RevertToPointerRoot, c.CurrentTime);
    _ = c.XDeleteProperty(dpy, root, netatom.get(.ActiveWindow));

    selmon.sel = null;
    drawBars();
}

pub fn isUniqueGeom(unique: []c.XineramaScreenInfo, check: c.XineramaScreenInfo) bool {
    for (unique) |item| {
        if (item.x_org == check.x_org and item.y_org == check.y_org and
            item.width == check.width and item.height == check.height) return false;
    }

    return true;
}

pub fn updateGeom() !bool {
    var dirty = false;

    if (c.XineramaIsActive(dpy) != 0) {
        var nn: c_int = 0;
        var info = c.XineramaQueryScreens(dpy, &nn);

        const n = mons.items.len;

        var unique = try allocator.alloc(c.XineramaScreenInfo, @intCast(usize, nn));
        var uidx: usize = 0;
        for (info, 0..@intCast(usize, nn)) |item, _| {
            if (isUniqueGeom(unique[0..uidx], item)) {
                unique[uidx] = item;
                uidx += 1;
            }
        }
        _ = c.XFree(info);

        if (n <= uidx) {
            for (0..(uidx - n)) |_| {
                try mons.append(try Monitor.init());
            }
        } else {
            try mons.resize(uidx);
        }

        for (mons.items, 0..) |*mon, idx| {
            if (idx >= n or
                unique[idx].x_org != mon.bounds.x or unique[idx].y_org != mon.bounds.y or
                unique[idx].width != mon.bounds.w or unique[idx].height != mon.bounds.h)
            {
                dirty = true;
                mon.num = idx;

                mon.bounds.x = unique[idx].x_org;
                mon.bounds.y = unique[idx].y_org;
                mon.bounds.w = unique[idx].width;
                mon.bounds.h = unique[idx].height;

                mon.window.x = unique[idx].x_org;
                mon.window.y = unique[idx].y_org;
                mon.window.w = unique[idx].width;
                mon.window.h = unique[idx].height;

                mon.updateBarPos();
            }
        }
    }

    if (dirty) {
        selmon = &mons.items[0];
    }

    return dirty;
}

pub fn setup() !void {
    // clean zombies
    //c.sigchld(0);

    // TODO: implement
    //c.signal(c.SIGHUP, sighup);
    //c.signal(c.SIGTERM, sigterm);

    screen = c.DefaultScreen(dpy);
    screenDims.x = c.DisplayWidth(dpy, screen);
    screenDims.y = c.DisplayHeight(dpy, screen);
    root = c.RootWindow(dpy, screen);
    drw = drawer.Drawer.init(allocator, dpy, screen, root, screenDims);
    if (!try drw.fontsetCreate(&.{"CaskaydiaCovePL Nerd Font:size=10"})) {
        die("no fonts could be loaded", .{});
    }

    lrpad = drw.fonts.items[0].h;
    bh = drw.fonts.items[0].h + 2;

    mons = std.ArrayList(Monitor).init(allocator);
    _ = try updateGeom();

    for (mons.items) |*monitor| {
        monitor.updateBar();
    }

    var arg: ?Arg = null;

    toggleBar(&arg);

    utf8string = c.XInternAtom(dpy, "UTF8_STRING", 0);

    wmatom.getPtr(.Protocols).* = c.XInternAtom(dpy, "WM_PROTOCOLS", 0);
    wmatom.getPtr(.Delete).* = c.XInternAtom(dpy, "WM_DELETE_WINDOW", 0);
    wmatom.getPtr(.State).* = c.XInternAtom(dpy, "WM_STATE", 0);
    wmatom.getPtr(.TakeFocus).* = c.XInternAtom(dpy, "WM_TAKE_FOCUS", 0);
    wmatom.getPtr(.Floating).* = c.XInternAtom(dpy, "WM_IS_FLOATING", 0);

    schemes.getPtr(.Active).* = drw.createScheme(CONFIG.colors[0]);
    schemes.getPtr(.Inactive).* = drw.createScheme(CONFIG.colors[1]);

    netatom.getPtr(.ActiveWindow).* = c.XInternAtom(dpy, "_NET_ACTIVE_WINDOW", 0);
    netatom.getPtr(.Supported).* = c.XInternAtom(dpy, "_NET_SUPPORTED", 0);
    netatom.getPtr(.SystemTray).* = c.XInternAtom(dpy, "_NET_SYSTEM_TRAY_S0", 0);
    netatom.getPtr(.SystemTrayOP).* = c.XInternAtom(dpy, "_NET_SYSTEM_TRAY_OPCODE", 0);
    netatom.getPtr(.SystemTrayOrientation).* = c.XInternAtom(dpy, "_NET_SYSTEM_TRAY_ORIENTATION", 0);
    netatom.getPtr(.SystemTrayOrientationHorz).* = c.XInternAtom(dpy, "_NET_SYSTEM_TRAY_ORIENTATION_HORZ", 0);
    netatom.getPtr(.WMName).* = c.XInternAtom(dpy, "_NET_WM_NAME", 0);
    netatom.getPtr(.WMState).* = c.XInternAtom(dpy, "_NET_WM_STATE", 0);
    netatom.getPtr(.WMCheck).* = c.XInternAtom(dpy, "_NET_SUPPORTING_WM_CHECK", 0);
    netatom.getPtr(.WMFullscreen).* = c.XInternAtom(dpy, "_NET_WM_STATE_FULLSCREEN", 0);
    netatom.getPtr(.WMWindowType).* = c.XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", 0);
    netatom.getPtr(.WMWindowTypeDialog).* = c.XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DIALOG", 0);
    netatom.getPtr(.ClientList).* = c.XInternAtom(dpy, "_NET_CLIENT_LIST", 0);
    netatom.getPtr(.DesktopViewport).* = c.XInternAtom(dpy, "_NET_DESKTOP_VIEWPORT", 0);
    netatom.getPtr(.NumberOfDesktops).* = c.XInternAtom(dpy, "_NET_NUMBER_OF_DESKTOPS", 0);
    netatom.getPtr(.CurrentDesktop).* = c.XInternAtom(dpy, "_NET_CURRENT_DESKTOP", 0);
    netatom.getPtr(.DesktopNames).* = c.XInternAtom(dpy, "_NET_DESKTOP_NAMES", 0);

    cursor.getPtr(.Normal).* = drawer.Cur.init(&drw, c.XC_left_ptr);
    cursor.getPtr(.Resize).* = drawer.Cur.init(&drw, c.XC_sizing);
    cursor.getPtr(.Moving).* = drawer.Cur.init(&drw, c.XC_fleur);

    // TODO: finish

    _ = c.XDeleteProperty(dpy, root, netatom.get(.ClientList));

    var wa: c.XSetWindowAttributes = undefined;

    // select events
    wa.cursor = cursor.get(.Normal).cursor;
    wa.event_mask = c.SubstructureRedirectMask | c.SubstructureNotifyMask |
        c.ButtonPressMask | c.PointerMotionMask | c.EnterWindowMask |
        c.LeaveWindowMask | c.StructureNotifyMask | c.PropertyChangeMask;
    _ = c.XChangeWindowAttributes(dpy, root, c.CWEventMask | c.CWCursor, &wa);
    _ = c.XSelectInput(dpy, root, wa.event_mask);
}

pub fn getRootPtr(x: *c_int, y: *c_int) i32 {
    var di: c_int = undefined;
    var dui: c_uint = undefined;
    var dummy: c.Window = undefined;

    return c.XQueryPointer(dpy, root, &dummy, &dummy, x, y, &di, &di, &dui);
}

pub fn rectToMon(rect: math.Rect(c_int)) *Monitor {
    var area: i32 = 0;
    var result: *Monitor = selmon;

    for (mons.items) |*mon| {
        var a = mon.bounds.intersect(rect);
        if (a > area) {
            area = a;
            result = mon;
        }
    }

    return result;
}

pub fn winToMon(w: c.Window) *Monitor {
    var rect: math.Rect(c_int) = .{
        .x = 0,
        .y = 0,
        .w = 1,
        .h = 1,
    };

    if (w == root and getRootPtr(&rect.x, &rect.y) != 0) return rectToMon(rect);
    for (mons.items) |*mon| {
        if (w == mon.barwin) return mon;
    }

    if (winToClient(w)) |client| return client.mon;

    return selmon;
}

pub fn winToClient(w: c.Window) ?*Client {
    for (mons.items) |mon| {
        for (mon.clients.items) |*client| {
            if (client.frame == w) return client;
            if (client.win == w) return client;
        }
    }

    return null;
}

pub fn buttonpress(e: *c.XEvent) void {
    const ev = &e.xbutton;

    var m = winToMon(ev.window);
    if (m != selmon) {
        if (selmon.sel) |sel| sel.unfocus(true);
        selmon = m;
        focusNone();
    }

    // TODO: bar click
    var target: Button.ClickTarget = .RootWin;

    if (winToClient(ev.window)) |aClient| {
        var client = aClient;

        target = .ClientWin;
        if (ev.y < bh and client.flags.frame) {
            target = .FrameWin;
            if (!client.flags.floating) {
                var totalTabs: i32 = 0;
                for (client.mon.clients.items) |cb| {
                    if (cb.isVisible() and cb.container == client.container and !cb.flags.floating)
                        totalTabs += 1;
                }
                const tabWidth = @divFloor(client.bounds.w + 2 * client.bw, totalTabs);
                var cur: i32 = 0;
                for (client.mon.clients.items) |*cb| {
                    if (cb.isVisible() and cb.container == client.container and !cb.flags.floating) {
                        cur = cur + 1;
                        if (ev.x < cur * tabWidth) {
                            client = cb;
                            break;
                        }
                    }
                }
            }
        }
        client.focus();
        selmon.restack();
        _ = c.XAllowEvents(dpy, c.ReplayPointer, c.CurrentTime);
    }

    for (CONFIG.buttons) |button| {
        if (target == button.target and button.button == ev.button and button.mask == ev.state) {
            button.func(&button.arg);
            return;
        }
    }
}

pub fn updateStatus() void {
    // TODO: implement
}

pub fn propertyNotify(e: *c.XEvent) void {
    const ev = &e.xproperty;

    if ((ev.window == root) and (ev.atom == c.XA_WM_NAME)) {
        if (!fakeSignal())
            updateStatus();
    }
    // TODO: finish
}

pub fn unmapnotify(e: *c.XEvent) void {
    const ev = &e.xunmap;

    if (winToClient(ev.window)) |client| {
        if (ev.send_event != 0)
            client.setState(c.WithdrawnState)
        else
            client.unmanage(false);
    }
}

pub fn enternotify(e: *c.XEvent) void {
    const ev = &e.xcrossing;

    if ((ev.mode != c.NotifyNormal or ev.detail == c.NotifyInferior) and ev.window != root) return;
    const client = winToClient(ev.window);
    var mon = if (client != null) client.?.mon else winToMon(ev.window);
    if (mon != selmon) {
        if (selmon.sel) |sel|
            sel.unfocus(true);
        selmon = mon;
    } else if (client == null or client == selmon.sel) return;

    if (client) |sel|
        sel.focus();
}

pub fn configurerequest(e: *c.XEvent) void {
    const ev = &e.xconfigurerequest;

    if (winToClient(ev.window)) |client| {
        if (ev.value_mask & c.CWBorderWidth != 0) {
            client.bw = ev.border_width;
        } else if (client.flags.floating or selmon.lt[selmon.sellt].arrange == null) {
            var mon = client.mon;
            _ = mon;
            // TODO: finish
        } else {
            client.configure();
        }
    } else {
        var wc: c.XWindowChanges = undefined;
        wc.x = ev.x;
        wc.y = ev.y;
        wc.width = ev.width;
        wc.height = ev.height;
        wc.border_width = ev.border_width;
        wc.stack_mode = ev.detail;
        _ = c.XConfigureWindow(dpy, ev.window, @intCast(c_uint, ev.value_mask), &wc);
    }

    _ = c.XSync(dpy, 0);
    // TODO: finish
}

pub fn winToSystrayIcon(window: c.Window) ?*Client {
    _ = window;

    return null;
}

pub fn winpid(window: c.Window) c.pid_t {
    _ = window;
    return 0;
}

pub fn manage(window: c.Window, wa: *c.XWindowAttributes) void {
    var client: Client = .{
        .win = window,
        .pid = winpid(window),
        .bounds = .{
            .x = wa.x,
            .y = wa.y,
            .w = wa.width,
            .h = wa.height,
        },
        .oldBounds = .{
            .x = wa.x,
            .y = wa.y,
            .w = wa.width,
            .h = wa.height,
        },
        .oldBw = wa.border_width,
        .mon = selmon,
        .flags = .{},
    };

    client.updateTitle();

    var trans: c.Window = undefined;

    if (c.XGetTransientForHint(dpy, window, &trans) != 0) {
        if (winToClient(trans)) |t| {
            client.mon = t.mon;
            client.tags = t.tags;
        }
    }

    if (client.flags.floating) client.flags.frame = true;

    if (client.bounds.x + client.bounds.w > client.mon.bounds.x + client.mon.bounds.w)
        client.bounds.x = client.mon.bounds.x + client.mon.bounds.w - client.bounds.w;
    if (client.bounds.y + client.bounds.h > client.mon.bounds.y + client.mon.bounds.h)
        client.bounds.y = client.mon.bounds.y + client.mon.bounds.y - client.bounds.h;
    client.bounds.x = @max(client.bounds.x, client.mon.bounds.x);
    //TODO:   c->y = MAX(c->y, ((c->mon->by == c->mon->my) && (c->x + (c->w / 2) >= c->mon->wx)
    //        && (c->x + (c->w / 2) < c->mon->wx + c->mon->ww)) ? bh : c->mon->my);

    if (client.flags.centered) {
        client.bounds.x = @divFloor((client.mon.bounds.w - client.bounds.w), 2);
        client.bounds.y = @divFloor((client.mon.bounds.h - client.bounds.h), 2);
        client.bounds.x += client.mon.bounds.x;
        client.bounds.y += client.mon.bounds.y;
    }

    client.applyRules();
    client.createFrame();

    _ = c.XSetWindowBorder(dpy, client.frame, schemes.get(.Inactive)[2].pixel);
    client.configure();
    client.updateWindowType();
    client.updateSizeHints();
    client.updateWMHints();

    _ = c.XSelectInput(dpy, client.win, c.EnterWindowMask | c.FocusChangeMask | c.PropertyChangeMask | c.StructureNotifyMask);

    client.grabButtons(false);

    if (client.flags.floating)
        _ = c.XRaiseWindow(dpy, client.frame);

    _ = c.XChangeProperty(dpy, root, netatom.get(.ClientList), c.XA_WINDOW, 32, c.PropModeAppend, @ptrCast(*const u8, &(client.win)), 1);
    client.setState(c.NormalState);

    if (client.mon == selmon)
        if (selmon.sel) |sel|
            sel.unfocus(false);

    _ = c.XMapWindow(dpy, client.win);

    client.resize(client.bounds, true);
    client.drawFrame();

    focusNone();
    var floating = .{client.flags.floating};

    _ = c.XChangeProperty(dpy, client.win, wmatom.get(.Floating), c.XA_CARDINAL, 8, c.PropModeReplace, @ptrCast(*const u8, &(floating)), 1);

    selmon.clients.append(client) catch {};

    client.mon.arrange();
}

pub fn maprequest(e: *c.XEvent) void {
    const ev = &e.xmaprequest;

    if (winToSystrayIcon(ev.window)) |icon| {
        _ = icon;

        // TODO: finish
    }

    var wa: c.XWindowAttributes = undefined;

    if (c.XGetWindowAttributes(dpy, ev.window, &wa) == 0) return;
    if (wa.override_redirect != 0) return;

    if (winToClient(ev.window) == null)
        manage(ev.window, &wa);
}

pub fn run() !void {
    handler = std.AutoHashMap(c_int, *const fn (*c.XEvent) void).init(allocator);

    try handler.put(c.ButtonPress, buttonpress);
    try handler.put(c.ConfigureRequest, configurerequest);
    try handler.put(c.EnterNotify, enternotify);
    try handler.put(c.MapRequest, maprequest);
    try handler.put(c.UnmapNotify, unmapnotify);
    try handler.put(c.PropertyNotify, propertyNotify);
    //try handler.put(c.MotionNotify, motionnotify);

    var ev: c.XEvent = undefined;

    _ = c.XSync(dpy, 0);
    while (running and c.XNextEvent(dpy, &ev) == 0) {
        if (handler.get(ev.type)) |handle|
            handle(&ev);
    }
}

pub fn sendEvent(window: c.Window, proto: c.Atom, mask: c_int, data: [5]c_long) bool {
    var mt: c.Atom = undefined;
    var protocols: [*c]c.Atom = undefined;

    var n: c_int = 0;
    var exists: bool = false;

    var ev: c.XEvent = undefined;

    if (proto == wmatom.get(.TakeFocus) or proto == wmatom.get(.Delete)) {
        if (c.XGetWMProtocols(dpy, window, &protocols, &n) != 0) {
            mt = wmatom.get(.Protocols);
            while (!exists and n != 0) {
                exists = protocols[@intCast(usize, n)] == proto;
                n -= 1;
            }
            _ = c.XFree(protocols);
        }
    } else {
        exists = true;
        mt = proto;
    }

    if (exists) {
        ev.type = c.ClientMessage;
        ev.xclient.window = window;
        ev.xclient.message_type = mt;
        ev.xclient.format = 32;
        ev.xclient.data.l[0] = data[0];
        ev.xclient.data.l[1] = data[1];
        ev.xclient.data.l[2] = data[2];
        ev.xclient.data.l[3] = data[3];
        ev.xclient.data.l[4] = data[4];
        _ = c.XSendEvent(dpy, window, 0, mask, &ev);
    }

    return exists;
}

pub fn killClient(_: *const ?Arg) void {
    if (selmon.sel) |sel| {
        if (!sendEvent(sel.win, wmatom.get(.Delete), c.NoEventMask, .{ @intCast(c_long, wmatom.get(.Delete)), c.CurrentTime, 0, 0, 0 })) {
            sel.unframe();
            _ = c.XGrabServer(dpy);
            _ = c.XSetErrorHandler(xerrordummy);
            _ = c.XSetCloseDownMode(dpy, c.DestroyAll);
            _ = c.XKillClient(dpy, sel.win);
            _ = c.XSync(dpy, 0);
            _ = c.XSetErrorHandler(xerror);
            _ = c.XUngrabServer(dpy);
        }
    }
}

pub fn quit(arg: *const ?Arg) void {
    if (arg.*) |argument| {
        if (argument.i != 0) restart = true;
    }
    running = false;
}

pub fn toggleBar(_: *const ?Arg) void {
    selmon.showbar = !selmon.showbar;
    selmon.updateBarPos();
}

pub fn toggleFloating(_: *const ?Arg) void {
    if (selmon.sel) |client| {
        client.flags.floating = !client.flags.floating;

        var floating = .{client.flags.floating};
        _ = c.XChangeProperty(dpy, client.win, wmatom.get(.Floating), c.XA_CARDINAL, 8, c.PropModeReplace, @ptrCast(*const u8, &(floating)), 1);
    }
    selmon.arrange();
}

pub fn setContainer(arg: *const ?Arg) void {
    if (arg.*) |argument| {
        if (selmon.sel) |client| {
            client.flags.floating = false;
            client.container = @intCast(u8, argument.i);

            var floating = .{client.flags.floating};

            _ = c.XChangeProperty(dpy, client.win, wmatom.get(.Floating), c.XA_CARDINAL, 8, c.PropModeReplace, @ptrCast(*const u8, &(floating)), 1);
        }
        selmon.arrange();
    }
}

pub fn resizeMouse(_: *const ?Arg) void {
    if (selmon.sel) |selected| {
        if (selected.flags.fullscreen) return;

        const ocx = selected.bounds.x;
        const ocy = selected.bounds.y;

        var pos: math.Vector(c_int) = undefined;
        if (c.XGrabPointer(dpy, root, 0, MOUSE_MASK, c.GrabModeAsync, c.GrabModeAsync, c.None, cursor.get(.Moving).cursor, c.CurrentTime) != c.GrabSuccess) return;
        if (getRootPtr(&pos.x, &pos.y) == 0) return;
        var ev: c.XEvent = undefined;
        var lasttime: c.Time = 0;

        selected.flags.floating = true;

        var floating = .{selected.flags.floating};
        _ = c.XChangeProperty(dpy, selected.win, wmatom.get(.Floating), c.XA_CARDINAL, 8, c.PropModeReplace, @ptrCast(*const u8, &(floating)), 1);

        selmon.arrange();

        while (true) {
            _ = c.XMaskEvent(dpy, MOUSE_MASK | c.ExposureMask | c.SubstructureRedirectMask, &ev);
            switch (ev.type) {
                c.ConfigureRequest, c.Expose, c.MapRequest => {
                    if (handler.get(ev.type)) |handle| handle(&ev);
                },
                c.MotionNotify => {
                    if ((ev.xmotion.time - lasttime) <= (1000 / 60)) continue;
                    lasttime = ev.xmotion.time;

                    const nw = @max(ev.xmotion.x - ocx - 2 * selected.bw + 1, 1 + bh);
                    const nh = @max(ev.xmotion.y - ocy - 2 * selected.bw + 1, 1 + bh);
                    // TODO: snap
                    if (selmon.lt[selmon.sellt].arrange == null or selected.flags.floating)
                        selected.resize(.{
                            .x = selected.bounds.x,
                            .y = selected.bounds.y,
                            .w = nw,
                            .h = nh,
                        }, true);
                },
                c.ButtonRelease => break,
                else => {},
            }
        }
        _ = c.XUngrabPointer(dpy, c.CurrentTime);
        var m = rectToMon(selected.bounds);
        if (m != selmon) {
            selected.sendMon(m);
            selmon = m;
            focusNone();
        }
    }
}

pub fn moveMouse(_: *const ?Arg) void {
    if (selmon.sel) |selected| {
        if (selected.flags.fullscreen) return;

        const ocx = selected.bounds.x;
        const ocy = selected.bounds.y;

        var pos: math.Vector(c_int) = undefined;
        if (c.XGrabPointer(dpy, root, 0, MOUSE_MASK, c.GrabModeAsync, c.GrabModeAsync, c.None, cursor.get(.Moving).cursor, c.CurrentTime) != c.GrabSuccess) return;
        if (getRootPtr(&pos.x, &pos.y) == 0) return;
        var ev: c.XEvent = undefined;
        var lasttime: c.Time = 0;

        selected.flags.floating = true;

        var floating = .{selected.flags.floating};
        _ = c.XChangeProperty(dpy, selected.win, wmatom.get(.Floating), c.XA_CARDINAL, 8, c.PropModeReplace, @ptrCast(*const u8, &(floating)), 1);

        selmon.arrange();

        while (true) {
            _ = c.XMaskEvent(dpy, MOUSE_MASK | c.ExposureMask | c.SubstructureRedirectMask, &ev);
            switch (ev.type) {
                c.ConfigureRequest, c.Expose, c.MapRequest => {
                    if (handler.get(ev.type)) |handle| handle(&ev);
                },
                c.MotionNotify => {
                    if ((ev.xmotion.time - lasttime) <= (1000 / 60)) continue;
                    lasttime = ev.xmotion.time;

                    const nx = ocx + (ev.xmotion.x - pos.x);
                    const ny = ocy + (ev.xmotion.y - pos.y);
                    // TODO: snap
                    if (selmon.lt[selmon.sellt].arrange == null or selected.flags.floating)
                        selected.resize(.{
                            .x = nx,
                            .y = ny,
                            .w = selected.bounds.w,
                            .h = selected.bounds.h,
                        }, true);
                },
                c.ButtonRelease => break,
                else => {},
            }
        }
        _ = c.XUngrabPointer(dpy, c.CurrentTime);
        var m = rectToMon(selected.bounds);
        if (m != selmon) {
            selected.sendMon(m);
            selmon = m;
            focusNone();
        }
    }
}

pub fn bud(comptime igapps: i32, comptime ogapps: i32, comptime containers: *const Container) (fn (*Monitor) void) {
    return struct {
        pub fn getSizeInContainer(target: u8, currentSize: math.Rect(c_int), container: *const Container, usage: [containers.ids.len]bool) math.Rect(c_int) {
            var result = currentSize;
            if (container.ids.len == 1 and container.ids[0] == target) return result;

            var childrenUsed: u8 = 0;
            var idsUsed: u8 = 0;
            for (container.ids) |id| {
                if (usage[id - 1]) idsUsed += 1;
            }

            for (container.children) |child| {
                var good: bool = false;
                for (child.ids) |id| {
                    if (usage[id - 1]) {
                        good = true;
                    }
                }
                if (good)
                    childrenUsed += 1;
            }

            std.log.info("cur: {s}, targ: {}, idsUsed: {}, childrenUsed: {}, usage: {any}", .{ container.name, target, idsUsed, childrenUsed, usage });

            if (idsUsed == 1) return result;
            for (container.children) |*child| {
                if (std.mem.containsAtLeast(u8, child.ids, 1, &.{target})) {
                    if (childrenUsed != 1)
                        result = child.getBounds(result);
                    return getSizeInContainer(target, result, child, usage);
                }
            }

            unreachable;
        }

        pub fn budImpl(mon: *Monitor) void {
            var containerUsage = [_]bool{false} ** containers.ids.len;

            for (mon.clients.items) |*client| {
                if (client.mon == mon and (client.tags & mon.tagset[seltags]) != 0) {
                    if (!client.flags.floating and !client.flags.fullscreen)
                        containerUsage[client.container - 1] = true;
                }
            }

            var win = mon.window;
            win.x += ogapps;
            win.y += ogapps;
            win.w -= ogapps * 2;
            win.h -= ogapps * 2;

            for (mon.clients.items) |*client| {
                if (client.mon == mon and (client.tags & mon.tagset[seltags]) != 0 and (!client.flags.floating and !client.flags.fullscreen)) {
                    var new = getSizeInContainer(client.container, win, containers, containerUsage);
                    new.x += igapps;
                    new.y += igapps;
                    new.w -= igapps * 2;
                    new.h -= igapps * 2;
                    client.flags.frame = new.y != mon.window.y or !client.mon.showbar;

                    new.w -= client.bw * 2;
                    new.h -= client.bw * 2;

                    client.resize(new, false);
                }
            }
        }
    }.budImpl;
}

fn fakeSignal() bool {
    const indicator = "fsignal:";

    if (getTextProp(root, c.XA_WM_NAME)) |fsignal| {
        if (std.mem.startsWith(u8, fsignal, indicator)) {
            var sigString = fsignal[indicator.len..];
            var sigNum = std.fmt.parseInt(c_uint, sigString, 0) catch return false;

            for (CONFIG.signals) |signal| {
                if (signal.signum == sigNum) {
                    signal.func(&signal.arg);

                    return true;
                }
            }
            std.log.info("{s} ignored", .{fsignal});
        }
    }

    return false;
}

pub fn main() !void {
    // argument iterator
    var args = try std.process.ArgIterator.initWithAllocator(allocator);

    // ignore first arg
    _ = args.next();

    // get args
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-v")) {
            die("conwm-{s}", .{VERSION});
        } else {
            die("usage: conwm [-v]", .{});
        }
    }

    if (c.setlocale(c.LC_CTYPE, "") == null or c.XSupportsLocale() == 0)
        std.log.warn("no locale support", .{});

    dpy = c.XOpenDisplay(null);
    if (dpy == null) die("cannot open display", .{});
    xcon = c.XGetXCBConnection(dpy);
    if (xcon == null) die("cannot get xcb connection", .{});

    try checkOtherWM();
    c.XrmInitialize();
    try loadxrdb();
    try setup();
    //TODO: scan

    try run();

    // deinit
    for (mons.items) |*mon| {
        for (mon.clients.items) |*client| {
            client.unmanage(false);
        }
        mon.clients.deinit();
    }
    mons.deinit();

    if (restart) {
        var arguments: [][]const u8 = try allocator.alloc([]const u8, std.os.argv.len);
        for (arguments, std.os.argv) |*dest, src| {
            dest.* = src[0..std.mem.len(src)];
        }
        std.process.execv(allocator, arguments) catch {};
    }

    // FIXME: cleanup();
    _ = c.XCloseDisplay(dpy);
}
