import os, tables, selectors, macros, strutils
import layout, options, ninepatch
import imlib2
import times
import x11 / [x, xlib, xutil, xrandr, xatom]
import math

converter intToCint(x: int): cint = x.cint
converter intToCuint(x: int): cuint = x.cuint
converter pintToPcint(x: ptr int): ptr cint = cast[ptr cint](x)
converter boolToXBool(x: bool): XBool = x.XBool
converter xboolToBool(x: XBool): bool = x.bool

var args: Options
args.background = Color(r: 68, g: 68, b: 68, a: 255)
args.hover = Color(r: 128, g: 128, b: 128, a: 255)
args.border = Color(r: 128, g: 128, b: 128, a: 255)
args.borderWidth = 2
args.x = 49
args.y = 0
args.w = -98
args.h = 0
args.hopt = ">="
args.defaultFont = "DejaVuSans/10"
args.format = "(-[~icon:32~]-[~title body~]-)"
args.text["title"] = Text(font: "DejaVuSans/12")
args.text["body"] = Text()
args.defaultColor = Color(r: 255, g: 255, b: 255, a: 255)
args.images["icon"] = Image()
args.padding = 8
args.quitOnAction = true
args = parseCommandLine(defaults = args)
for _, text in args.text.mpairs:
  if text.font.len == 0:
    text.font = args.defaultFont

type
  Screen = object
    name: string
    primary: bool
    id: int
    x, y: int
    w, h: int
    mmh: int
  HoverSection = object
    element: string
    x, y, w, h: int
    action: string
    color: Color
  WindowInformation = object
    w, h: int
    screen: Screen
    updates: ImlibUpdates
    layout: Layout
    hoverSection: HoverSection

var
  disp: PDisplay
  vis: PVisual
  cm: Colormap
  depth: int
  ev: XEvent
  windows: Table[Window, WindowInformation]
  vinfo: XVisualInfo
  bgNinepatch: Ninepatch
  backgroundPatches: Table[string, Ninepatch]
  hoverPatches: Table[string, Ninepatch]
  startTime = epochTime()
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
wa.overrideRedirect = args.mode in {Notification, Desktop}
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

for element, background in args.backgrounds:
  if background.ninepatch.len != 0:
    var loaded = imlib_load_ninepatch(background.ninepatch)
    if loaded.image == background.ninepatch:
      loaded.tile = background.ninepatchTile
      backgroundPatches[element] = loaded

for element, hover in args.hoverables:
  if hover.ninepatch.len != 0:
    var loaded = imlib_load_ninepatch(hover.ninepatch)
    if loaded.image == hover.ninepatch:
      loaded.tile = hover.ninepatchTile
      hoverPatches[element] = loaded

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

proc calculateDimensions(screen: Screen): tuple[layout: Layout, x, y, w, h: int] =
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
    xCenterRelative =
      if args.monitors.hasKey(screen.name) and args.monitors[screen.name].xCenterRelative:
        true
      else: args.xCenterRelative
    yCenterRelative =
      if args.monitors.hasKey(screen.name) and args.monitors[screen.name].yCenterRelative:
        true
      else: args.yCenterRelative
    winWidth = if width < 0: screen.w + width else: width
    winHeight = if height < 0: screen.h + height else: height
  var layout = parseLayout(args.format, (args.wopt, winWidth), (args.hopt, winHeight), args.padding, texts, images)
  if args.ninepatch.len != 0 and bgNinepatch.tile:
    let
      cwidth = layout.pack.width.value.int - bgNinepatch.startTileX - bgNinepatch.endTileX
      cheight = layout.pack.height.value.int - bgNinepatch.startTileY - bgNinepatch.endTileY
    var
      nwidth = layout.pack.width.value.int + (bgNinepatch.tileStepX - (cwidth mod bgNinepatch.tileStepX))
      nheight = layout.pack.height.value.int + (bgNinepatch.tileStepY - (cheight mod bgNinepatch.tileStepY))
    case args.wopt:
    of "==": nwidth = layout.pack.width.value.int
    of "<=": nwidth = min(winWidth, nwidth)
    of ">=": nwidth = max(winWidth, nwidth)
    case args.hopt:
    of "==": nheight = layout.pack.height.value.int
    of "<=": nheight = min(winHeight, nheight)
    of ">=": nheight = max(winHeight, nheight)
    layout.updateLayout(
      ("==", nwidth),
      ("==", nheight)
    )
  let
    xpos = screen.x + (if xCenterRelative: (screen.w div 2 - borderWidth - (layout.pack.width.value.int div 2) + xinput)
      else: (if xinput < 0: screen.w - layout.pack.width.value.int - borderWidth*2 + xinput + 1 else: xinput)
    )
    ypos = screen.y + (if yCenterRelative: (screen.h div 2 - borderWidth - (layout.pack.height.value.int div 2) + yinput)
      else: (if yinput < 0: screen.h - layout.pack.height.value.int - borderWidth*2 + yinput + 1 else: yinput)
    )
  return (layout, xpos, ypos, layout.pack.width.value.round.int, layout.pack.height.value.round.int)

