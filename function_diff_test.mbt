///|
/// Complete modules built independently of the matching implementation. Each
/// local function has a locals vector, n NOPs and end; optional names use the
/// full function index space after imports. Tests use only public comparison.
fn diff_leb(value : Int) -> Array[Byte] {
  let out : Array[Byte] = []
  let mut value = value
  while value >= 128 {
    out.push(((value & 127) | 128).to_byte())
    value = value >> 7
  }
  out.push(value.to_byte())
  out
}

///|
fn diff_append(out : Array[Byte], bytes : Array[Byte]) -> Unit {
  for byte in bytes {
    out.push(byte)
  }
}

///|
fn diff_section(out : Array[Byte], id : Int, payload : Array[Byte]) -> Unit {
  out.push(id.to_byte())
  diff_append(out, diff_leb(payload.length()))
  diff_append(out, payload)
}

///|
fn diff_name(out : Array[Byte], name : String) -> Unit {
  let bytes = @utf8.encode(name)
  diff_append(out, diff_leb(bytes.length()))
  for byte in bytes {
    out.push(byte)
  }
}

///|
fn diff_module(functions : Array[(String?, Int)], imported? : Int = 0) -> Bytes {
  let out : Array[Byte] = [0, 97, 115, 109, 1, 0, 0, 0]
  diff_section(out, 1, [1, 96, 0, 0])
  if imported > 0 {
    let payload = diff_leb(imported)
    for _ in 0..<imported {
      diff_append(payload, [1, 109, 1, 102, 0, 0])
    }
    diff_section(out, 2, payload)
  }
  let declarations = diff_leb(functions.length())
  let bodies = diff_leb(functions.length())
  let names : Array[Byte] = []
  let mut named = 0
  for i, (name, nops) in functions {
    declarations.push(0)
    diff_append(bodies, diff_leb(nops + 2))
    bodies.push(0)
    for _ in 0..<nops {
      bodies.push(1)
    }
    bodies.push(11)
    if name is Some(name) {
      named += 1
      diff_append(names, diff_leb(i + imported))
      diff_name(names, name)
    }
  }
  diff_section(out, 3, declarations)
  diff_section(out, 10, bodies)
  if named > 0 {
    let payload : Array[Byte] = [4, 110, 97, 109, 101, 1]
    let entries = diff_leb(named)
    diff_append(entries, names)
    diff_append(payload, diff_leb(entries.length()))
    diff_append(payload, entries)
    diff_section(out, 0, payload)
  }
  Bytes::from_array(out)
}

///|
fn compare_fixture(
  before : Bytes,
  after : Bytes,
) -> @moonsize.ModuleSizeDiff raise {
  match @moonsize.compare_modules(before, after) {
    Ok(diff) => diff
    Err(_) => fail("unexpected comparison input failure")
  }
}

