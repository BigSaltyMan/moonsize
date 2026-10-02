///|
test "demangles a package-qualified moonbit symbol" {
  inspect(
    display_name("_M0FP34demo6sample3src8classify"),
    content="demo::sample::src::classify",
  )
}

///|
test "demangles a namespace count that has no length of its own" {
  // `26mizchi` is the package-segment count `2` followed by length `6`.
  inspect(
    display_name("_M0FP26mizchi5bench9ackermann"),
    content="mizchi::bench::ackermann",
  )
}

///|
test "drops a generic instantiation suffix" {
  inspect(display_name("_M0FPB7printlnGsE"), content="println")
}

///|
test "keeps doubled underscores, which stand in for one underscore" {
  inspect(
    display_name("_M0FP26mizchi5bench11mandel__sum"),
    content="mizchi::bench::mandel__sum",
  )
}

///|
test "leaves names it cannot decode exactly as they were" {
  inspect(display_name("fd_write"), content="fd_write")
  inspect(display_name("tlsf/searchBlock"), content="tlsf/searchBlock")
  inspect(display_name("_M0FPXXXXX"), content="_M0FPXXXXX")
  inspect(display_name(""), content="")
}

///|
test "groups a mangled symbol by the package it names" {
  inspect(module_of("_M0FP34demo6sample3src3fib"), content="demo::sample::src")
  inspect(
    module_of(
      "_M0FP311moonbitlang6parser11pkg__parser36is__statement__start__after__newline",
    ),
    content="moonbitlang::parser::pkg__parser",
  )
}

///|
test "groups a plain symbol by its leading path" {
  inspect(module_of("tlsf/searchBlock"), content="tlsf")
  inspect(module_of("moonbit.malloc"), content="moonbit")
  inspect(module_of("moonbit.gc.malloc"), content="moonbit.gc")
  inspect(module_of("moonbit.utf8.encode_from_utf16"), content="moonbit.utf8")
}

///|
test "a symbol with no package of its own is top level" {
  // An imported host function, and a mangled helper whose only segment is the
  // function name itself.
  inspect(module_of("fd_write"), content="(top-level)")
  inspect(module_of("_M0FPB7printlnGsE"), content="(top-level)")
}

///|
test "a function the binary never names is reported as unnamed" {
  inspect(module_of(""), content="(unnamed)")
}
