import npeg, os, strutils, tables

type
  Monitor = object
    name: string
    x, y, w, h: int
  Text = object
    text: string
    font: string
  Image = object
    image: string
  Options = object
    x, y, w, h: int
    background, border: string
    borderWidth: int
    font: string
    format: string
    monitor: seq[Monitor]
    text: Table[string, Text]
    images: Table[string, Image]

template monitorSetValues(i: int) =
  if capture[i+1].s == ",":
    monitor.x = parseInt capture[i].s
    monitor.y = parseInt capture[i+2].s
  else:
    monitor.w = parseInt capture[i].s
    monitor.h = parseInt capture[i+2].s

let parser = peg(input, options: Options):
  input <- option * *("\x1F" * option) * !1
  option <- help | version | position | size | background | border | borderwidth | text | font | image | monitor | format
  help <- "--help":
    echo "Help message"
    quit 0
  version <- ("--version" | "-v"):
    echo "Version"
    quit 0
  monitor <- "--monitor\x1F" * >xrandrident * ?("\x1F" * >number * >',' * ?'\x1F' * >number) * ?("\x1F" * >number * >':' * ?'\x1F' * >number):
    var monitor = Monitor(name: $1, x: int.high, y: int.high, w: int.high, h: int.high)
    if capture.len == 5:
      monitorSetValues(2)
    if capture.len == 8:
      monitorSetValues(2)
      monitorSetValues(5)
    options.monitor.add monitor
  position <- "-" * >("x" | "y") * "\x1F" * >number:
    case $1:
    of "x": options.x = parseInt($2)
    of "y": options.y = parseInt($2)
  size <- "-" * >("w" | "h") * "\x1F" * >number:
    case $1:
    of "w": options.w = parseInt($2)
    of "h": options.h = parseInt($2)
  background <- "--background\x1F" * >color:
    options.background = $1
  border <- "--border\x1F" * >color:
    options.border = $1
  borderwidth <- "--borderWidth\x1F" * >positiveNumber:
    options.borderWidth = parseInt($1)
  text <- "--" * >identifier * ".text\x1F" * >string:
    options.text.mgetOrPut($1, Text()).text = $2
  image <- "--" * >identifier * ".image\x1F" * >string:
    options.images.mgetOrPut($1, Image()).image = $2
  font <- "--" * ?(>identifier * '.') * "font\x1F" * >fontidentifier:
    if capture.len == 2: options.font = $1
    else: options.text.mgetOrPut($1, Text()).font = $2
  format <- "--format\x1F" * >string:
    options.format = $1
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

proc parseCommandLine*(opts = commandLineParams()): Options =
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