///|
fn assert_diff_accounts(diff : @moonsize.ModuleSizeDiff) -> Unit raise {
  let baseline : Set[Int] = Set([])
  let current : Set[Int] = Set([])
  let mut row_delta = 0
  let mut before_bytes = 0
  let mut after_bytes = 0
  for row in diff.functions {
    if row.baseline is Some(stat) {
      assert_false(baseline.contains(stat.index))
      baseline.add(stat.index)
      before_bytes += stat.total_size
    }
    if row.current is Some(stat) {
      assert_false(current.contains(stat.index))
      current.add(stat.index)
      after_bytes += stat.total_size
    }
    if !(row.status is Matched) {
      assert_false(row.baseline is Some(_) && row.current is Some(_))
    }
    row_delta += row.delta
  }
  assert_eq(baseline.length(), diff.baseline_code.function_count)
  assert_eq(current.length(), diff.current_code.function_count)
  assert_eq(before_bytes, diff.baseline_code.function_bytes)
  assert_eq(after_bytes, diff.current_code.function_bytes)
  assert_eq(row_delta, after_bytes - before_bytes)
  let mut package_before = 0
  let mut package_after = 0
  for row in diff.packages {
    assert_eq(row.delta, row.current_size - row.baseline_size)
    package_before += row.baseline_size
    package_after += row.current_size
  }
  assert_eq(package_before, before_bytes)
  assert_eq(package_after, after_bytes)
  assert_eq(
    diff.baseline_code.function_bytes + diff.baseline_code.overhead,
    diff.baseline_code.code_size,
  )
  assert_eq(
    diff.current_code.function_bytes + diff.current_code.overhead,
    diff.current_code.code_size,
  )
  assert_eq(diff.delta, diff.current_size - diff.baseline_size)
  let s = diff.matching
  assert_eq(
    s.matched_baseline.count +
    s.removed_symbols.count +
    s.ambiguous_baseline.count +
    s.missing_baseline.count,
    baseline.length(),
  )
  assert_eq(
    s.matched_current.count +
    s.added_symbols.count +
    s.ambiguous_current.count +
    s.missing_current.count,
    current.length(),
  )
  assert_eq(
    s.matched_baseline.bytes +
    s.removed_symbols.bytes +
    s.ambiguous_baseline.bytes +
    s.missing_baseline.bytes,
    before_bytes,
  )
  assert_eq(
    s.matched_current.bytes +
    s.added_symbols.bytes +
    s.ambiguous_current.bytes +
    s.missing_current.bytes,
    after_bytes,
  )
  assert_eq(
    s.matched_delta +
    s.added_symbols.bytes -
    s.removed_symbols.bytes +
    s.ambiguous_current.bytes +
    s.missing_current.bytes -
    s.ambiguous_baseline.bytes -
    s.missing_baseline.bytes,
    row_delta,
  )
}

///|
test "function diff self comparison retains exact raw symbols and zero deltas" {
  let data = diff_module([(Some("pkg/a"), 0), (Some("pkg/b"), 4)])
  let diff = compare_fixture(data, data)
  assert_diff_accounts(diff)
  assert_eq(diff.matching.matched_current.count, 2)
  assert_eq(diff.matching.matched_delta, 0)
  assert_eq(diff.delta, 0)
  for row in diff.functions {
    assert_true(row.status is Matched)
    assert_eq(row.delta, 0)
  }
  assert_eq(diff.packages[0].name, "pkg")
  assert_eq(diff.packages[0].delta, 0)
}

///|
test "symbol identities survive reordered functions and inserted imports" {
  let before = diff_module([(Some("pkg/a"), 0), (Some("pkg/b"), 4)])
  let after = diff_module([(Some("pkg/b"), 4), (Some("pkg/a"), 0)], imported=2)
  let diff = compare_fixture(before, after)
  assert_diff_accounts(diff)
  assert_eq(diff.matching.matched_current.count, 2)
  assert_eq(diff.matching.matched_delta, 0)
  for row in diff.functions {
    let a = row.baseline.unwrap()
    let b = row.current.unwrap()
    assert_eq(a.raw_name, b.raw_name)
    assert_true(a.index != b.index)
    assert_eq(row.delta, 0)
  }
}

///|
test "growth shrinkage additions and disappeared symbols reconcile independently" {
  let diff = compare_fixture(
    diff_module([
      (Some("p/grow"), 0),
      (Some("p/shrink"), 5),
      (Some("old/gone"), 0),
    ]),
    diff_module([
      (Some("p/grow"), 4),
      (Some("p/shrink"), 2),
      (Some("new/added"), 1),
    ]),
  )
  assert_diff_accounts(diff)
  assert_eq(diff.matching.matched_delta, 1)
  assert_eq(diff.matching.added_symbols.bytes, 4)
  assert_eq(diff.matching.removed_symbols.bytes, 3)
  assert_eq(diff.functions[0].raw_name, Some("new/added")) // +4 ties: identity wins.
  assert_eq(diff.functions[1].raw_name, Some("p/grow"))
  assert_eq(diff.functions[2].delta, -3)
  assert_eq(diff.packages.length(), 3)
}

