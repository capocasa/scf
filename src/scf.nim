## Standalone Nim Source Code Filter (stdtmpl) transformer.
##
## Transforms SCF syntax into valid Nim code that can be parsed by parseStmt.
##
## Usage:
##   CLI: scf < input.nim > output.nim
##   Lib: let output = filterStdTmpl(input)

import std/strutils

type
  ScfError* = object of CatchableError

  ParseState = enum
    psDirective, psTempl

  TmplParser = object
    state: ParseState
    line: int
    indent, emitPar: int
    x: string  # current input line
    output: string
    subsChar, nimDirective: char
    emit, conc, toStr: string
    curly, bracket, par: int
    pendingExprLine: bool

const
  PatternChars = {'a'..'z', 'A'..'Z', '0'..'9', '\x80'..'\xFF', '.', '_'}
  LineContinuationOprs = {'+', '-', '*', '/', '\\', '<', '>', '^',
                          '|', '%', '&', '$', '@', '~', ','}

proc endsWith(x: string, s: set[char]): bool =
  var i = x.len - 1
  while i >= 0 and x[i] == ' ': dec(i)
  result = i >= 0 and x[i] in s

proc raiseScfError(p: TmplParser, msg: string) =
  raise newException(ScfError, "line " & $p.line & ": " & msg)

proc write(p: var TmplParser, s: string) =
  p.output.add s

proc write(p: var TmplParser, c: char) =
  p.output.add c

proc newLine(p: var TmplParser) =
  p.output.add repeat(')', p.emitPar)
  p.emitPar = 0
  if p.line > 1:
    p.output.add "\n"
  if p.pendingExprLine:
    p.output.add spaces(2)
    p.pendingExprLine = false

proc scanPar(p: var TmplParser, d: int) =
  var i = d
  while i < p.x.len:
    case p.x[i]
    of '(': inc(p.par)
    of ')': dec(p.par)
    of '[': inc(p.bracket)
    of ']': dec(p.bracket)
    of '{': inc(p.curly)
    of '}': dec(p.curly)
    else: discard
    inc(i)

proc withInExpr(p: TmplParser): bool {.inline.} =
  p.par > 0 or p.bracket > 0 or p.curly > 0

proc parseLine(p: var TmplParser) =
  var j = 0
  let len = p.x.len

  while j < len and p.x[j] == ' ': inc(j)

  if len >= 2 and p.x[0] == p.nimDirective and p.x[1] == '?':
    # Skip directive lines like #? stdtmpl
    p.newLine()
  elif j < len and p.x[j] == p.nimDirective:
    # Nim code line
    p.newLine()
    inc(j)
    while j < len and p.x[j] == ' ': inc(j)
    let d = j
    var keyw = ""
    while j < len and p.x[j] in PatternChars:
      keyw.add(p.x[j])
      inc(j)

    p.scanPar(j)
    p.pendingExprLine = p.withInExpr() or p.x.endsWith(LineContinuationOprs)

    case keyw
    of "end":
      if p.indent >= 2:
        dec(p.indent, 2)
      else:
        p.raiseScfError("'end' does not close a control flow construct")
      p.write(spaces(p.indent))
      p.write("#end")
    of "if", "when", "try", "while", "for", "block", "case", "proc", "iterator",
       "converter", "macro", "template", "method", "func":
      p.write(spaces(p.indent))
      p.write(p.x[d..^1])
      inc(p.indent, 2)
    of "elif", "of", "else", "except", "finally":
      p.write(spaces(p.indent - 2))
      p.write(p.x[d..^1])
    of "let", "var", "const", "type":
      p.write(spaces(p.indent))
      p.write(p.x[d..^1])
      if not p.x.contains({':', '='}):
        inc(p.indent, 2)
    else:
      p.write(spaces(p.indent))
      p.write(p.x[d..^1])
    p.state = psDirective
  else:
    # Data line (template content)
    p.par = 0
    p.curly = 0
    p.bracket = 0
    j = 0

    case p.state
    of psTempl:
      p.write(p.conc)
      p.write("\n")
      p.write(spaces(p.indent + 2))
      p.write("\"")
    of psDirective:
      p.newLine()
      p.write(spaces(p.indent))
      p.write(p.emit)
      p.write("(\"")
      inc(p.emitPar)

    p.state = psTempl

    while j < len:
      case p.x[j]
      of '\x01'..'\x1F', '\x80'..'\xFF':
        p.write("\\x")
        p.write(toHex(ord(p.x[j]), 2))
        inc(j)
      of '\\':
        p.write("\\\\")
        inc(j)
      of '\'':
        p.write("\\'")
        inc(j)
      of '\"':
        p.write("\\\"")
        inc(j)
      else:
        if p.x[j] == p.subsChar:
          inc(j)
          if j >= len:
            p.raiseScfError("unexpected end after substitution char")
          case p.x[j]
          of '{':
            p.write('\"')
            p.write(p.conc)
            p.write(p.toStr)
            p.write('(')
            inc(j)
            var curly = 0
            while j < len:
              case p.x[j]
              of '{':
                inc(j)
                inc(curly)
                p.write('{')
              of '}':
                inc(j)
                if curly == 0: break
                if curly > 0: dec(curly)
                p.write('}')
              else:
                p.write(p.x[j])
                inc(j)
            if curly > 0:
              p.raiseScfError("expected closing '}'")
            p.write(')')
            p.write(p.conc)
            p.write('\"')
          of 'a'..'z', 'A'..'Z', '\x80'..'\xFF':
            p.write('\"')
            p.write(p.conc)
            p.write(p.toStr)
            p.write('(')
            while j < len and p.x[j] in PatternChars:
              p.write(p.x[j])
              inc(j)
            p.write(')')
            p.write(p.conc)
            p.write('\"')
          else:
            if p.x[j] == p.subsChar:
              p.write(p.subsChar)
              inc(j)
            else:
              p.raiseScfError("invalid expression after '" & p.subsChar & "'")
        else:
          p.write(p.x[j])
          inc(j)

    p.write("\\n\"")

