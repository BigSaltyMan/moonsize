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
  // And the size helper agrees with the stream it just produced.
  match compressed_size(Bytes::new(0)) {
    Ok(size) => inspect(size, content=compressed.length().to_string())
    Err(message) => fail(message)
  }
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
  let size = match compressed_size(data) {
    Ok(size) => size
    Err(message) => fail(message)
  }
  // A stream that cannot be compressed still has to be stored, plus its
  // container, so this is the case where the "compressed" size is the larger one.
  inspect(size > data.length(), content="true")
  assert_eq(data.length(), 1024)
}

///|
test "repetitive data compresses by a wide margin" {
  let data = @utf8.encode("moonbit ".repeat(1000))
  assert_eq(data.length(), 8000)
  let size = match compressed_size(data) {
    Ok(size) => size
    Err(message) => fail(message)
  }
  // The exact number depends on the deflate implementation, so the assertion is
  // the order of magnitude: this is what a name section full of symbols does.
  inspect(size < data.length() / 20, content="true")
}

///|
test "the compression report renders totals and the per-section table" {
  let sections : Array[SectionCompression] = [
    { label: "code", raw: 5166, gzip: Ok(1543), },
    { label: "custom (name)", raw: 4975, gzip: Ok(964), },
    { label: "data", raw: 252, gzip: Ok(210), },
  ]
  inspect(
    render_compression(10675, Ok(2891), sections),
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
    { label: "datacount", raw: 3, gzip: Ok(27), },
  ]
  let text = render_compression(10675, Ok(5207), sections)
  assert_true(text.contains("datacount"))
  assert_true(text.contains("0.11x"))
  assert_true(text.contains("0.5%"))
}

///|
test "the report copes with a module that has no sections" {
  let sections : Array[SectionCompression] = []
  let text = render_compression(8, Ok(27), sections)
  assert_true(text.contains("no sections"))
  assert_true(text.contains("ratio 0.29x"))
}

///|
test "compression ratios are padded to two decimals" {
  // 1000 / 333 is 3.003…, which has to read as 3.00x and not 3.3x.
  let sections : Array[SectionCompression] = [
    { label: "x", raw: 1000, gzip: Ok(333), },
  ]
  assert_true(render_compression(1000, Ok(333), sections).contains("3.00x"))
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

///|
test "a refused compression is reported, not passed off as the raw size" {
  // The real compressor is unlikely to refuse a stream, so the failure is
  // injected where it enters the report — which the `Result` in the signature
  // exists to make possible. What is under test is that the report says so:
  // printing 10675 where the compressed size belongs would read as a ratio of
  // 1.00x, and that is a different claim from "nothing was measured".
  let sections : Array[SectionCompression] = [
    { label: "code", raw: 5166, gzip: Err("deflate refused the stream"), },
    { label: "data", raw: 252, gzip: Ok(174), },
  ]
  let text = render_compression(
    10675,
    Err("deflate refused the stream"),
    sections,
  )
  assert_true(text.contains("gzip  failed: deflate refused the stream"))
  // The raw size never appears where the compressed size belongs, and neither
  // does the ratio that would follow from it.
  assert_true(!text.contains("10675 B  ("))
  assert_true(!text.contains("ratio 1.00x"))
  // The section that failed says so, and the one that did not still shows its
  // own number — but no share anywhere, because with no total there is nothing
  // for a share to be a share of.
  assert_true(text.contains("failed"))
  assert_true(text.contains("174"))
  assert_true(!text.contains("%"))
}

///|
test "a section that compressed stays readable when the total did not" {
  let sections : Array[SectionCompression] = [
    { label: "code", raw: 5166, gzip: Ok(2712), },
  ]
  let text = render_compression(10675, Err("boom"), sections)
  // Its own size stands, because that one was measured...
  assert_true(text.contains("2712"))
  // ...but its share does not, because there is no total to be a share of.
  assert_true(!text.contains("52.0%"))
}

///|
test "the gzip card says N/A rather than a ratio of one" {
  let (value, sub, title) = gzip_card_fields(10675, Err("deflate refused"))
  inspect(value, content="N/A")
  inspect(sub, content="compression failed")
  // The reason travels with it, for the card's hover text.
  inspect(title, content="deflate refused")
  // And a successful card still reads exactly as it did.
  let (ok_value, ok_sub, ok_title) = gzip_card_fields(10675, Ok(5207))
  inspect(ok_value, content="5,207 B")
  inspect(ok_sub, content="48.7% of raw · 2.05x")
  inspect(ok_title, content="")
}
