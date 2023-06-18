const std = @import("std");
const math = @import("math.zig");
const c = @import("c.zig");

pub const Cur = struct {
    const Self = @This();

    cursor: c.Cursor,

    pub fn init(drw: *Drawer, shape: c_uint) Self {
        return .{
            .cursor = c.XCreateFontCursor(drw.dpy, shape),
        };
    }
};

pub const Clr = c.XftColor;
const ColFg = 0;
const ColBg = 1;
const ColBorder = 2;

pub const Fnt = struct {
    const Self = @This();

    dpy: ?*c.Display,
    h: c_int,
    xfont: ?*c.XftFont,
    pattern: ?*c.FcPattern,

    pub fn getExts(font: *Fnt, text: []const u8, w: ?*c_uint, h: ?*c_uint) void {
        var ext: c.XGlyphInfo = undefined;

        _ = c.XftTextExtentsUtf8(font.dpy, font.xfont, text.ptr, @intCast(c_int, text.len), &ext);

        if (w) |ww|
            ww.* = @intCast(c_uint, ext.xOff);
        if (h) |hh|
            hh.* = @intCast(c_uint, font.h);
    }

    pub fn init(drw: *Drawer, fontname: ?[]const u8, fontpattern: ?*c.FcPattern) ?Self {
        var xfont: ?*c.XftFont = null;
        var pattern: ?*c.FcPattern = null;

        if (fontname) |name| {
            xfont = c.XftFontOpenName(drw.dpy, drw.screen, name.ptr);
            if (xfont == null) {
                std.log.err("cannot load font from name: '{s}'", .{name});
                return null;
            }
            pattern = c.FcNameParse(name.ptr);
            if (pattern == null) {
                std.log.err("cannot parse font name to pattern: '{s}'", .{name});
                c.XftFontClose(drw.dpy, xfont);
                return null;
            }
        } else if (fontpattern) |patt| {
            xfont = c.XftFontOpenPattern(drw.dpy, patt);
            if (xfont == null) {
                std.log.err("cannot load font from pattern", .{});
                return null;
            }
        } else {
            return null;
        }

        var iscol: c.FcBool = undefined;

        if (c.FcPatternGetBool(xfont.?.pattern, c.FC_COLOR, 0, &iscol) == c.FcResultMatch and iscol != 0) {
            c.XftFontClose(drw.dpy, xfont);
            return null;
        }

        return .{
            .xfont = xfont,
            .pattern = pattern,
            .h = xfont.?.ascent + xfont.?.descent,
            .dpy = drw.dpy,
        };
    }
};

