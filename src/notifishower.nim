import os, tables
import layout, options, ninepatch
import imlib2
import x11 / [x, xlib, xutil, xrandr, xatom]

converter intToCint(x: int): cint = x.cint
converter intToCuint(x: int): cuint = x.cuint
converter pintToPcint(x: ptr int): ptr cint = cast[ptr cint](x)
converter boolToXBool(x: bool): XBool = x.XBool
converter xboolToBool(x: XBool): bool = x.bool

var args: Options
args.background = Color(r: 68, g: 68, b: 68, a: 255)
args.border = Color(r: 128, g: 128, b: 128, a: 255)
args.borderWidth = 2
args.x = 49
args.y = 0
args.w = -98
args.h = 0
args.hopt = ">="
args.defaultFont = "DejaVuSans/10"
args.format = "(-[~icon:32~]-[~title body~]-)"
args.text["title"] = Text(font: "DejaVuSans/12", color: Color(r: 255, g: 255, b: 255, a: 255))
args.text["body"] = Text(color: Color(r: 255, g: 255, b: 255, a: 255))
args.images["icon"] = Image()
args.padding = 8
args = parseCommandLine(defaults = args)
for _, text in args.text.mpairs:
  if text.font.len == 0:
    text.font = args.defaultFont

var
  disp: PDisplay
  vis: PVisual
  cm: Colormap
  depth: int
  ev: XEvent
  windows: Table[Window, tuple[w, h: int, updates: ImlibUpdates, layout: Pack]]
  vinfo: XVisualInfo
  bgNinepatch: Ninepatch

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

# Prepare common window attributes
discard XMatchVisualInfo(disp, DefaultScreen(disp), 32, TrueColor, vinfo.addr) == 1 or
        XMatchVisualInfo(disp, DefaultScreen(disp), 24, TrueColor, vinfo.addr) == 1 or
        XMatchVisualInfo(disp, DefaultScreen(disp), 16, DirectColor, vinfo.addr) == 1 or
        XMatchVisualInfo(disp, DefaultScreen(disp), 8, PseudoColor, vinfo.addr) == 1

var wa: XSetWindowAttributes
wa.overrideRedirect = true
wa.backgroundPixmap = None
wa.backgroundPixel = 0
wa.borderPixel = ((args.border.a shl 24) or (args.border.r shl 16) or (args.border.g shl 8) or args.border.b).uint
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

if args.ninepatch.len != 0:
  bgNinepatch = imlib_load_ninepatch(args.ninepatch)
  if bgNinepatch.image == args.ninepatch:
    bgNinepatch.tile = args.ninepatchTile
    let
      dx = bgNinepatch.startDx
      dy = bgNinepatch.startDy
      dw = bgNinepatch.dwidth
      dh = bgNinepatch.dheight
    args.format = "(-" & $dx & "-[-" & $dy & "-" & args.format & "-" & $dh & "-]-" & $ $dw & "-)"

var texts, images: Table[string, tuple[w, h: int]]
for name, text in args.text:
  var loadedFont = imlib_load_font(text.font)
  texts[name] = (1, 1)
  imlib_context_set_font(loadedFont)
  if text.text.len > 0:
    imlib_get_text_size(text.text[0].unsafeAddr, texts[name].w.addr, texts[name].h.addr)
  imlib_free_font()

for name, image in args.images:
  if image.image.len > 0:
    var image = imlib_load_image(image.image)
    if image == nil:
      args.images[name].image = ""
      images[name] = (1, 1)
    else:
      imlib_context_set_image(image)
      images[name] = (imlib_image_get_width().int, imlib_image_get_height().int)
      imlib_free_image()
  else:
    images[name] = (1, 1)

