///|
fn comparison_module(data : Bytes) -> @moonsize.WasmModule raise {
  match @moonsize.parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(@moonsize.describe_error(error))
  }
}

///|
test "public comparison aggregates the reproduced same-name custom sections" {
  let data = b"\x00asm\x01\x00\x00\x00\x00\x02\x01x\x00\x04\x01x\x00\x00"
  let parsed = comparison_module(data)
  assert_eq(parsed.file_size, 18)
  inspect(
    @moonsize.render_size_comparison(parsed, parsed),
    content=(
      #|SIZE COMPARISON
      #|
      #|              baseline  current  delta
      #|  total             18       18  0  (0.0%)
      #|  custom (x)        10       10  0  (0.0%)
      #|
    ),
  )
}

///|
/// Parse the rendered numeric columns, independent of the internal row model.
fn public_comparison_rows(
  before : @moonsize.WasmModule,
  after : @moonsize.WasmModule,
) -> Map[String, (Int, Int, Int)] raise {
  let rows : Map[String, (Int, Int, Int)] = Map([])
  for line in @moonsize.render_size_comparison(before, after).split("\n") {
    let columns = line
      .trim()
      .split(" ")
      .filter(column => column != "")
      .collect()
    if columns.length() < 5 {
      continue
    }
    let numeric = columns.length() - 4
    let labels : Array[String] = []
    for i = 0; i < numeric; i = i + 1 {
      labels.push(columns[i].to_owned())
    }
    let label = labels.join(" ")
    assert_true(!rows.contains(label))
    rows.set(
      label,
      (
        @string.parse_int(columns[numeric]),
        @string.parse_int(columns[numeric + 1]),
        @string.parse_int(columns[numeric + 2]),
      ),
    )
  }
  assert_true(rows.contains("total"))
  let mut before_sum = 0
  let mut after_sum = 0
  let mut delta_sum = 0
  for label, (baseline, current, delta) in rows {
    assert_eq(delta, current - baseline)
    if label != "total" {
      before_sum += baseline
      after_sum += current
      delta_sum += delta
    }
  }
  assert_eq(before_sum + 8, before.file_size)
  assert_eq(after_sum + 8, after.file_size)
  assert_eq(
    rows.get("total"),
    Some((before.file_size, after.file_size, delta_sum)),
  )
  rows
}

///|
test "public comparison reports exact forward reverse and whole-group deltas" {
  let a = comparison_module(
    b"\x00asm\x01\x00\x00\x00\x00\x02\x01x\x00\x04\x01x\x00\x00\x00\x02\x01y",
  )
  let b = comparison_module(
    b"\x00asm\x01\x00\x00\x00\x00\x03\x01x\x00\x00\x06\x01x\x00\x00\x00\x00\x00\x02\x01z",
  )
  let forward = public_comparison_rows(a, b)
  assert_eq(forward.get("custom (x)"), Some((10, 13, 3)))
  assert_eq(forward.get("custom (y)"), Some((4, 0, -4)))
  assert_eq(forward.get("custom (z)"), Some((0, 4, 4)))
  assert_eq(forward.get("total"), Some((22, 25, 3)))
  let reverse = public_comparison_rows(b, a)
  for label, (baseline, current, delta) in forward {
    assert_eq(reverse.get(label), Some((current, baseline, -delta)))
  }
}

///|
test "public comparison includes actual non-short section length encoding bytes" {
  let a = comparison_module(b"\x00asm\x01\x00\x00\x00\x00\x02\x01x")
  // Identical payload, but its length takes two bytes and its name length
  // takes two bytes. This is legal Wasm and costs two actual encoded bytes.
  let b = comparison_module(b"\x00asm\x01\x00\x00\x00\x00\x83\x00\x81\x00x")
  let rows = public_comparison_rows(a, b)
  assert_eq(rows.get("custom (x)"), Some((4, 6, 2)))
  assert_eq(rows.get("total"), Some((12, 14, 2)))
}

///|
test "public comparison preserves standard groups and distinguishes custom code" {
  let a = comparison_module(
    b"\x00asm\x01\x00\x00\x00\x01\x01\x00\x0a\x01\x00\x00\x05\x04code",
  )
  let b = comparison_module(
    b"\x00asm\x01\x00\x00\x00\x01\x81\x00\x00\x00\x07\x04code\x00\x00",
  )
  let rows = public_comparison_rows(a, b)
  assert_eq(rows.get("type"), Some((3, 4, 1)))
  assert_eq(rows.get("code"), Some((3, 0, -3)))
  assert_eq(rows.get("custom (code)"), Some((7, 9, 2)))
  assert_eq(rows.get("total"), Some((21, 21, 0)))
}
