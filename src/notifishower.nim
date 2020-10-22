import docopt
import strutils, sequtils, tables
import imlib2
import x11 / [x, xlib, xutil, xatom, xrandr]

let doc = """
Notifishower 0.1.0

This is a simple program to display a combinations of text and images as a
notification on the screen. It also allows the user to interact with the
notification and the program will report back which action was triggered. It
does not read freedesktop notifications, for that you might want to check out
notificatcher.

Usage:
  notifishower [options]
  notifishower [-x <x> -y <y>] [options]
  notifishower [-x <x> -y <y>] (--text <tid> <text> [--font <font>])... [options]
  notifishower (--monitor <name> [-x <x> -y <y>])... [options]
  notifishower (--monitor <name> [-x <x> -y <y>])... (--text <tid> <text> [--font <font>])... [options]

Options:
  --help                     Show this screen
  -v --version               Show the version
  --class <class>            Set the window class [default: notishower]
  --name <name>              Set the window name [default: Notishower]
  --monitor <name>           Sets the monitor to display on
  -x <x>                     Set the x position of the notification [default: 0]
  -y <y>                     Set the y position of the notification [default: 0]
  -w --width <w>             Set the width of the notification [default: 200]
  -h --height <h>            Set the height of the notification [default: 100]
  --background <color>       Set the background colour of the notification
  --border <color>           Set the border colour of the notification
  --borderWidth <bw>         Set the width of the border [default: 0]
  --font <font>              Set the font to draw the message in
  --text <tid> <text>        Store a text element with a given ID
  --image <iid> <path>       Store an image element with a given ID
"""

converter intToCint(x: int): cint = x.cint
converter intToCuint(x: int): cuint = x.cuint
converter pintToPcint(x: ptr int): ptr cint = cast[ptr cint](x)
converter boolToXBool(x: bool): XBool = x.XBool
converter xboolToBool(x: XBool): bool = x.bool

import os
echo commandLineParams()
let args = docopt(doc, version = "Notifishower 0.1.0")
echo args

var
  disp: PDisplay
  vis: PVisual
  cm: Colormap
  depth: int
  ev: XEvent
  font: ImlibFont
  #mouseX, mouseY: int
  windows: Table[Window, tuple[w, h: int, updates: ImlibUpdates]]
  vinfo: XVisualInfo
  background: tuple[r, g, b, a: int]

type
  Screen = object
    name: string
    primary: bool
    id: int
    x, y: int
    w, h: int
    mmh: int
var
  randrMajorVersion, randrMinorVersion: int
  screens: seq[Screen]

proc randrInit() =
  var ignored: int
  if XRRQueryExtension(disp, ignored.addr, ignored.addr) == 0:
    stderr.writeLine("Could not initialize the RandR extension. " &
          "Falling back to single monitor mode.");
    return
  discard XRRQueryVersion(disp, randr_major_version.addr, randr_minor_version.addr)
  XRRSelectInput(disp, RootWindow(disp, DefaultScreen(disp)), RRScreenChangeNotifyMask)

proc screenUpdateFallback() =
  let count = XScreenCount(disp)
  reset screens
  for screen in 0..<count:
    screens.add Screen(
      id: screen,
      w: DisplayWidth(disp, screen),
      h: DisplayHeight(disp, screen))

proc randr_update() =
  if randr_major_version < 1 or
    (randr_major_version == 1 and randr_minor_version < 5):
    stderr.writeLine("Server RandR version too low (" & $randrMajorVersion & "." & $randrMinorVersion & "). " &
                "Falling back to single monitor mode.");
    screenUpdateFallback()
    return

  var n = 0
  let m = XRRGetMonitors(disp, RootWindow(disp, DefaultScreen(disp)), true, n.addr)

  if (n < 1):
    stderr.writeLine("Get monitors reported " & $n & " monitors. " &
      "Falling back to single monitor mode.")
    screenUpdateFallback()
    return

  reset screens
  for i in 0..<n:
    screens.add(Screen(
      id: i,
      name: $disp.XGetAtomName(m[i].name),
      primary: m[i].primary,
      x: m[i].x,
      y: m[i].y,
      w: m[i].width,
      h: m[i].height,
      mmh: m[i].mheight))

  XRRFreeMonitors(m)

proc screen_check_event(ev: PXEvent): bool =
  if XRRUpdateConfiguration(ev) != 0:
    stderr.writeLine("XEvent: processing 'RRScreenChangeNotify'")
    randr_update()
    return true
  return false

disp  = XOpenDisplay(nil)
vis   = DefaultVisual(disp, DefaultScreen(disp))
depth = DefaultDepth(disp, DefaultScreen(disp))
cm    = DefaultColormap(disp, DefaultScreen(disp))

