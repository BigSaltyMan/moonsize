///|
/// Compression, checked against what compression has to be rather than against
/// the numbers one file happens to produce: an empty input still yields a stream,
/// incompressible input does not get smaller, and repetitive input gets much
/// smaller.

///|
/// Deterministic pseudo-random bytes, so the "does not compress" case is a real
/// one and still reproducible.
fn noise(length : Int) -> Bytes {
  let out : Array[Byte] = []
  let mut state = 12345
  let mut i = 0
  while i < length {
    state = (state * 1103515245 + 12345) & 2147483647
    out.push((state / 65536 % 256).to_byte())
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
test "an empty input still produces a well-formed stream" {
  let compressed = match compress_gzip(Bytes::new(0)) {
    Ok(compressed) => compressed
    Err(message) => fail(message)
  }
  // A gzip stream has a header and a trailer even with nothing in it.
  inspect(compressed.length() > 0, content="true")
  inspect(compressed.length() < 40, content="true")
  inspect(
    compressed_size(Bytes::new(0)),
    content=compressed.length().to_string(),
  )
}

///|
test "a gzip stream decompresses back to what went in" {
  let data = @utf8.encode("the same words, over and over, over and over")
  let compressed = match compress_gzip(data) {
    Ok(compressed) => compressed
    Err(message) => fail(message)
  }
  let (restored, _header) = @gzip.decompress(compressed) catch {
    error => fail(error.to_string())
  }
  assert_eq(restored, data)
}

///|
test "incompressible data does not get smaller" {
  let data = noise(1024)
  let size = compressed_size(data)
  // A stream that cannot be compressed still has to be stored, plus its
  // container, so this is the case where the "compressed" size is the larger one.
  inspect(size > data.length(), content="true")
  assert_eq(data.length(), 1024)
}

///|
test "repetitive data compresses by a wide margin" {
  let data = @utf8.encode("moonbit ".repeat(1000))
  assert_eq(data.length(), 8000)
  let size = compressed_size(data)
  // The exact number depends on the deflate implementation, so the assertion is
  // the order of magnitude: this is what a name section full of symbols does.
  inspect(size < data.length() / 20, content="true")
}

///|
test "the compression report renders totals and the per-section table" {
  let sections : Array[SectionCompression] = [
    { label: "code", raw: 5166, gzip: 1543, },
    { label: "custom (name)", raw: 4975, gzip: 964, },
    { label: "data", raw: 252, gzip: 210, },
  ]
  inspect(
    render_compression(10675, 2891, sections),
    content=(
      #|COMPRESSED SIZE
      #|  raw   10675 B
      #|  gzip   2891 B  (27.0% of raw, ratio 3.69x)
      #|
      #|  BY SECTION
      #|
      #|  SECTION         RAW  GZIP  RATIO  SHARE(GZIP)
      #|  code           5166  1543  3.34x        53.3%
      #|  custom (name)  4975   964  5.16x        33.3%
      #|  data            252   210  1.20x         7.2%
      #|
    ),
  )
}

///|
test "a section that grew when compressed is not hidden" {
  // A ratio below one is the honest answer for a section smaller than a gzip
  // container, so it is printed rather than clamped.
  let sections : Array[SectionCompression] = [
    { label: "datacount", raw: 3, gzip: 27, },
  ]
  let text = render_compression(10675, 5207, sections)
  assert_true(text.contains("datacount"))
  assert_true(text.contains("0.11x"))
  assert_true(text.contains("0.5%"))
}

///|
test "the report copes with a module that has no sections" {
  let sections : Array[SectionCompression] = []
  let text = render_compression(8, 27, sections)
  assert_true(text.contains("no sections"))
  assert_true(text.contains("ratio 0.29x"))
}

///|
test "compression ratios are padded to two decimals" {
  // 1000 / 333 is 3.003…, which has to read as 3.00x and not 3.3x.
  let sections : Array[SectionCompression] = [
    { label: "x", raw: 1000, gzip: 333, },
  ]
  assert_true(render_compression(1000, 333, sections).contains("3.00x"))
}

///|
test "--compress is off unless it is asked for" {
  match parse_options(["moonsize", "app.wasm"]) {
    Ok(options) => inspect(options.compress, content="false")
    Err(message) => fail(message)
  }
  match parse_options(["moonsize", "app.wasm", "--compress"]) {
    Ok(options) => inspect(options.compress, content="true")
    Err(message) => fail(message)
  }
  // It combines with the other report sections rather than replacing them.
  match
    parse_options([
      "moonsize", "app.wasm", "--compress", "--retained", "--top", "3",
    ]) {
    Ok(options) => {
      inspect(options.compress, content="true")
      inspect(options.retained, content="true")
      inspect(options.top, content="3")
    }
    Err(message) => fail(message)
  }
}
