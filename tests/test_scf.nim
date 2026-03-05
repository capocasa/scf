import std/[unittest, strutils]
import ../src/scf

suite "SCF stdtmpl filter":

  test "simple XML template":
    let input = """#? stdtmpl(subsChar = '$', metaChar = '#')
#proc generateXML(name, age: string): string =
#  result = ""
<xml>
  <name>$name</name>
  <age>$age</age>
</xml>"""

    let output = filterStdTmplAuto(input)
    check "proc generateXML(name, age: string): string =" in output
    check "result = \"\"" in output
    check "$(name)" in output
    check "$(age)" in output
    check "<xml>" in output

  test "for loop with if/else":
    let input = """#? stdtmpl
#for tab in tabs:
#if tab == current:
<li class="selected">$tab</li>
#else:
<li>$tab</li>
#end if
#end for"""

    let output = filterStdTmplAuto(input)
    check "for tab in tabs:" in output
    check "if tab == current:" in output
    check "$(tab)" in output
    check "#end" in output  # end markers preserved as comments

  test "dollar escape $$":
    let input = """#? stdtmpl
A dollar: $$."""

    let output = filterStdTmplAuto(input)
    # $$ should become single $
    check "A dollar: $." in output

  test "expression with braces ${expr}":
    let input = """#? stdtmpl
href="${tab}.html">$tab</a>"""

    let output = filterStdTmplAuto(input)
    check "$(tab)" in output
    check ".html" in output

  test "custom emit parameter":
    let input = """#? stdtmpl(emit="echo")
Hello $name"""

    let output = filterStdTmplAuto(input)
    check "echo(" in output
    check "$(name)" in output
    check "result.add" notin output

  test "custom subsChar":
    let input = """#? stdtmpl(subsChar='%')
Hello %name"""

    let output = filterStdTmplAuto(input)
    check "$(name)" in output

  test "custom metaChar":
    let input = """#? stdtmpl(metaChar='@')
@var x = 5
Value: $x"""

    let output = filterStdTmplAuto(input)
    check "var x = 5" in output
    check "$(x)" in output

  test "let/var/const declarations":
    let input = """#? stdtmpl
#let x = 5
#var y = 10
#const z = 15
Values: $x $y $z"""

    let output = filterStdTmplAuto(input)
    check "let x = 5" in output
    check "var y = 10" in output
    check "const z = 15" in output

  test "proc definition":
    let input = """#? stdtmpl
#proc helper(s: string): string =
#  result = s & "!"
#end proc
Hello"""

    let output = filterStdTmplAuto(input)
    check "proc helper(s: string): string =" in output

  test "while loop":
    let input = """#? stdtmpl
#var i = 0
#while i < 3:
Item $i
#  inc i
#end while"""

    let output = filterStdTmplAuto(input)
    check "while i < 3:" in output
    check "inc i" in output

  test "try/except":
    let input = """#? stdtmpl
#try:
$riskyCall()
#except:
Error!
#end try"""

    let output = filterStdTmplAuto(input)
    check "try:" in output
    check "except:" in output

  test "block statement":
    let input = """#? stdtmpl
#block myBlock:
Content
#end block"""

    let output = filterStdTmplAuto(input)
    check "block myBlock:" in output

  test "multiline template preserves structure":
    let input = """#? stdtmpl
Line 1
Line 2
Line 3"""

    let output = filterStdTmplAuto(input)
    check "\\n" in output  # newlines encoded
    check output.count("result.add") >= 1

  test "nested braces in expression":
    let input = """#? stdtmpl
${items[0]}"""

    let output = filterStdTmplAuto(input)
    check "items[0]" in output

  test "complex expression":
    let input = """#? stdtmpl
${if x > 0: "positive" else: "negative"}"""

    let output = filterStdTmplAuto(input)
    check "if x > 0:" in output or """if x > 0: "positive" else: "negative"""" in output

  test "empty lines preserved":
    let input = """#? stdtmpl
Line 1

Line 3"""

    let output = filterStdTmplAuto(input)
    # Empty line should produce a newline in output
    check "\\n" in output

  test "special characters escaped":
    let input = """#? stdtmpl
<script>alert("xss")</script>"""

    let output = filterStdTmplAuto(input)
    check "\\\"" in output  # quotes escaped

  test "real-world HTML template":
    let input = """#? stdtmpl | standard
#proc generateHTMLPage(title, currentTab, content: string,
#                      tabs: openArray[string]): string =
#  result = ""
<head><title>$title</title></head>
<body>
  <div id="menu">
    <ul>
  #for tab in items(tabs):
    #if currentTab == tab:
    <li><a id="selected"
    #else:
    <li><a
    #end if
    href="${tab}.html">$tab</a></li>
  #end for
    </ul>
  </div>
  <div id="content">
    $content
    A dollar: $$.
  </div>
</body>"""

    let output = filterStdTmplAuto(input)
    # Check key structural elements
    check "proc generateHTMLPage" in output
    check "for tab in items(tabs):" in output
    check "if currentTab == tab:" in output
    check "$(title)" in output
    check "$(tab)" in output
    check "$(content)" in output
    check "A dollar: $." in output  # $$ -> $
