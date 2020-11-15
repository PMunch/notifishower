import npeg, kiwi, tables, strutils, sequtils, random
import termstyle

type
  PackingKind* = enum Element, Stack, Spacer
  Orientation* = enum Horizontal, Vertical
  Pack* = ref object
    width*, height*: Variable
    color*: tuple[red, green, blue: uint8]
    constraints: seq[Constraint]
    case kind*: PackingKind
    of Element:
      name*: string
    of Stack:
      orientation*: Orientation
      children*: seq[Pack]
    of Spacer:
      strict: bool
  Constraint = object
    comparator: string
    value: int
    percentage: bool
  ParseState = object
    stack: seq[Pack]
    constraints: Table[string, Constraint]
  LayoutDefect = object of Defect
    defective: Pack

proc `toFormatLanguage`*(p: Pack, highlight: Pack = nil): string =
  if p == highlight:
    result.add termRed
  case p.kind:
  of Element:
    result.add p.name
  of Stack:
    result.add if p.orientation == Horizontal: "(" else: "["
    for i, child in p.children:
      result.add child.toFormatLanguage(highlight)
      if child.kind != Spacer and i != p.children.high:
        result.add if p.children[i+1].kind == Spacer: "" else: " "
    result.add if p.orientation == Horizontal: ")" else: "]"
  of Spacer:
    result.add if p.strict: "-" else: "~"
  if p.constraints.len != 0:
    for constraint in p.constraints:
      result.add (if p.kind != Spacer: ":" else: "") & (if constraint.comparator == "==": "" else: constraint.comparator) &
        $constraint.value & (if constraint.percentage: "%" else: "")
      if p.kind == Spacer:
        result.add "-"
  if p == highlight:
    result.add termClear

proc `$`*(p: Pack): string =
  result.add $p.kind & "\n"
  result.add "  width: " & $p.width.value & "\n"
  result.add "  height: " & $p.height.value & "\n"
  result.add "  constraints: " & $p.constraints & "\n"
  case p.kind:
  of Element:
    result.add "  name: " & p.name & "\n"
  of Stack:
    result.add "  orientation: " & $p.orientation & "\n"
    result.add indent(p.children.mapIt($it).join("\n"), 2)
  of Spacer:
    result.add "  strict: " & $p.strict & "\n"

proc newStack(orientation: Orientation): Pack =
  result = Pack(kind: Stack)
  result.color = (rand(uint8), rand(uint8), rand(uint8))
  result.width = newVariable()
  result.height = newVariable()
  result.orientation = orientation

proc newSpacer(strict: bool): Pack =
  result = Pack(kind: Spacer)
  result.color = (rand(uint8), rand(uint8), rand(uint8))
  result.width = newVariable()
  result.height = newVariable()
  result.strict = strict

proc newElement(name: string): Pack =
  result = Pack(kind: Element)
  result.color = (rand(uint8), rand(uint8), rand(uint8))
  result.name = name
  result.width = newVariable()
  result.height = newVariable()

proc constrain(pack: var Pack, constraints: varargs[Constraint]) =
  pack.constraints &= constraints

proc last[T](x: var seq[T]): var T =
  x[x.high]

let
  parser = peg(outer, ps: ParseState):
    outer <- (outerHorizontal | outerVertical) * !1
    stack <- (horizontal | vertical) * *' '
    outerHorizontal <- startHorizontal * children * stopHorizontal
    outerVertical <- startVertical * children * stopVertical
    horizontal <- outerHorizontal * ?(':' * >constraint):
      if capture.len > 1:
        ps.stack.last.children.last.constrain ps.constraints[$1]
    vertical <- outerVertical * ?(':' * >constraint):
      if capture.len > 1:
        ps.stack.last.children.last.constrain ps.constraints[$1]
    elements <- element * *(+' ' * element)
    children <- ?spacer * +((stack | (element * *' ')) * ?spacer)
    constraint <- >?(">=" | "<=") * >positiveNumber * >?'%':
      ps.constraints[$0] = Constraint(
        comparator: if len($1) == 0: "==" else: $1,
        value: parseInt($2),
        percentage: $3 == "%"
      )
    element <- >identifier * ?(':' * >constraint):
      # TODO: Verify elements in list of defined elements
      var element = newElement($1)
      if capture.len > 2:
        element.constrain ps.constraints[$2]
      ps.stack.last.children.add element
    spacer <- *' ' * (strictSpacer | softSpacer) * *' '
    softSpacer <- '~':
      ps.stack.last.children.add newSpacer(false)
    strictSpacer <- '-' * ?(>constraint * '-'):
      var spacer = newSpacer(true)
      if capture.len > 1:
        spacer.constrain ps.constraints[$1]
      ps.stack.last.children.add spacer
    positiveNumber <- {'1'..'9'} * *Digit
    identifier <- Alpha * *(Alnum | '_')
    startHorizontal <- '(':
      ps.stack.add newStack(Horizontal)
    stopHorizontal <- ')' * *' ':
      let n = ps.stack.pop
      ps.stack.last.children.add n
    startVertical <- '[':
      ps.stack.add newStack(Vertical)
    stopVertical <- ']' * *' ':
      let n = ps.stack.pop
      ps.stack.last.children.add n

