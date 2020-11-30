import npeg, kiwi, tables, strutils, sequtils, random
import termstyle

type
  PackingKind* = enum Element, Stack, Spacer
  Orientation* = enum Horizontal, Vertical
  Layout* = ref object
    s: Solver
    pack*: Pack
    width: kiwi.Constraint
    height: kiwi.Constraint
  Pack* = ref object
    width*, height*: Variable
    color*: tuple[red, green, blue: uint8]
    constraints: seq[Constraint]
    case kind*: PackingKind
    of Element:
      name*: string
    of Stack:
      stackName*: string
      orientation*: Orientation
      children*: seq[Pack]
    of Spacer:
      strict: bool
  ConstraintKind = enum Value, Relative
  Constraint = object
    comparator: string
    case kind: ConstraintKind
    of Value:
      percentage: bool
      value: int
    of Relative:
      element: string
  ParseState = object
    stack: seq[Pack]
    constraints: Table[string, Constraint]
    elements: Table[string, Pack]
  LayoutDefect = object of Defect
    defective: Pack

template basePack(state: ParseState): Pack =
  state.stack[0].children[0]

template `basePack=`(state: ParseState, base: Pack) =
  state.stack[0].children[0] = base

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
        (if constraint.kind == Value: $constraint.value else: constraint.element) & (if constraint.kind == Value and constraint.percentage: "%" else: "")
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

template handleStack(): untyped =
  if capture[1].s.len > 0:
    let name = capture[1].s[0..^2]
    ps.stack.last.children.last.stackName = name
    ps.elements[name] = ps.stack.last.children.last
  if capture.len > 2:
    ps.stack.last.children.last.constrain ps.constraints[capture[2].s]

let
  parser = peg(outer, ps: ParseState):
    outer <- (outerHorizontal | outerVertical) * !1
    stack <- (horizontal | vertical) * *' '
    outerHorizontal <- startHorizontal * children * stopHorizontal
    outerVertical <- startVertical * children * stopVertical
    horizontal <- >?(identifier * '=') * outerHorizontal * ?(':' * >constraint):
      handleStack()
    vertical <- >?(identifier * '=') * outerVertical * ?(':' * >constraint):
      handleStack()
    elements <- element * *(+' ' * element)
    children <- ?spacer * +((stack | (element * *' ')) * ?spacer)
    constraint <- >?(">=" | "<=") * ((>positiveNumber * >?'%') | >identifier):
      try:
        let value = parseInt($2)
        ps.constraints[$0] = Constraint(
          kind: Value,
          comparator: if len($1) == 0: "==" else: $1,
          value: value,
          percentage: $3 == "%"
        )
      except ValueError:
        ps.constraints[$0] = Constraint(
          kind: Relative,
          comparator: if len($1) == 0: "==" else: $1,
          element: $2
        )
    element <- >identifier * ?(':' * >constraint):
      var element = newElement($1)
      if capture.len > 2:
        element.constrain ps.constraints[$2]
      ps.stack.last.children.add element
      ps.elements[$1] = element
    spacer <- *' ' * (strictSpacer | softSpacer) * *' '
    softSpacer <- '~':
      ps.stack.last.children.add newSpacer(false)
    strictSpacer <- '-' * ?(>constraint * '-'):
      var spacer = newSpacer(true)
      if capture.len > 1:
        spacer.constrain ps.constraints[$1]
      ps.stack.last.children.add spacer
    positiveNumber <- ({'1'..'9'} * *Digit) | '0'
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

proc parse(x: string): ParseState =
  var
    ps = ParseState(stack: @[newStack(Vertical)])
    match = parser.match(x, ps)
  if match.ok:
    if ps.stack.len == 1 and ps.stack[0].children.len == 1:
      return ps #.stack[0].children[0]
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