if args.mode == Normal and args.monitors.len == 0:
  # TODO: try to pick current monitor
  screens = screens[0..0]

for screen in screens:
  # TODO: Detect active monitor and allow a follow active mode
  if args.monitors.len == 0 or args.monitors.hasKey(screen.name):
    let
      dimensions = calculateDimensions(screen)
      win = XCreateWindow(disp, DefaultRootWindow(disp), dimensions.x, dimensions.y, dimensions.w,
        dimensions.h, args.borderWidth, vinfo.depth, InputOutput, vinfo.visual,
        (if args.mode in {Notification, Desktop}: CWOverrideRedirect else: 0).culong or CWBackPixmap or CWBackPixel or CWBorderPixel or
        CWColormap or CWEventMask, wa.addr)
    windows[win] = WindowInformation(
      w: dimensions.w,
      h: dimensions.h,
      screen: screen,
      layout: dimensions.layout
    )

    if args.mode == Dock:
      var dockAtom = XInternAtom(disp, "_NET_WM_WINDOW_TYPE_DOCK", true)
      discard XChangeProperty(disp, win, XInternAtom(disp, "_NET_WM_WINDOW_TYPE", false),
        XA_ATOM, 32, PropModeReplace, cast[ptr cuchar](dockAtom.addr),
        1)
      var partial = [
        if args.edge == Left: dimensions.w else: 0, # left
        if args.edge == Right: dimensions.w else: 0, # right
        if args.edge == Top: dimensions.h else: 0, # top
        if args.edge == Bottom: dimensions.h else: 0, # bottom
        if args.edge == Left: screen.y else: 0, # leftStartY
        if args.edge == Left: screen.y + screen.h else: 0, # leftEndY
        if args.edge == Right: screen.y else: 0, # rightStartY
        if args.edge == Right: screen.y + screen.h else: 0, # rightEndY
        if args.edge == Top: screen.x else: 0, # topStartX
        if args.edge == Top: screen.x + screen.w else: 0, # topEndX
        if args.edge == Bottom: screen.x else: 0, # bottomStartX
        if args.edge == Bottom: screen.x + screen.w else: 0 # bottomEndX
      ]
      discard XChangeProperty(disp, win, XInternAtom(disp, "_NET_WM_STRUT_PARTIAL", false),
        XA_CARDINAL, 32, PropModeReplace, cast[ptr cuchar](partial[0].addr),
        partial.len)

    discard XSelectInput(disp, win, KeyPressMask or ButtonPressMask or ButtonReleaseMask or
                PointerMotionMask or ExposureMask or FocusChangeMask or StructureNotifyMask)
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


    # set the icon
    if args.icon.len != 0:
      let icon = imlib_load_image(args.icon)
      if icon != nil:
        imlib_context_set_image(icon)
        let
          icon_data = cast[ptr UncheckedArray[uint32]](imlib_image_get_data_for_reading_only())
          width = imlib_image_get_width()
          height = imlib_image_get_height()
          elements = width*height + 2
        var icon_data_x11 = newSeq[uint](elements * sizeof(uint))
        icon_data_x11[0] = width.uint
        icon_data_x11[1] = height.uint
        # Can't simply use memcpy here because the target buffer is
        # architecture dependent but the imlib buffer is always 32-bit
        for i in 0..<width*height:
          icon_data_x11[2+i] = icon_data[i].uint
        let
          net_wm_icon = XInternAtom(disp, "_NET_WM_ICON", false)
          cardinal = XInternAtom(disp, "CARDINAL", false)
        discard XChangeProperty(disp, win, net_wm_icon, cardinal, 32,
          PropModeReplace, cast[ptr cuchar](icon_data_x11[0].addr), elements)
        imlib_free_image()

    # set window type
    let net_wm_window_type = XInternAtom(disp, "_NET_WM_WINDOW_TYPE", false)

    var data = case args.mode:
      of Notification: @[
          XInternAtom(disp, "_NET_WM_WINDOW_TYPE_NOTIFICATION", false),
          XInternAtom(disp, "_NET_WM_WINDOW_TYPE_UTILITY", false)
        ]
      of Dock: @[
          XInternAtom(disp, "_NET_WM_WINDOW_TYPE_DOCK", false)
        ]
      of Desktop: @[
          XInternAtom(disp, "_NET_WM_WINDOW_TYPE_DESKTOP", false)
        ]
      of Normal: @[
          XInternAtom(disp, "_NET_WM_WINDOW_TYPE_NORMAL", false)
        ]

    if data.len > 0:
      discard XChangeProperty(disp, win, net_wm_window_type, XA_ATOM, 32,
        PropModeReplace, cast[ptr cuchar](data[0].addr), data.len)

    # set state above
    let netWmState = XInternAtom(disp, "_NET_WM_STATE", false)
    case args.mode:
    of Notification, Dock:
      data[0] = XInternAtom(disp, "_NET_WM_STATE_ABOVE", false)
    else:
      data[0] = XInternAtom(disp, "_NET_WM_STATE_BELOW", false)

    discard XChangeProperty(disp, win, netWmState, XA_ATOM, 32,
            PropModeReplace, cast[ptr cuchar](data[0].addr), 1)

    if args.mode == Desktop: discard XLowerWindow(disp, win)

  if args.mode != Normal:
    for shortcut in args.shortcuts.keys:
      discard XGrabKey(disp, XKeysymToKeycode(disp, shortcut.key).cint, shortcut.mask, DefaultRootWindow(disp),
        false, GrabModeAsync, GrabModeAsync);

    if args.defaultShortcut.mask != 0 or args.defaultShortcut.key.int != 0:
      discard XGrabKey(disp, XKeysymToKeycode(disp, args.defaultShortcut.key).cint, args.defaultShortcut.mask, DefaultRootWindow(disp),
        false, GrabModeAsync, GrabModeAsync);