proc parse(x: string): Pack =
  var
    ps = ParseState(stack: @[newStack(Vertical)])
    match = parser.match(x, ps)
  if match.ok:
    # TODO: Verify that ps is good
    if ps.stack.len == 1 and ps.stack[0].children.len == 1:
      return ps.stack[0].children[0]
    else:
      echo "Parser returned illegal state"
      quit 1
  else:
    # TODO: Integrate error messages into npeg pattern
    echo "Error at:"
    echo x
    echo " ".repeat(match.matchMax) & "^"
    quit 1

#echo parse("[-test]")
#echo parse("[-test]:200")
#echo parse("[test-]")
#echo parse("[-test-]")
#echo parse("[test more]")
#echo parse("[test-more]")
#echo parse("([test][more])")
#echo parse("([test]-[more])")
#echo parse("([test]--[more])")
#echo parse("([test]-20-[more])")
#echo parse("([test]-5%-[more])")
#echo parse("([test]->=5-[more])")
#echo parse("([test:10 more])")

template failWithMessage(child: Pack, message: string, action: untyped): untyped =
  try:
    action
  except ValueError as e:
    var defect = newException(LayoutDefect, message)
    defect.defective = child
    raise defect

proc addStack(s: Solver, p: Pack, padding: int, text, images: Table[string, tuple[w: int, h: int]], depth: int) =
  # TODO: add more failWithMessage statements for better debugging
  var totalSize = newExpression(0)
  var nonStrictSpacers: seq[Variable]
  let
    parentDimension = (if p.orientation == Horizontal: p.width else: p.height)
    parentOtherDimension = (if p.orientation == Horizontal: p.height else: p.width)
  for child in p.children:
    let
      dimension = (if p.orientation == Horizontal: child.width else: child.height)
      otherDimension = (if p.orientation == Horizontal: child.height else: child.width)
    s.addConstraint(child.height >= 0)
    s.addConstraint(child.width >= 0)
    if child.kind != Spacer:
      s.addConstraint(otherDimension == parentOtherDimension)
    case child.kind:
    of Element:
      if text.hasKey(child.name):
        let
          dimensionValue = (if p.orientation == Horizontal: text[child.name].w.float else: text[child.name].h.float)
          otherDimensionValue = (if p.orientation == Horizontal: text[child.name].h.float else: text[child.name].w.float)
        if child.constraints.len == 0:
          s.addConstraint(dimension == dimensionValue)
        child.failWithMessage("Unable to add text element"):
          # This defaults text to be left aligned
          var
            dummySpacer = newVariable()
            constraint = dummySpacer == 0
          constraint.strength = createStrength(1.0, 0.0, 0.0, (depth + 1).float)
          s.addConstraint constraint
          s.addConstraint(otherDimension == otherDimensionValue + dummySpacer)
      elif images.hasKey(child.name):
        let dimensionValue = (if p.orientation == Horizontal: images[child.name].w.float else: images[child.name].h.float)
        if child.constraints.len == 0:
          s.addConstraint(dimension == dimensionValue)
        s.addConstraint(child.height*images[child.name][0].float == child.width*images[child.name][1].float)
    of Stack:
      s.addStack(child, padding, text, images, depth + 1)
    of Spacer:
      if child.strict:
        if child.constraints.len == 0:
          s.addConstraint(dimension == padding.float)
      else:
        nonStrictSpacers.add dimension
        var constraint = dimension == 0
        constraint.strength = createStrength(1.0, 0.0, 0.0, depth.float)
        s.addConstraint constraint
    for constraint in child.constraints:
      child.failWithMessage("Unable to satisfy constraint"):
        if constraint.percentage:
          case constraint.comparator:
          of "==":
            s.addConstraint(parentDimension * constraint.value.float / 100 == dimension)
          of "<=":
            s.addConstraint(parentDimension * constraint.value.float / 100 >= dimension)
          of ">=":
            s.addConstraint(parentDimension * constraint.value.float / 100 <= dimension)
        else:
          case constraint.comparator:
          of "==":
            s.addConstraint(constraint.value.float == dimension)
          of "<=":
            s.addConstraint(constraint.value.float >= dimension)
          of ">=":
            s.addConstraint(constraint.value.float <= dimension)
    totalSize = totalSize + dimension
  if nonStrictSpacers.len > 1:
    let first = nonStrictSpacers[0]
    for spacer in nonStrictSpacers[1..^1]:
      s.addConstraint(spacer == first)
  p.failWithMessage("Container too small for constraints"):
    s.addConstraint(parentDimension == totalSize)

proc parseLayout*(layout: string, w, h: tuple[opt: string, val: int], padding: int, text, images: Table[string, tuple[w: int, h: int]]): Pack =
  result = parse(layout)
  var s = newSolver()
  try:
    s.addStack(result, padding, text, images, 0)
  except LayoutDefect as e:
    echo red e.msg
    # TODO: Maybe add disclaimer about pattern being auto-expanded
    echo result.toFormatLanguage(e.defective)
    quit 1
  try:
    case w.opt:
    of "==", "": s.addConstraint(result.width == w.val.float)
    of "<=": s.addConstraint(result.width <= w.val.float)
    of ">=": s.addConstraint(result.width >= w.val.float)
    case h.opt:
    of "==", "": s.addConstraint(result.height == h.val.float)
    of "<=": s.addConstraint(result.height <= h.val.float)
    of ">=": s.addConstraint(result.height >= h.val.float)
  except ValueError:
    echo red("Unable to fit pattern into given width/height (", w.opt, w.val, ", ", h.opt, h.val, ")")
    echo red result.toFormatLanguage()
    quit 1
  s.updateVariables()
