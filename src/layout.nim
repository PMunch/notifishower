import npeg, kiwi, tables, strutils, sequtils

type
  PackingKind* = enum Element, Stack, Spacer
  Orientation* = enum Horizontal, Vertical
  Pack* = object
    width*, height*: Variable
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
  result.width = newVariable()
  result.height = newVariable()
  result.orientation = orientation

proc newSpacer(strict: bool): Pack =
  result = Pack(kind: Spacer)
  result.width = newVariable()
  result.height = newVariable()
  result.strict = strict

proc newElement(name: string): Pack =
  result = Pack(kind: Element)
  result.name = name
  result.width = newVariable()
  result.height = newVariable()

proc constrain(pack: var Pack, constraints: varargs[Constraint]) =
  pack.constraints &= constraints

proc last[T](x: var seq[T]): var T =
  x[x.high]

let
  parser = peg(stack, ps: ParseState):
    outer <- (outerHorizontal | outerVertical) * !1
    stack <- horizontal | vertical
    outerHorizontal <- startHorizontal * children * stopHorizontal
    outerVertical <- startVertical * children * stopVertical
    horizontal <- outerHorizontal * ?(':' * >constraint):
      if capture.len > 1:
        ps.stack.last.children.last.constrain ps.constraints[$1]
    vertical <- outerVertical * ?(':' * >constraint):
      if capture.len > 1:
        ps.stack.last.children.last.constrain ps.constraints[$1]
    elements <- element * *(+' ' * element)
    children <- ?spacer * +((stack | elements) * ?spacer)
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
    return ps.stack[0].children[0]
  else:
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

proc addStack(s: Solver, p: Pack, text, images: Table[string, tuple[w: int, h: int]]) =
  var totalSize = newExpression(0)
  var nonStrictSpacers: seq[Variable]
  let parentDimension = (if p.orientation == Horizontal: p.width else: p.height)
  for child in p.children:
    s.addConstraint(child.height >= 0)
    s.addConstraint(child.width >= 0)
    let dimension = (if p.orientation == Horizontal: child.width else: child.height)
    case child.kind:
    of Element:
      if text.hasKey(child.name):
        s.addEditVariable(child.width, createStrength(1, 0, 0, text[child.name][0].float))
        s.addEditVariable(child.height, createStrength(1, 0, 0, text[child.name][0].float))
        s.suggestValue(child.width, text[child.name][0].float)
        s.suggestValue(child.height, text[child.name][1].float)
      elif images.hasKey(child.name):
        let
          size = max(images[child.name][0], images[child.name][1]).float
          strength = createStrength(1, 0, 0, size)
        s.addEditVariable(child.width, strength)
        s.addEditVariable(child.height, strength)
        s.suggestValue(child.width, size)
        s.suggestValue(child.height, size)
        s.addConstraint(child.height*images[child.name][0].float == child.width*images[child.name][1].float)
    of Stack:
      s.addStack(child, text, images)
    of Spacer:
      if child.strict:
        if child.constraints.len == 0:
          s.addConstraint(dimension == 8) # TODO replace with padding variable
      else:
        nonStrictSpacers.add dimension
    for constraint in child.constraints:
      if constraint.percentage:
        case constraint.comparator:
        of "==":
          s.addConstraint(dimension == parentDimension * constraint.value.float / 100)
        of "<=":
          s.addConstraint(dimension <= parentDimension * constraint.value.float / 100)
        of ">=":
          s.addConstraint(dimension >= parentDimension * constraint.value.float / 100)
      else:
        case constraint.comparator:
        of "==":
          s.addConstraint(dimension == constraint.value.float)
        of "<=":
          s.addConstraint(dimension <= constraint.value.float)
        of ">=":
          s.addConstraint(dimension >= constraint.value.float)
    totalSize = totalSize + dimension
    if p.orientation == Horizontal:
      s.addConstraint(p.height == child.height)
    else:
      s.addConstraint(p.width == child.width)
  if nonStrictSpacers.len > 1:
    let first = nonStrictSpacers[0]
    for spacer in nonStrictSpacers[1..^1]:
      s.addConstraint(spacer == first)
  if p.orientation == Horizontal:
    s.addConstraint(p.width == totalSize)
  else:
    s.addConstraint(p.height == totalSize)

proc parseLayout*(layout: string, w, h: tuple[opt: string, val: int], text, images: Table[string, tuple[w: int, h: int]]): Pack =
  result = parse(layout)
  #echo result
  var s = newSolver()
  case w.opt:
  of "==", "": s.addConstraint(result.width == w.val.float)
  of "<=": s.addConstraint(result.width <= w.val.float)
  of ">=": s.addConstraint(result.width >= w.val.float)
  case h.opt:
  of "==", "": s.addConstraint(result.height == h.val.float)
  of "<=": s.addConstraint(result.height <= h.val.float)
  of ">=": s.addConstraint(result.height >= h.val.float)
  s.addStack(result, text, images)
  s.updateVariables()