proc inRect(x, y, rx, ry, rw, rh: int): bool =
  if x >= rx and x < rx + rw and
     y >= ry and y < ry + rh:
    true
  else:
    false

template forEachElement(startX, startY: int, elementBody: untyped, stackBody: untyped): untyped =
  block:
    var
      x {.inject.} = startX
      y {.inject.} = startY
    proc calculateStack(s: Pack, window {.inject.}: var WindowInformation) =
      for element {.inject.} in s.children:
        let
          w {.inject.} = element.width.value.int
          h {.inject.} = element.height.value.int
        when declared(drawStack):
          imlib_context_set_image(buffer)
          let color = element.color
          imlib_context_set_color(color.red.cint, color.green.cint, color.blue.cint, 200)
          imlib_image_fill_rectangle(x, y, element.width.value.int, element.height.value.int)
        case element.kind:
        of Stack:
          stackBody
          element.calculateStack(window)
        of Element:
          elementBody
        of Spacer: discard
        if s.orientation == Horizontal:
          x += element.width.value.int
        else:
          y += element.height.value.int
      if s.orientation == Horizontal:
        x -= s.width.value.int
      else:
        y -= s.height.value.int
    when declared(drawStack):
      imlib_context_set_image(buffer)
      let color = window.layout.pack.color
      imlib_context_set_color(color.red.cint, color.green.cint, color.blue.cint, 200)
      imlib_image_fill_rectangle(x, y, window.layout.pack.width.value.int, window.layout.pack.height.value.int)
    window.layout.pack.calculateStack(window)

