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

///|
test "the full decoder spells out a module path" {
  inspect(
    demangle_full("_M0FP34demo6sample3src8classify"),
    content="demo::sample::src::classify",
  )
  inspect(
    demangle_full("_M0FP55probe6mangle4demo6sample3src8classify"),
    content="probe::mangle::demo::sample::src::classify",
  )
}

///|
test "a package index that reads as a length does not swallow the path" {
  // `P55probe` is the package index `5` followed by `5probe`. Reading `55` as a
  // length matches too — the tail really is 55 characters — and taking the
  // longest match there turns the whole path into one nonsense segment.
  inspect(
    display_name("_M0FP55probe6mangle4demo6sample3src8classify"),
    content="probe::mangle::demo::sample::src::classify",
  )
  inspect(
    demangle_full(
      "_M0FP55probe6mangle4demo6sample3src25mixed___e5_90_8d_e5_ad_97",
    ),
    content="probe::mangle::demo::sample::src::mixed_名字",
  )
}

///|
test "escapes are resolved, doubled underscores first" {
  // `_2e` is `.`, `_24` is `$`.
  inspect(
    demangle_full("_M0MPC13int3Int18to__string_2einner"),
    content="int::Int::to_string.inner",
  )
  inspect(
    demangle_full("_M0IP016_24default__implPB4Show6outputGiE"),
    content="$default_impl::Show::output[Int]",
  )
  // A doubled underscore is a literal one, so a run of them is not a run of
  // escapes: `int__to__string__dec` is `int_to_string_dec`.
  inspect(
    demangle_full("_M0FPB20int__to__string__dec"),
    content="int_to_string_dec",
  )
  // `_5f` is the escape the table gives for `_`. The emitter writes a literal
  // underscore as `__` instead, but a decoder that meets `_5f` should not leave
  // it as text.
  inspect(demangle_full("_M0FPB5a_5fb"), content="a_b")
  // One non-ASCII character arrives as one escape per UTF-8 byte.
  inspect(
    demangle_full(
      "_M0FP55probe6mangle4demo6sample3src36_e4_b8_ad_e6_96_87_e5_87_bd_e6_95_b0",
    ),
    content="probe::mangle::demo::sample::src::中文函数",
  )
}

///|
test "escapes survive a segment longer than any fixed cap" {
  // This name is 67 characters once escaped; a decoder that only looks back a
  // fixed 64 characters finds nothing and gives up on the whole symbol.
  inspect(
    demangle_full(
      "_M0IPB13StringBuilderPB6Logger67write__char_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger",
    ),
    content="StringBuilder::Logger::write_char.dyncall_as_@moonbitlang/core/builtin.Logger",
  )
}

///|
test "a trait implementation decodes both of its paths" {
  // The type's package and the trait's package are both spelled out, and the
  // first one's marker sits stranded between them.
  inspect(
    demangle_full(
      "_M0IP55probe6mangle4demo6sample3src6CircleP55probe6mangle4demo6sample3src5Shape4area",
    ),
    content="probe::mangle::demo::sample::src::Circle::probe::mangle::demo::sample::src::Shape::area",
  )
}