///|
test "any duplicate symbol makes every related record ambiguous" {
  for
    (before, after) in [
      ([(Some("dup"), 0), (Some("dup"), 2)], [(Some("dup"), 1)]),
      ([(Some("dup"), 1)], [(Some("dup"), 0), (Some("dup"), 2)]),
      (
        [(Some("dup"), 0), (Some("dup"), 2)],
        [(Some("dup"), 1), (Some("dup"), 3)],
      ),
      ([(Some("dup"), 0), (Some("dup"), 2)], []),
    ] {
    let diff = compare_fixture(diff_module(before), diff_module(after))
    assert_diff_accounts(diff)
    assert_eq(diff.functions.length(), before.length() + after.length())
    for row in diff.functions {
      assert_true(row.status is AmbiguousSymbol)
    }
    assert_eq(diff.matching.added_symbols.count, 0)
    assert_eq(diff.matching.removed_symbols.count, 0)
    assert_eq(diff.matching.matched_current.count, 0)
  }
}

///|
test "display name collisions never merge distinct original symbols" {
  let mangled = "_M0FPB7printlnGsE"
  let plain = "println"
  assert_eq(@moonsize.display_name(mangled), @moonsize.display_name(plain))
  let diff = compare_fixture(
    diff_module([(Some(mangled), 0)]),
    diff_module([(Some(plain), 0)]),
  )
  assert_diff_accounts(diff)
  assert_eq(diff.matching.matched_current.count, 0)
  assert_eq(diff.matching.added_symbols.count, 1)
  assert_eq(diff.matching.removed_symbols.count, 1)
  let both = compare_fixture(
    diff_module([(Some(mangled), 0), (Some(plain), 3)]),
    diff_module([(Some(plain), 3), (Some(mangled), 0)]),
  )
  assert_diff_accounts(both)
  assert_eq(both.matching.matched_current.count, 2)
}

///|
test "missing empty and literal unnamed symbols remain distinct" {
  let data = diff_module([(None, 0), (Some(""), 2), (Some("(unnamed)"), 1)])
  let diff = compare_fixture(data, data)
  assert_diff_accounts(diff)
  assert_eq(diff.matching.matched_current.count, 1)
  assert_eq(diff.matching.missing_current.count, 2)
  for row in diff.functions {
    if row.status is Matched {
      assert_eq(row.raw_name, Some("(unnamed)"))
      assert_eq(row.current.unwrap().name, "(unnamed)")
      assert_eq(row.current.unwrap().module_name, "(top-level)")
    } else {
      assert_eq(row.raw_name, None)
    }
  }
  assert_eq(diff.packages.length(), 2)
}

///|
test "body prefix boundary contributes to encoded size difference" {
  let diff = compare_fixture(
    diff_module([(Some("f"), 125)]),
    diff_module([(Some("f"), 126)]),
  )
  assert_diff_accounts(diff)
  let row = diff.functions[0]
  assert_eq(row.baseline.unwrap().body_size, 127)
  assert_eq(row.current.unwrap().body_size, 128)
  assert_eq(row.baseline.unwrap().total_size, 128)
  assert_eq(row.current.unwrap().total_size, 130)
  assert_eq(row.delta, 2)
}

///|
test "empty absent and explicit code sections retain their real overhead" {
  let header = b"\x00asm\x01\x00\x00\x00"
  let diff = compare_fixture(header, header + b"\x0a\x01\x00")
  assert_diff_accounts(diff)
  assert_eq(diff.baseline_code.overhead, 0)
  assert_eq(diff.current_code.overhead, 3)
  assert_eq(diff.current_code.function_count, 0)
  assert_eq(diff.delta, 3)
}