proc calculateHoverSection(mx, my: int, window: var WindowInformation) =
  reset window.hoverSection
  template checkElement(name: untyped): untyped =
    var
      action = args.hoverables.getOrDefault(element.name).action
      color = args.hoverables.getOrDefault(element.name).color
    if color.r == 0 and color.b == 0 and color.g == 0 and color.a == 0:
      color = args.hover
    if action.len > 0 and
      inRect(mx, my, x, y, element.width.value.int, element.height.value.int):
      window.hoverSection =
        HoverSection(x: x, y: y,
          w: element.width.value.int, h: element.height.value.int,
          element: element.name,
          action: action,
          color: color)
  forEachElement(0, 0):
    checkElement(name)
  do:
    checkElement(stackName)

template performReplace(event, action, element: untyped): untyped =
  block:
    let
      rootX = ev.event.x
      rootY = ev.event.y
    var elementX, elementY, clickX, clickY = 0
    if windows.hasKey(ev.event.window):
      elementX = windows[ev.event.window].hoverSection.x
      elementY = windows[ev.event.window].hoverSection.y
      clickX = rootX - elementX
      clickY = rootY - elementY
    var replaced = action.multiReplace(
        ("{clickX}", $clickX), ("{clickY}", $clickY),
        ("{elementX}", $elementX), ("{elementY}", $elementY),
        ("{rootX}", $rootX), ("{rootY}", $rootY), ("{trigger}", "click"))
    if args.text.hasKey(element):
      replaced = replaced.replace("{value}", args.text[element].text)
    if args.images.hasKey(element):
      replaced = replaced.replace("{value}", args.images[element].image)
    replaced

var selector = newSelector[pointer]()
selector.registerHandle(ConnectionNumber(disp).int, {Read}, nil)
var pipes: Table[int, tuple[element: string, file: File]]
for key, text in args.text:
  if text.pipe.len != 0:
    let pipe = open(text.pipe)
    selector.registerHandle(pipe.getFileHandle.int, {Read}, nil)
    pipes[pipe.getFileHandle.int] = (key, pipe)

for key, image in args.images:
  if image.pipe.len != 0:
    let pipe = open(image.pipe)
    selector.registerHandle(pipe.getFileHandle.int, {Read}, nil)
    pipes[pipe.getFileHandle.int] = (key, pipe)

