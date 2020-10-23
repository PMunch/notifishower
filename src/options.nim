import npeg, os, strutils, tables

type
  Monitor* = object
    x*, y*, w*, h*: int
  Text* = object
    text*: string
    font*: string
    color*: Color
  Image* = object
    image*: string
  Options* = object
    wopt*: string
    hopt*: string
    x*, y*, w*, h*: int
    background*, border*: Color
    borderWidth*: int
    ninepatch*: string
    ninepatchTile*: bool
    defaultFont*: string
    format*: string
    monitors*: Table[string, Monitor]
    text*: Table[string, Text]
    images*: Table[string, Image]
    name*, class*: string
  Color* = object
    r*, g*, b*, a*: int

template monitorSetValues(i: int) =
  if capture[i+1].s == ",":
    monitor.x = parseInt capture[i].s
    monitor.y = parseInt capture[i+2].s
  else:
    monitor.w = parseInt capture[i].s
    monitor.h = parseInt capture[i+2].s

proc parseColor(color: string): Color =
  let s = if color[0] == '#': 1 else: 0
  result.r = parseHexInt(color[s..s+1])
  result.g = parseHexInt(color[s+2..s+3])
  result.b = parseHexInt(color[s+4..s+5])
  result.a = 255
  if color.len - s > 6:
    result.a = parseHexInt(color[s+6..s+7])

proc parseCommandFile*(file: string, defaults: var Options = default(Options)): Options

let parser = peg(input, options: Options):
  input <- option * *("\x1F" * option) * !1
  option <- help | version | position | size | background | border | borderwidth | text | font | image | monitor | format | name | class | textColor | ninepatch | tile | config
  help <- "--help":
    echo "Help message"
    quit 0
  version <- ("--version" | "-v"):
    echo "Version"
    quit 0
  monitor <- "--monitor\x1F" * >xrandrident * ?("\x1F" * >number * >',' * ?'\x1F' * >number) * ?("\x1F" * >number * >':' * ?'\x1F' * >number):
    var monitor = Monitor(x: int.high, y: int.high, w: int.high, h: int.high)
    if capture.len == 5:
      monitorSetValues(2)
    if capture.len == 8:
      monitorSetValues(2)
      monitorSetValues(5)
    options.monitors[$1] = monitor
  position <- "-" * >("x" | "y") * "\x1F" * >number:
    case $1:
    of "x": options.x = parseInt($2)
    of "y": options.y = parseInt($2)
  size <- "-" * >("w" | "h") * "\x1F" * >?comparator * >number:
    case $1:
    of "w":
      options.w = parseInt($3)
      options.wopt = $2
    of "h":
      options.h = parseInt($3)
      options.hopt = $2
  ninepatch <- "--ninepatch\x1F" * >string:
    options.ninepatch = $1
  config <- "--config\x1F" * >string:
    options = parseCommandFile($1, options)
  tile <- "--ninepatch.tile\x1F" * >("true" | "false"):
    options.ninepatchTile = $1 == "true"
  background <- "--background\x1F" * >color:
    options.background = parseColor($1)
  border <- "--border\x1F" * >color:
    options.border = parseColor($1)
  borderwidth <- "--borderWidth\x1F" * >positiveNumber:
    options.borderWidth = parseInt($1)
  text <- "--" * >identifier * ".text\x1F" * >string:
    options.text.mgetOrPut($1, Text()).text = $2
  textColor <- "--" * >identifier * ".color\x1F" * >color:
    options.text.mgetOrPut($1, Text()).color = parseColor($2)
  image <- "--" * >identifier * ".image\x1F" * >string:
    options.images.mgetOrPut($1, Image()).image = $2
  font <- "--" * ?(>identifier * '.') * "font\x1F" * >fontidentifier:
    if capture.len == 2: options.defaultFont = $1
    else: options.text.mgetOrPut($1, Text()).font = $2
  format <- "--format\x1F" * >string:
    options.format = $1
  name <- "--name\x1F" * >string:
    options.name = $1
  class <- "--class\x1F" * >string:
    options.class = $1
  comparator <- ">=" | "<="
  number <- (?'-' * {'1'..'9'} * *Digit) | '0'
  positiveNumber <- ({'1'..'9'} * *Digit) | '0'
  identifier <- Alpha * *(Alnum | '_')
  string <- *Print
  #string <- (+UnquotStrChar) | ('"' * *StrChar * '"')
  #UnquotStrChar <- {'!', 0x23..0x7E}
  #StrChar <- {'\t', ' ', '!', 0x23..0x7E}
  xrandrident <- +Print #UnquotStrChar
  color <- ?'#' * (Xdigit[8] | Xdigit[6])
  fontidentifier <- +nonslash * +(('/' * positiveNumber * &('\x1F' | !1)) | ('/' * +nonslash * &1 * &(!'\x1F')))
  nonslash <- {0x21..0x2E, 0x30..0x7E}

proc parseCommandLine*(defaults: var Options = default(Options), opts = commandLineParams()): Options =
  result = defaults
  let params = opts.join("\x1F")
  let match = parser.match(params, result)
  if not match.ok:
    echo "Unable to parse"
    quit 1
  #if not match.ok:
  #  echo params.replace("\x1F", " ")
  #  echo " ".repeat(match.matchMax) & "^"
  #else:
  #  echo match
  #  echo options

proc parseCommandFile*(file: string, defaults: var Options = default(Options)): Options =
  var options: seq[string]
  for line in file.lines:
    let split = line.split(":", maxSplit = 1)
    options.add "-".repeat(min(2, split[0].len)) & split[0]
    options.add split[1].strip
  parseCommandLine(defaults, options)

when isMainModule:
  var defaults = default(Options)
  echo parseCommandfile("test.conf", defaults)