proc addStack(s: Solver, ps: ParseState, padding: int, text, images: Table[string, tuple[w: int, h: int]], depth: int) =
  # TODO: add more failWithMessage statements for better debugging
  let p = ps.basePack
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
          s.addConstraint(dummySpacer >= 0)
          s.addConstraint constraint
          s.addConstraint(otherDimension == otherDimensionValue + dummySpacer)
      elif images.hasKey(child.name):
        let dimensionValue = (if p.orientation == Horizontal: images[child.name].w.float else: images[child.name].h.float)
        if child.constraints.len == 0:
          s.addConstraint(dimension == dimensionValue)
        child.failWithMessage("Unable to keep aspect ratio"):
          s.addConstraint(child.height*images[child.name][0].float == child.width*images[child.name][1].float)
    of Stack:
      var dummyParseState = ps
      dummyParseState.basePack = child
      s.addStack(dummyParseState, padding, text, images, depth + 1)
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
        case constraint.kind:
        of Value:
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
        of Relative:
          let constraintDimension =
            if p.orientation == Horizontal:
              ps.elements[constraint.element].width
            else: ps.elements[constraint.element].height
          case constraint.comparator:
          of "==":
            s.addConstraint(constraintDimension == dimension)
          of "<=":
            s.addConstraint(constraintDimension >= dimension)
          of ">=":
            s.addConstraint(constraintDimension <= dimension)
    totalSize = totalSize + dimension
  if nonStrictSpacers.len > 1:
    let first = nonStrictSpacers[0]
    for spacer in nonStrictSpacers[1..^1]:
      s.addConstraint(spacer == first)
  p.failWithMessage("Container too small or big for constraints"):
    s.addConstraint(parentDimension == totalSize)

proc parseLayout*(layout: string, w, h: tuple[opt: string, val: int], padding: int, text, images: Table[string, tuple[w: int, h: int]]): Layout =
  var parseState = parse(layout)
  new result
  result.pack = parseState.basePack
  for key, element in parseState.elements.pairs:
    if element.kind == Element:
      if not text.hasKey(key) and not images.hasKey(key):
        echo red "Element \"" & key & "\" in pattern not given any text or image"
        echo result.pack.toFormatLanguage(element)
        quit 1
  var s = newSolver()
  try:
    s.addStack(parseState, padding, text, images, 0)
  except LayoutDefect as e:
    echo red e.msg
    echo result.pack.toFormatLanguage(e.defective)
    quit 1
  try:
    case w.opt:
    of "==", "": result.width = result.pack.width == w.val.float
    of "<=": result.width = result.pack.width <= w.val.float
    of ">=": result.width = result.pack.width >= w.val.float
    case h.opt:
    of "==", "": result.height = result.pack.height == h.val.float
    of "<=": result.height = result.pack.height <= h.val.float
    of ">=": result.height = result.pack.height >= h.val.float
    s.addConstraint result.width
    s.addConstraint result.height
  except ValueError:
    echo red("Unable to fit pattern into given width/height (", w.opt, w.val, ", ", h.opt, h.val, ")")
    echo red result.pack.toFormatLanguage()
    quit 1
  s.updateVariables()
  result.s = s

proc updateLayout*(l: Layout, w, h: tuple[opt: string, val: int]) =
  l.s.removeConstraint l.width
  l.s.removeConstraint l.height
  try:
    case w.opt:
    of "==", "": l.width = l.pack.width == w.val.float
    of "<=": l.width = l.pack.width <= w.val.float
    of ">=": l.width = l.pack.width >= w.val.float
    case h.opt:
    of "==", "": l.height = l.pack.height == h.val.float
    of "<=": l.height = l.pack.height <= h.val.float
    of ">=": l.height = l.pack.height >= h.val.float
    l.s.addConstraint l.width
    l.s.addConstraint l.height
  except ValueError:
    l.width = l.pack.width >= 0
    l.height = l.pack.height >= 0
    l.s.addConstraint l.width
    l.s.addConstraint l.height
    #l.s.addConstraint oldW
    #l.s.addConstraint oldH
    #echo red("Unable to fit pattern into given width/height (", w.opt, w.val, ", ", h.opt, h.val, ")")
    #echo red l.pack.toFormatLanguage()
    #quit 1
  l.s.updateVariables()