proc parseDirective(firstLine: string): tuple[subsChar, nimDirective: char, emit, conc, toStr: string] =
  ## Parse #? stdtmpl(...) directive to extract options
  result = (subsChar: '$', nimDirective: '#', emit: "result.add", conc: " & ", toStr: "$")

  # Find the arguments part
  let parenStart = firstLine.find('(')
  if parenStart < 0:
    return

  let parenEnd = firstLine.rfind(')')
  if parenEnd <= parenStart:
    return

  let args = firstLine[parenStart+1 ..< parenEnd]

  # Parse key=value pairs (simplified parser)
  for part in args.split(','):
    let kv = part.strip().split('=')
    if kv.len != 2:
      continue
    let key = kv[0].strip().toLowerAscii()
    var val = kv[1].strip()

    # Handle char literals 'x' and string literals "x"
    if val.len >= 2:
      if val[0] == '\'' and val[^1] == '\'':
        val = val[1..^2]
      elif val[0] == '"' and val[^1] == '"':
        val = val[1..^2]

    case key
    of "subschar":
      if val.len == 1:
        result.subsChar = val[0]
    of "metachar":
      if val.len == 1:
        result.nimDirective = val[0]
    of "emit":
      result.emit = val
    of "conc":
      result.conc = val
    of "tostring":
      result.toStr = val

proc filterStdTmpl*(input: string, subsChar = '$', nimDirective = '#',
                    emit = "result.add", conc = " & ", toStr = "$"): string =
  ## Transform stdtmpl source code filter syntax into valid Nim code.
  ##
  ## Parameters match the stdtmpl directive options:
  ## - subsChar: substitution character (default '$')
  ## - nimDirective: Nim code line prefix (default '#')
  ## - emit: proc to emit text (default "result.add")
  ## - conc: concatenation operator (default " & ")
  ## - toStr: stringify operator (default "$")

  var p = TmplParser(
    state: psDirective,
    line: 0,
    indent: 0,
    emitPar: 0,
    subsChar: subsChar,
    nimDirective: nimDirective,
    emit: emit,
    conc: conc,
    toStr: toStr,
    output: ""
  )

  for line in input.splitLines:
    inc p.line
    p.x = line

    # Skip first line if it's the directive
    if p.line == 1 and line.startsWith("#?"):
      continue

    p.parseLine()

  p.newLine()
  result = p.output

proc filterStdTmplAuto*(input: string): string =
  ## Transform stdtmpl with automatic directive parsing.
  ## Reads options from the #? stdtmpl(...) line if present.

  var firstLine = ""
  for line in input.splitLines:
    firstLine = line
    break

  if firstLine.startsWith("#?"):
    let opts = parseDirective(firstLine)
    result = filterStdTmpl(input, opts.subsChar, opts.nimDirective, opts.emit, opts.conc, opts.toStr)
  else:
    result = filterStdTmpl(input)

# Dynlib exports for use as shared library

# Simple C-string interface (null-terminated input)
proc scfFilter*(input: cstring): cstring {.exportc, dynlib.} =
  ## Transform SCF input. Returns transformed output or nil on error.
  ## Caller must free result with scfFree.
  try:
    let transformed = filterStdTmplAuto($input)
    let buf = cast[ptr UncheckedArray[char]](alloc(transformed.len + 1))
    if transformed.len > 0:
      copyMem(buf, addr transformed[0], transformed.len)
    buf[transformed.len] = '\0'
    return cast[cstring](buf)
  except ScfError:
    return nil

# Full interface with length and error handling
proc scfTransform*(input: cstring, inputLen: cint, output: ptr cstring, outputLen: ptr cint): cint {.exportc, dynlib.} =
  ## Transform SCF input. Returns 0 on success, 1 on error.
  ## Caller must free output with scfFree.
  try:
    let nimInput = if inputLen > 0: newString(inputLen) else: ""
    if inputLen > 0:
      copyMem(addr nimInput[0], input, inputLen)
    let transformed = filterStdTmplAuto(nimInput)
    let buf = cast[ptr UncheckedArray[char]](alloc(transformed.len + 1))
    if transformed.len > 0:
      copyMem(buf, addr transformed[0], transformed.len)
    buf[transformed.len] = '\0'
    output[] = cast[cstring](buf)
    outputLen[] = transformed.len.cint
    return 0
  except ScfError as e:
    let errMsg = e.msg
    let buf = cast[ptr UncheckedArray[char]](alloc(errMsg.len + 1))
    if errMsg.len > 0:
      copyMem(buf, addr errMsg[0], errMsg.len)
    buf[errMsg.len] = '\0'
    output[] = cast[cstring](buf)
    outputLen[] = errMsg.len.cint
    return 1

proc scfFree*(p: pointer) {.exportc, dynlib.} =
  ## Free memory allocated by scfTransform
  dealloc(p)

# CLI
when isMainModule:
  import std/os

  proc main() =
    var input: string

    if paramCount() > 0:
      let filename = paramStr(1)
      if filename == "-h" or filename == "--help":
        echo "Usage: scf [file]"
        echo "Transforms Nim source code filter (stdtmpl) syntax to valid Nim."
        echo "Reads from stdin if no file given."
        quit(0)
      input = readFile(filename)
    else:
      input = stdin.readAll()

    try:
      echo filterStdTmplAuto(input)
    except ScfError as e:
      stderr.writeLine "scf: " & e.msg
      quit(1)

  main()