///|
test "generic arguments are spelled out from their type codes" {
  // The letters were read back from a build with one instantiation per builtin
  // type, which is what makes this a decode rather than a guess.
  inspect(
    demangle_full("_M0FP55probe6mangle4demo6sample3src8identityGiE"),
    content="probe::mangle::demo::sample::src::identity[Int]",
  )
  inspect(
    demangle_full("_M0FP55probe6mangle4demo6sample3src8identityGsE"),
    content="probe::mangle::demo::sample::src::identity[String]",
  )
  inspect(
    demangle_full("_M0FP55probe6mangle4demo6sample3src8identityGdE"),
    content="probe::mangle::demo::sample::src::identity[Double]",
  )
  // Several arguments are just their codes in order.
  inspect(
    demangle_full("_M0MPC17hashmap7HashMap11new_2einnerGsiE"),
    content="hashmap::HashMap::new.inner[String, Int]",
  )
  // A tuple nests its own list.
  inspect(
    demangle_full("_M0FP55probe6mangle4demo6sample3src12probe__tupleGUiiEE"),
    content="probe::mangle::demo::sample::src::probe_tuple[(Int, Int)]",
  )
  // A named argument carries a path, and is only decodable as the last code.
  inspect(
    demangle_full(
      "_M0FP55probe6mangle4demo6sample3src12probe__pointGRP55probe6mangle4demo6sample3src5PointE",
    ),
    content="probe::mangle::demo::sample::src::probe_point[probe::mangle::demo::sample::src::Point]",
  )
  // A named argument with arguments of its own.
  inspect(
    demangle_full(
      "_M0FP55probe6mangle4demo6sample3src12probe__arrayGRPB5ArrayGiEE",
    ),
    content="probe::mangle::demo::sample::src::probe_array[Array[Int]]",
  )
}

///|
test "a generic argument with an unknown type code is left undecoded" {
  // `GAkE` is not a letter any build produced a meaning for, so the arguments
  // are dropped rather than printed as something they might not be.
  inspect(demangle_full("_M0FPC15abort5abortGAkE"), content="abort::abort")
}

///|
test "a lifted closure says so, and keeps the line it came from" {
  // The environment the compiler builds for a closure is named after the
  // function it belongs to.
  inspect(demangle_full("_M0FP017____moonbit__main"), content="[closure]main")
  // A closure body carries `C<id>l<line>`.
  inspect(
    demangle_full("_M0FP55probe6mangle4demo6sample3src11make__adderC1460l22"),
    content="probe::mangle::demo::sample::src::make_adder[closure@22]",
  )
  inspect(
    demangle_full(
      "_M0FP55probe6mangle4demo6sample3src15nested__closureC1465l31",
    ),
    content="probe::mangle::demo::sample::src::nested_closure[closure@31]",
  )
}

///|
test "the full decoder leaves anything it cannot decode alone" {
  // Not mangled by MoonBit at all.
  inspect(demangle_full("fd_write"), content="fd_write")
  inspect(demangle_full("tlsf/searchBlock"), content="tlsf/searchBlock")
  inspect(
    demangle_full("moonbit.utf8.encode_from_utf16"),
    content="moonbit.utf8.encode_from_utf16",
  )
  // Looks mangled, carries no component the walk can match.
  inspect(demangle_full("_M0FPXXXXX"), content="_M0FPXXXXX")
}

///|
test "the full decoder survives degenerate input" {
  inspect(demangle_full(""), content="")
  inspect(demangle_full("_"), content="_")
  inspect(demangle_full("___"), content="___")
  inspect(demangle_full("____"), content="____")
  inspect(demangle_full("_M0"), content="_M0")
  inspect(demangle_full("_M0F"), content="_M0F")
  inspect(demangle_full("_2e"), content="_2e")
}

///|
test "a symbol far past any real size is refused, not walked" {
  // The walk is bounded by a length guard, so a name forged into a binary cannot
  // drive it into a deep recursion. Nothing here may hang or overflow.
  let long_plain = "a".repeat(8000)
  inspect(demangle_full(long_plain), content=long_plain)
  let long_mangled = "_M0FP" + long_plain
  inspect(demangle_full(long_mangled), content=long_mangled)
  let digits = "9".repeat(3000)
  inspect(display_name(digits), content=digits)
}

///|
test "display_name stays the simplified path" {
  // The report uses this one; it decodes the path only, and leaves escapes,
  // generic arguments and closure markers as they were found.
  inspect(
    display_name("_M0MPC13int3Int18to__string_2einner"),
    content="int::Int::to__string_2einner",
  )
  inspect(
    display_name("_M0FP55probe6mangle4demo6sample3src8identityGiE"),
    content="probe::mangle::demo::sample::src::identity",
  )
}