///|
test "function count prefix growth remains unassigned code overhead" {
  let before : Array[(String?, Int)] = []
  for _ in 0..<127 {
    before.push((None, 0))
  }
  let after = before.copy()
  after.push((None, 0))
  let diff = compare_fixture(diff_module(before), diff_module(after))
  assert_diff_accounts(diff)
  assert_eq(
    diff.current_code.function_bytes - diff.baseline_code.function_bytes,
    3,
  )
  assert_eq(diff.current_code.overhead - diff.baseline_code.overhead, 1)
}

///|
test "comparison errors distinguish structure and collection failures by side" {
  let valid = b"\x00asm\x01\x00\x00\x00"
  for bad in [b"\x00asm\x02\x00\x00\x00", valid + b"\x02\x01\x01"] {
    match @moonsize.compare_modules(bad, valid) {
      Err(Baseline(_)) => ()
      _ => fail("expected baseline failure")
    }
    match @moonsize.compare_modules(valid, bad) {
      Err(Current(_)) => ()
      _ => fail("expected current failure")
    }
  }
}

///|
test "comparison requires sizes not a complete baseline call graph" {
  let indirect = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x04\x04\x01\x70\x00\x01\x0a\x09\x01\x07\x00\x41\x00\x13\x00\x00\x0b"
  let diff = compare_fixture(indirect, b"\x00asm\x01\x00\x00\x00")
  assert_diff_accounts(diff)
  assert_eq(diff.matching.missing_baseline.count, 1)
}

///|
test "public text report keeps summaries when rankings are hidden" {
  let data = diff_module([(None, 0), (Some("a"), 3)])
  let diff = compare_fixture(data, data)
  let text = @moonsize.render_function_diff(diff, 0)
  for
    heading in [
      "FUNCTION SIZE CHANGES", "PACKAGE SIZE CHANGES", "MATCHING SUMMARY", "CODE OVERHEAD",
    ] {
    assert_true(text.contains(heading))
  }
  assert_true(text.contains("detail rankings hidden"))
  assert_true(text.contains("ambiguous or missing symbols"))
  assert_true(
    text.contains(
      "Function delta = matched 0 + added 0 - removed 0 + unmatched current 3 - unmatched baseline 3 = 0 B.",
    ),
  )
  assert_false(text.contains("RAW_SYMBOL"))
  assert_false(text.contains("BASE_FUNCS"))
}

///|
test "function text ranks by magnitude and escapes raw identities" {
  let diff = compare_fixture(
    diff_module([(Some("z"), 2), (Some("a\n\""), 2)]),
    diff_module([(Some("z"), 0), (Some("a\n\""), 0)]),
  )
  assert_diff_accounts(diff)
  assert_eq(diff.functions[0].raw_name, Some("a\n\""))
  let text = @moonsize.render_function_diff(diff, 10)
  assert_true(text.contains("\"a\\n\\\"\""))
  assert_true(text.contains("-2"))
  assert_true(text.contains("-4"))
}

///|
test "lossy debug name decoding cannot manufacture a shared symbol identity" {
  let data = diff_module([(Some("x"), 0)])
  let bytes : Array[Byte] = []
  for byte in data {
    bytes.push(byte)
  }
  bytes[bytes.length() - 1] = 0xff
  let before = Bytes::from_array(bytes)
  let other = bytes.copy()
  other[other.length() - 1] = 0xfe
  let diff = compare_fixture(before, Bytes::from_array(other))
  assert_diff_accounts(diff)
  assert_eq(diff.matching.matched_current.count, 0)
  assert_eq(diff.matching.missing_baseline.count, 1)
  assert_eq(diff.matching.missing_current.count, 1)
  // A real replacement character and BOM are valid symbols, not decode errors.
  let valid = diff_module([(Some("\u{fffd}"), 0), (Some("\u{feff}f"), 1)])
  let self_diff = compare_fixture(valid, valid)
  assert_diff_accounts(self_diff)
  assert_eq(self_diff.matching.matched_current.count, 2)
  let bom = compare_fixture(
    diff_module([(Some("\u{feff}f"), 0)]),
    diff_module([(Some("f"), 0)]),
  )
  assert_eq(bom.matching.matched_current.count, 0)
}