pub const Drawer = struct {
    const Self = @This();

    dpy: ?*c.Display,
    screen: c_int,
    root: c.Window,
    dims: math.Vector(c_int),
    drawable: c.Drawable,
    gc: c.GC,
    fonts: std.ArrayList(Fnt),
    scheme: [3]Clr = undefined,

    pub fn init(allocator: std.mem.Allocator, dpy: ?*c.Display, screen: c_int, root: c.Window, dims: math.Vector(c_int)) Self {
        var drawable = c.XCreatePixmap(dpy, root, @intCast(c_uint, dims.x), @intCast(c_uint, dims.y), @intCast(c_uint, c.DefaultDepth(dpy, screen)));
        var gc = c.XCreateGC(dpy, root, 0, null);
        _ = c.XSetLineAttributes(dpy, gc, 1, c.LineSolid, c.CapButt, c.JoinMiter);

        return .{
            .dpy = dpy,
            .screen = screen,
            .root = root,
            .dims = dims,
            .drawable = drawable,
            .gc = gc,
            .fonts = std.ArrayList(Fnt).init(allocator),
        };
    }

    const UTF_INVALID = 0xFFFD;

    pub fn utf8decode(text: []const u8, u: *u32) u3 {
        var len = std.unicode.utf8ByteSequenceLength(text[0]) catch 1;

        u.* = std.unicode.utf8Decode(text[0..len]) catch 0;

        return len;
    }

    pub fn sizeText(self: *Self, text: []const u8) c_int {
        return self.drawText(.{ .x = 0, .y = 0, .w = 0, .h = 0 }, 0, text, false);
    }

    pub fn drawText(self: *Self, bnds: math.Rect(c_int), lpad: c_uint, txt: []const u8, invert: bool) c_int {
        const render = bnds.x != 0 or bnds.y != 0 or bnds.w != 0 or bnds.h != 0;

        var bounds = bnds;
        var text = txt;

        _ = c.XSetForeground(self.dpy, self.gc, self.scheme[if (invert) ColFg else ColBg].pixel);
        _ = c.XFillRectangle(self.dpy, self.drawable, self.gc, bounds.x, bounds.y, @intCast(c_uint, bounds.w), @intCast(c_uint, bounds.h));
        const d = c.XftDrawCreate(
            self.dpy,
            self.drawable,
            c.DefaultVisual(self.dpy, self.screen),
            c.DefaultColormap(self.dpy, self.screen),
        );
        bounds.x += @intCast(c_int, lpad);
        bounds.w -= @intCast(c_int, lpad);

        var utf8str: []const u8 = undefined;
        var utf8codepoint: u32 = undefined;

        var nextfont: ?Fnt = null;
        var curfont: ?Fnt = null;
        var usedfont: ?Fnt = self.fonts.items[0];
        var charexists: bool = false;
        var fccharset: ?*c.FcCharSet = undefined;
        var fcpattern: ?*c.FcPattern = undefined;
        var match: ?*c.FcPattern = undefined;
        var result: c.XftResult = undefined;

        while (true) {
            utf8str = text;
            utf8str.len = 0;

            while (text.len != 0) {
                const utf8charlen = utf8decode(text, &utf8codepoint);
                for (self.fonts.items) |font| {
                    curfont = font;

                    charexists = charexists or c.XftCharExists(self.dpy, curfont.?.xfont, utf8codepoint) != 0;
                    if (charexists) {
                        var same = ((curfont == null) and (usedfont == null));
                        if (curfont != null and usedfont != null) same = same or curfont.?.xfont == usedfont.?.xfont;

                        if (same) {
                            utf8str.len += utf8charlen;
                            text = text[utf8charlen..];
                        } else {
                            nextfont = curfont;
                        }

                        break;
                    }
                }

                if (!charexists or nextfont != null)
                    break
                else
                    charexists = false;
            }

            if (utf8str.len != 0) {
                var ew: c_uint = 0;

                usedfont.?.getExts(utf8str, &ew, null);

                var ty = bounds.y + @divFloor((bounds.h - usedfont.?.h), 2) + usedfont.?.xfont.?.ascent;

                if (render) c.XftDrawStringUtf8(d, &self.scheme[if (invert) ColBg else ColFg], usedfont.?.xfont, bounds.x, ty, utf8str.ptr, @intCast(c_int, utf8str.len));

                bounds.x += @intCast(c_int, ew);
                bounds.w -= @intCast(c_int, ew);
            }

            if (text.len == 0) break else if (nextfont != null) {
                usedfont = nextfont.?;
                charexists = false;
            } else {
                charexists = true;

                fccharset = c.FcCharSetCreate();
                _ = c.FcCharSetAddChar(fccharset, utf8codepoint);

                fcpattern = c.FcPatternDuplicate(self.fonts.items[0].pattern);
                _ = c.FcPatternAddCharSet(fcpattern, c.FC_CHARSET, fccharset);
                _ = c.FcPatternAddBool(fcpattern, c.FC_SCALABLE, c.FcTrue);
                _ = c.FcPatternAddBool(fcpattern, c.FC_COLOR, c.FcFalse);

                _ = c.FcConfigSubstitute(null, fcpattern, c.FcMatchPattern);
                _ = c.FcDefaultSubstitute(fcpattern);
                match = c.XftFontMatch(self.dpy, self.screen, fcpattern, &result);

                _ = c.FcCharSetDestroy(fccharset);
                _ = c.FcPatternDestroy(fcpattern);

                if (match != null) {
                    usedfont = Fnt.init(self, null, match);
                    if (usedfont != null and c.XftCharExists(self.dpy, usedfont.?.xfont, utf8codepoint) != 0) {
                        self.fonts.append(usedfont.?) catch return bounds.x;
                    } else {
                        //xfont_free(usedfont);
                        curfont = self.fonts.items[0];
                    }
                }
            }
        }

        return bounds.x + if (render) bounds.w else 0;
    }

    const FillType = enum { Frame, Fill, Border };

    pub fn drawRect(self: *Self, bounds: math.Rect(c_int), filled: FillType, invert: bool) void {
        switch (filled) {
            .Frame => {
                _ = c.XSetForeground(self.dpy, self.gc, self.scheme[if (invert) ColFg else ColBg].pixel);
                _ = c.XDrawRectangle(self.dpy, self.drawable, self.gc, bounds.x, bounds.y, @intCast(c_uint, bounds.w - 1), @intCast(c_uint, bounds.h - 1));
            },
            .Fill => {
                _ = c.XSetForeground(self.dpy, self.gc, self.scheme[if (invert) ColFg else ColBg].pixel);
                _ = c.XFillRectangle(self.dpy, self.drawable, self.gc, bounds.x, bounds.y, @intCast(c_uint, bounds.w), @intCast(c_uint, bounds.h));
            },
            .Border => {
                _ = c.XSetForeground(self.dpy, self.gc, self.scheme[ColBorder].pixel);
                _ = c.XFillRectangle(self.dpy, self.drawable, self.gc, bounds.x, bounds.y, @intCast(c_uint, bounds.w), @intCast(c_uint, bounds.h));
            },
        }
    }

    pub fn fontsetCreate(self: *Self, fonts: []const []const u8) !bool {
        var result = false;

        for (fonts) |fontname| {
            if (Fnt.init(self, fontname, null)) |adds| {
                try self.fonts.append(adds);
                result = true;
            }
        }

        return result;
    }

    pub fn createScheme(self: *Self, names: [3]*[]const u8) [3]Clr {
        var result: [3]Clr = undefined;

        for (names, 0..) |name, idx| {
            _ = c.XftColorAllocName(
                self.dpy,
                c.DefaultVisual(self.dpy, self.screen),
                c.DefaultColormap(self.dpy, self.screen),
                name.*.ptr,
                &result[idx],
            );
        }

        return result;
    }

    pub fn map(self: *Self, window: c.Window, bounds: math.Rect(c_int)) void {
        _ = c.XCopyArea(self.dpy, self.drawable, window, self.gc, bounds.x, bounds.y, @intCast(c_uint, bounds.w), @intCast(c_uint, bounds.h), bounds.x, bounds.y);
        _ = c.XSync(self.dpy, 0);
    }

    pub inline fn setScheme(self: *Self, scm: [3]Clr) void {
        self.scheme = scm;
    }
};