for screen in screens:
  # TODO: Detect active monitor and allow a follow active mode
  if args.monitors.len == 0 or args.monitors.hasKey(screen.name):
    let
      borderWidth = args.borderWidth
      xinput =
        if args.monitors.hasKey(screen.name) and args.monitors[screen.name].x != int.high:
          args.monitors[screen.name].x
        else: args.x
      yinput =
        if args.monitors.hasKey(screen.name) and args.monitors[screen.name].y != int.high:
          args.monitors[screen.name].y
        else: args.y
      width =
        if args.monitors.hasKey(screen.name) and args.monitors[screen.name].w != int.high:
          args.monitors[screen.name].w
        else: args.w
      height =
        if args.monitors.hasKey(screen.name) and args.monitors[screen.name].h != int.high:
          args.monitors[screen.name].h
        else: args.h
      winWidth = if width < 0: screen.w + width else: width
      winHeight = if height < 0: screen.h + height else: height
      layout = parseLayout(args.format, (args.wopt, winWidth), (args.hopt, winHeight), args.padding, texts, images)
      xpos = screen.x + (if xinput < 0: screen.w - layout.width.value.int - borderWidth*2 + xinput + 1 else: xinput)
      ypos = screen.y + (if yinput < 0: screen.h - layout.height.value.int - borderWidth*2 + yinput + 1 else: yinput)
      win = XCreateWindow(disp, DefaultRootWindow(disp), xpos, ypos, layout.width.value.int,
        layout.height.value.int, borderWidth, vinfo.depth, InputOutput, vinfo.visual,
        CWOverrideRedirect or CWBackPixmap or CWBackPixel or CWBorderPixel or
        CWColormap or CWEventMask, wa.addr)
    windows[win] = (w: layout.width.value.int, h: layout.height.value.int, updates: nil, layout: layout)

    discard XSelectInput(disp, win, ButtonPressMask or ButtonReleaseMask or
                PointerMotionMask or ExposureMask);
    discard XMapWindow(disp, win)

    # set window title and class
    var
      title = if args.name.len == 0: "notifishower" else: args.name
      classhint = XClassHint(resName: if args.class.len == 0: "notifishower" else: args.class, resClass: "Notishower")
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

      # create our buffer image for rendering this update
      var buffer = imlib_create_image(up_w, up_h);
      imlib_context_set_image(buffer)
      imlib_image_set_has_alpha(1)
      imlib_context_set_blend(1)
      imlib_image_clear()
      imlib_context_set_color(args.background.r, args.background.g, args.background.b, args.background.a)
      imlib_image_fill_rectangle(-upX, -upY, value.w, value.h)
      if bgNinepatch.image.len != 0:
        imlib_ninepatch_draw(bgNinepatch, -upX, -upY, value.w, value.h)
      #imlib_context_set_color(255,255,255,255)

      var
        x = -upX
        y = -upY
      proc drawStack(s: Pack) =
        for child in s.children:
          case child.kind:
          of Stack: drawStack(child)
          of Element:
            if images.hasKey(child.name):
              var image = imlib_load_image(args.images[child.name].image)
              if image != nil:
                imlib_context_set_image(buffer)
                #imlib_context_set_color(255, 0, 0,255)
                #imlib_image_fill_rectangle(x, y, child.width.value.int, child.height.value.int)
                imlib_blend_image_onto_image(image, 255, 0, 0, images[child.name].w, images[child.name].h, x, y, child.width.value.int, child.height.value.int)
                imlib_context_set_image(image)
                imlib_free_image()
            if texts.hasKey(child.name):
              imlib_context_set_image(buffer)
              #imlib_context_set_color(255, 0, 0,255)
              #imlib_image_fill_rectangle(x, y, child.width.value.int, child.height.value.int)
              var font = imlib_load_font(args.text[child.name].font)
              imlib_context_set_font(font)
              let color = args.text[child.name].color
              imlib_context_set_color(color.r, color.g, color.b, color.a);
              var text = args.text[child.name].text
              imlib_text_draw(x - up_x , y - up_y, text[0].addr)
              imlib_free_font()
          of Spacer: discard
          if s.orientation == Horizontal:
            x += child.width.value.int
          else:
            y += child.height.value.int
        if s.orientation == Horizontal:
          x -= s.width.value.int
        else:
          y -= s.height.value.int
      value.layout.drawStack()

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