while true:
  if XPending(disp) == 0: # If we don't have any XEvents, make sure we don't wait further than our timeout
    let timeout = if args.timeout == 0: -1
      else: int((startTime + args.timeout.float - epochTime())*1000.0)
    var events = selector.select(timeout)
    for event in events:
      if pipes.hasKey(event.fd):
        let pipe = pipes[event.fd]
        try:
          if args.text.hasKey(pipe.element):
            args.text[pipe.element].text = pipe.file.readLine
            let
              text = args.text[pipe.element]
              loadedFont = imlib_load_font(text.font)
            texts[pipe.element] = (1, 1)
            imlib_context_set_font(loadedFont)
            if text.text.len > 0:
              imlib_get_text_size(text.text[0].unsafeAddr, texts[pipe.element].w.addr, texts[pipe.element].h.addr)
            imlib_free_font()
          elif args.images.hasKey(pipe.element):
            args.images[pipe.element].image = pipe.file.readLine
            let image = args.images[pipe.element]
            if image.image.len > 0:
              var image = imlib_load_image(image.image)
              if image == nil:
                args.images[pipe.element].image = ""
                images[pipe.element] = (1, 1)
              else:
                imlib_context_set_image(image)
                images[pipe.element] = (imlib_image_get_width().int, imlib_image_get_height().int)
                imlib_free_image()
            else:
              images[pipe.element] = (1, 1)
          for win, winInfo in windows.mpairs:
            let dimensions = calculateDimensions(winInfo.screen)
            if winInfo.w == dimensions.w and winInfo.h == dimensions.h:
              # This will happen anyways if the window resizes
              winInfo.updates = imlib_update_append_rect(
                winInfo.updates, 0, 0, dimensions.w, dimensions.h)
            winInfo.w = dimensions.w
            winInfo.h = dimensions.h
            winInfo.layout = dimensions.layout
            if args.mode != Normal:
              discard XMoveResizeWindow(disp, win, dimensions.x, dimensions.y, dimensions.w, dimensions.h)
            else:
              discard XResizeWindow(disp, win, dimensions.w, dimensions.h)
        except EOFError:
          selector.unregister(event.fd)
          pipe.file.close()
          pipes.del(event.fd)
  if args.timeout != 0 and startTime + args.timeout.float <= epochTime():
    quit 0

  while XPending(disp) > 0:
    discard XNextEvent(disp, ev.addr)
    case ev.tHeType:
    of Expose:
      windows[ev.xexpose.window].updates = imlib_update_append_rect(
        windows[ev.xexpose.window].updates,
        ev.xexpose.x, ev.xexpose.y,
        ev.xexpose.width, ev.xexpose.height)
    of MotionNotify:
      template window(): untyped = windows[ev.xmotion.window]
      template updateHoverSection(): untyped =
        if window.hoverSection.w > 0 and window.hoverSection.h > 0:
          if backgroundPatches.hasKey(window.hoverSection.element):
            let patch = backgroundPatches[window.hoverSection.element]
            window.updates = imlib_update_append_rect(
              window.updates,
              window.hoverSection.x - patch.startDX, window.hoverSection.y - patch.startDY,
              window.hoverSection.w + patch.startDX + patch.dwidth, window.hoverSection.h + patch.startDY + patch.dheight)
          if hoverPatches.hasKey(window.hoverSection.element):
            let patch = hoverPatches[window.hoverSection.element]
            window.updates = imlib_update_append_rect(
              window.updates,
              window.hoverSection.x - patch.startDX, window.hoverSection.y - patch.startDY,
              window.hoverSection.w + patch.startDX + patch.dwidth, window.hoverSection.h + patch.startDY + patch.dheight)
          window.updates = imlib_update_append_rect(
            window.updates,
            window.hoverSection.x, window.hoverSection.y,
            window.hoverSection.w, window.hoverSection.h)
      updateHoverSection()
      calculateHoverSection(ev.xmotion.x, ev.xmotion.y, window)
      updateHoverSection()
      if window.hoverSection.action == "":
        window.hoverSection.action = args.defaultAction
    of ButtonRelease:
      let action = windows[ev.xbutton.window].hoverSection.action
      if action != "":
        let element = windows[ev.xbutton.window].hoverSection.element
        stdout.writeLine performReplace(xbutton, action, element)
        if args.quitOnAction:
          quit 0
    of KeyPress:
      let shortcut = Shortcut(mask: ev.xkey.state, key: XLookupKeysym(ev.xkey.addr, 0))
      if args.defaultShortcut == shortcut and args.defaultAction.len != 0:
        stdout.writeLine performReplace(xkey, args.defaultAction, "")
        if args.quitOnAction:
          quit 0
      if args.shortcuts.hasKey(shortcut):
        let element = args.shortcuts[shortcut]
        if args.hoverables.hasKey(element):
          stdout.writeLine performReplace(xkey, args.hoverables[element].action, element)
          if args.quitOnAction:
            quit 0
    of FocusIn, FocusOut:
      if args.mode == Desktop: discard XLowerWindow(disp, ev.xfocus.window)
    of ConfigureNotify:
      if ev.xconfigure.width != windows[ev.xconfigure.window].w or
         ev.xconfigure.height != windows[ev.xconfigure.window].h:
        var layout = windows[ev.xconfigure.window].layout
        layout.updateLayout(
          ("==", ev.xconfigure.width.int),
          ("==", ev.xconfigure.height.int)
        )
        windows[ev.xconfigure.window].w = layout.pack.width.value.round.int
        windows[ev.xconfigure.window].h = layout.pack.height.value.round.int
        windows[ev.xconfigure.window].updates = imlib_update_append_rect(
          windows[ev.xconfigure.window].updates,
          0, 0,
          ev.xconfigure.width, ev.xconfigure.height)
    else:
      discard screenCheckEvent(ev.addr)

  for winId, window in windows.mpairs:
    window.updates = imlib_updates_merge_for_rendering(window.updates, window.w, window.h);
    var currentUpdate = window.updates
    while currentUpdate != nil:
      imlib_context_set_drawable(winId)
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
      imlib_image_fill_rectangle(-upX, -upY, window.w, window.h)
      if bgNinepatch.image.len != 0:
        imlib_ninepatch_draw(bgNinepatch, -upX, -upY, window.w, window.h)
      #imlib_context_set_color(255,255,255,255)

      imlib_context_set_image(buffer)
      if hoverPatches.hasKey(window.hoverSection.element):
        let patch = hoverPatches[window.hoverSection.element]
        imlib_ninepatch_draw(patch, window.hoverSection.x - up_x - patch.startDX,
          window.hoverSection.y - up_y - patch.startDY,
          window.hoverSection.w + patch.startDX + patch.dwidth,
          window.hoverSection.h + patch.startDY + patch.dheight)
      else:
        let color = window.hoverSection.color
        imlib_context_set_color(color.r, color.g, color.b, color.a)
        imlib_image_fill_rectangle(window.hoverSection.x - up_x, window.hoverSection.y - up_y,
          window.hoverSection.w, window.hoverSection.h)

      #var drawStack = true
      forEachElement(-up_x, -up_y):
        if args.backgrounds.hasKey(element.name) and window.hoverSection.element != element.name:
          imlib_context_set_image(buffer)
          if backgroundPatches.hasKey(element.name):
            let patch = backgroundPatches[element.name]
            imlib_ninepatch_draw(patch, x - patch.startDX, y - patch.startDY,
              w + patch.startDX + patch.dwidth, h + patch.startDY + patch.dheight)
          else:
            let color = args.backgrounds[element.name].background
            imlib_context_set_color(color.r, color.g, color.b, color.a);
            imlib_image_fill_rectangle(x, y, w, h)
        if images.hasKey(element.name):
          var image = imlib_load_image(args.images[element.name].image)
          if image != nil:
            imlib_context_set_image(buffer)
            imlib_blend_image_onto_image(image, 255, 0, 0,
              images[element.name].w, images[element.name].h,
              x, y, w, h)
            imlib_context_set_image(image)
            imlib_free_image()
        if texts.hasKey(element.name):
          var text = args.text[element.name].text
          if text.len > 0:
            var textBuffer = imlib_create_image(w, h)
            imlib_context_set_image(textBuffer)
            imlib_image_set_has_alpha(1)
            imlib_image_clear()
            var font = imlib_load_font(args.text[element.name].font)
            imlib_context_set_font(font)
            let color = args.text[element.name].color
            if color == default(Color):
              imlib_context_set_color(args.defaultColor.r, args.defaultColor.g, args.defaultColor.b, args.defaultColor.a)
            else:
              imlib_context_set_color(color.r, color.g, color.b, color.a)
            imlib_text_draw(0, 0, text[0].addr)
            imlib_free_font()
            imlib_context_set_image(buffer)
            imlib_blend_image_onto_image(textBuffer, 255, 0, 0, w, h, x, y, w, h)
            imlib_context_set_image(textBuffer)
            imlib_free_image()
      do:
        if element.stackName.len > 0:
          if args.backgrounds.hasKey(element.stackName) and window.hoverSection.element != element.stackName:
            imlib_context_set_image(buffer)
            if backgroundPatches.hasKey(element.stackName):
              let patch = backgroundPatches[element.stackName]
              imlib_ninepatch_draw(patch, x - patch.startDX, y - patch.startDY,
                w + patch.startDX + patch.dwidth, h + patch.startDY + patch.dheight)
            else:
              let color = args.backgrounds[element.stackName].background
              imlib_context_set_color(color.r, color.g, color.b, color.a);
              imlib_image_fill_rectangle(x, y, w, h)

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
    if window.updates != nil:
       imlib_updates_free(window.updates)
       window.updates = nil

