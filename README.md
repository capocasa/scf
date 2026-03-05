# scf - Standalone Nim Source Code Filter

A standalone implementation of Nim's `stdtmpl` source code filter, extracted from the compiler for use at compile-time in macro contexts.

## Why

Nim's source code filters (SCF) like `#? stdtmpl` are processed by the compiler before parsing. This makes them impossible to use with `parseStmt()` in macros - the filter syntax isn't valid Nim.

This package provides the same transformation as a pure function, allowing:
```nim
const scfSource = staticRead("template.nimf")
const nimSource = filterStdTmplAuto(scfSource)  # transform at compile-time
let ast = parseStmt(nimSource)  # now it's valid Nim
```

## Usage

### As a library
```nim
import scf

# Auto-detect options from #? directive
let output = filterStdTmplAuto(input)

# Or specify options manually
let output = filterStdTmpl(input,
  subsChar = '$',
  nimDirective = '#',
  emit = "result.add",
  conc = " & ",
  toStr = "$")
```

### As CLI
```bash
scf template.nimf > output.nim
cat template.nimf | scf > output.nim
```

## Supported Features

All `stdtmpl` features are supported:
- `$var` and `${expr}` substitution
- `$$` escape for literal `$`
- Control flow: `if/elif/else/end`, `for/end`, `while/end`, `try/except/finally/end`
- Declarations: `let`, `var`, `const`, `type`, `proc`, `template`, `macro`, etc.
- Custom parameters: `subsChar`, `metaChar`, `emit`, `conc`, `tostring`

## Whitespace Behavior

The output is **functionally equivalent** to the Nim compiler's filter, not byte-identical. Differences:

1. **String literal continuation indentation** - My output uses 4-space continuation; compiler varies. Both produce identical runtime output.

2. **Trailing content** - Minor differences in how trailing newlines are grouped into `result.add()` calls.

These differences are all **inside string literals** or **inside parentheses**, so they don't affect Nim's indentation-based parsing. The generated code compiles and runs identically.

## Testing

```bash
nim c -r tests/test_scf.nim
```

18 tests covering all stdtmpl features, verified against examples from Nim's official documentation.

## License

MIT (same as Nim)