# Use this to be able to select monitor
randrInit()
randrUpdate()
echo screens

# Prepare common window attributes
discard XMatchVisualInfo(disp, DefaultScreen(disp), 32, TrueColor, vinfo.addr) == 1 or
        XMatchVisualInfo(disp, DefaultScreen(disp), 24, TrueColor, vinfo.addr) == 1 or
        XMatchVisualInfo(disp, DefaultScreen(disp), 16, DirectColor, vinfo.addr) == 1 or
        XMatchVisualInfo(disp, DefaultScreen(disp), 8, PseudoColor, vinfo.addr) == 1

var bgColor = $args["--background"]
if bgColor != "nil":
  let s = if bgColor[0..1].toLower == "0x": 2 else: 0
  background.r = parseHexInt(bgColor[s..s+1])
  background.g = parseHexInt(bgColor[s+2..s+3])
  background.b = parseHexInt(bgColor[s+4..s+5])
  background.a = 255
  if bgColor.len > 6:
    background.a = parseHexInt(bgColor[s+6..s+7])

var wa: XSetWindowAttributes
wa.overrideRedirect = true
wa.backgroundPixmap = None
wa.backgroundPixel = if $args["--background"] != "nil": parseHexInt($args["--background"]).uint else: 0
wa.borderPixel = if $args["--border"] != "nil": parseHexInt($args["--border"]).uint else: 0
#wa.colormap = XCreateColormap(disp, DefaultRootWindow(disp), vis, AllocNone)
wa.colormap = XCreateColormap(disp, DefaultRootWindow(disp), vinfo.visual, AllocNone)
wa.eventMask =
    ExposureMask or KeyPressMask or VisibilityChangeMask or
    ButtonReleaseMask or FocusChangeMask or StructureNotifyMask

# Set up Imlib stuff
let homedir = getEnv("HOME")
if homedir.len != 0:
  imlib_add_path_to_font_path(homedir & "/.local/share/fonts")
  imlib_add_path_to_font_path(homedir & "/.fonts")
imlib_add_path_to_font_path("/usr/local/share/fonts")
imlib_add_path_to_font_path("/usr/share/fonts/truetype")
imlib_add_path_to_font_path("/usr/share/fonts/truetype/dejavu")
imlib_add_path_to_font_path("/usr/share/fonts/TTF")
imlib_set_cache_size(2048 * 1024)
imlib_set_font_cache_size(512 * 1024)
imlib_set_color_usage(128)
imlib_context_set_dither(1)
imlib_context_set_display(disp)
imlib_context_set_visual(vinfo.visual)
imlib_context_set_colormap(wa.colormap)

font = imlib_load_font(if $args["--font"] != "nil": $args["--font"] else: "DejaVuSans/20")
imlib_context_set_font(font);
imlib_context_set_color(255, 0, 0, 255);
#var text = $args["<message>"]
#var textW, textH: int
#imlib_get_text_size(text[0].addr, textW.addr, textH.addr)
#imlib_free_font()
#echo (textW: textW, textH: textH)

let
  width = if $args["--width"] != "nil": parseInt($args["--width"]) else: 200
  height = if $args["--height"] != "nil": parseInt($args["--height"]) else: 100
  wneg = ($args["--width"])[0] == '-'
  hneg = ($args["--height"])[0] == '-'

for screen in screens:
  let
    monitors = args["--monitor"].mapIt($it)
    monitorPos = monitors.find(screen.name)
    # TODO: Detect active monitor and allow a follow active mode
  if args["--monitor"].len == 0 or monitorPos > -1:
    let
      borderWidth = parseInt($args["--borderWidth"])
      xinput =
        if args["--monitor"].len == 0 and $args["-x"] != "nil": parseInt($args["-x"])
        elif monitorPos > -1: parseInt($(args["-x"][monitorPos]))
        else: 0
      yinput =
        if (args["--monitor"].len == 0 and $args["-y"] != "nil"): parseInt($args["-y"])
        elif monitorPos > -1: parseInt($(args["-y"][monitorPos]))
        else: 0
      xneg =
        if args["--monitor"].len == 0: ($args["-x"])[0] == '-'
        elif monitorPos > -1: ($(args["-x"][monitorPos]))[0] == '-'
        else: false
      yneg =
        if args["--monitor"].len == 0: ($args["-y"])[0] == '-'
        elif monitorPos > -1: ($(args["-y"][monitorPos]))[0] == '-'
        else: false
      winWidth = if wneg: screen.w + width else: width
      winHeight = if hneg: screen.h + height else: height
      xpos = screen.x + (if xneg: screen.w - winWidth - borderWidth*2 + xinput else: xinput)
      ypos = screen.y + (if yneg: screen.h - winHeight - borderWidth*2 + yinput else: yinput)

    let win = XCreateWindow(disp, DefaultRootWindow(disp), xpos, ypos, winWidth,
      winHeight, borderWidth, vinfo.depth, InputOutput, vinfo.visual,
      CWOverrideRedirect or CWBackPixmap or CWBackPixel or CWBorderPixel or
      CWColormap or CWEventMask, wa.addr)
    echo win
    windows[win] = (w: winWidth, h: winHeight, updates: nil)
    # tell X what events we are interested in
    discard XSelectInput(disp, win, ButtonPressMask or ButtonReleaseMask or
                PointerMotionMask or ExposureMask);
    # show the window
    discard XMapWindow(disp, win)

    # set window title and class
    var
      title = $args["--name"]
      classhint = XClassHint(resName: $args["--class"], resClass: "Notishower")
    discard XStoreName(disp, win, title)
    discard XChangeProperty(disp, win, XInternAtom(disp, "_NET_WM_NAME", false),
      XInternAtom(disp, "UTF8_STRING", false), 8, PropModeReplace, title[0].addr,
      title.len)
    discard XSetClassHint(disp, win, classhint.addr)

    # set window type
    let net_wm_window_type = XInternAtom(disp, "_NET_WM_WINDOW_TYPE", false)

    var data = [
      XInternAtom(disp, "_NET_WM_WINDOW_TYPE_NOTIFICATION", false),
      XInternAtom(disp, "_NET_WM_WINDOW_TYPE_UTILITY", false)
    ]
    discard XChangeProperty(disp, win, net_wm_window_type, XA_ATOM, 32,
      PropModeReplace, cast[ptr cuchar](data.addr), 2)

    # set state above
    let netWmState = XInternAtom(disp, "_NET_WM_STATE", false);
    data[0] = XInternAtom(disp, "_NET_WM_STATE_ABOVE", false)
    discard XChangeProperty(disp, win, netWmState, XA_ATOM, 32,
            PropModeReplace, cast[ptr cuchar](data.addr), 1)

echo windows

template doWhile(condition, action: untyped): untyped =
  action
  while condition:
    action

while true:
  doWhile(XPending(disp) > 0):
    discard XNextEvent(disp, ev.addr)
    case ev.theType:
    of Expose:
      windows[ev.xexpose.window].updates = imlib_update_append_rect(
        windows[ev.xexpose.window].updates,
        ev.xexpose.x, ev.xexpose.y,
        ev.xexpose.width, ev.xexpose.height)
    else:
      discard screenCheckEvent(ev.addr)

  for win, value in windows.mpairs:
    value.updates = imlib_updates_merge_for_rendering(value.updates, value.w, value.h);
    var currentUpdate = value.updates
    while currentUpdate != nil:
      imlib_context_set_drawable(win)
      var up_x, up_y, up_w, up_h: int

      # find out where the first update is
      imlib_updates_get_coordinates(currentUpdate,
                                    up_x.addr, up_y.addr, up_w.addr, up_h.addr);

      echo (win: win, upX: upX, upY: upY, upW: upW, upH: upH)

      # create our buffer image for rendering this update
      var buffer = imlib_create_image(up_w, up_h);
      # set the image
      imlib_context_set_image(buffer)
      imlib_image_set_has_alpha(1)

      imlib_context_set_blend(1)
      imlib_context_set_color(background.r, background.g, background.b, background.a)
      imlib_image_fill_rectangle(0,0, value.w, value.h)

      # draw text - centered with the current mouse x, y
      #font = imlib_load_font(if $args["--font"] != "nil": $args["--font"] else: "DejaVuSans/20")
      #if font != nil:
      #  # set the current font
      #  imlib_context_set_font(font);
      #  # set the color (black)
      #  imlib_context_set_color(255, 0, 0, 255);
      #  # print text to display in the buffer
      #  var text = $args["<message>"]
      #  # query the size it will be
      #  var textW, textH: int
      #  imlib_get_text_size(text[0].addr, textW.addr, textH.addr)
      #  # draw it
      #  imlib_text_draw((value.w div 2) - (text_w div 2) - up_x, (value.h div 2) - (text_h div 2) - up_y, text[0].addr)
      #  # free the font
      #  imlib_free_font()
      #else:
      #  echo "No font"

      # don't blend the image onto the drawable - slower
      imlib_context_set_blend(0)
      # set the buffer image as our current image
      imlib_context_set_image(buffer)
      # render the image at 0, 0
      imlib_render_image_on_drawable(up_x, up_y)
      # don't need that temporary buffer image anymore
      imlib_free_image()
      currentUpdate = imlib_updates_get_next(currentUpdate)

    # if we had updates - free them
    if value.updates != nil:
       imlib_updates_free(value.updates)
       value.updates = nil

