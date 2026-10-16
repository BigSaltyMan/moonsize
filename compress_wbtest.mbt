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
test "invalid compression spans fail without overflow or empty substitution" {
  let data = b"abcd"
  for
    (offset, length) in [
      (-1, 1),
      (0, -1),
      (5, 0),
      (3, 2),
      (1, 2147483647),
      (2147483647, 2147483647),
    ] {
    match compressed_span(data, offset, length) {
      Ok(_) => fail("invalid span was measured")
      Err(message) => {
        assert_true(message.contains("offset " + offset.to_string()))
        assert_true(message.contains("length " + length.to_string()))
        assert_true(message.contains("file length 4"))
      }
    }
  }
}

///|
test "section compression rejects invalid metadata instead of measuring empty bytes" {
  let parsed : WasmModule = {
    version: 1,
    file_size: 4,
    sections: [
      {
        id: 0,
        kind: Custom,
        offset: 3,
        payload_size: 2,
        total_size: 4,
        custom_name: Some("bad"),
      },
    ],
  }
  match compress_sections(b"abcd", parsed)[0].gzip {
    Err(_) => ()
    Ok(_) => fail("out-of-bounds section was compressed successfully")
  }
}

///|
test "compression reports independent streams without transfer shares" {
  let text = render_compression(100, Ok(50), [
    { label: "bad", raw: 10, gzip: Err("local failure"), },
    { label: "small", raw: 3, gzip: Ok(27), },
  ])
  assert_false(text.contains("SHARE(GZIP)"))
  assert_true(text.contains("INDEPENDENT GZIP STREAMS"))
  assert_true(text.contains("not additive"))
  assert_true(text.contains("50.0% of raw"))
  assert_true(text.contains("bad: local failure"))
  assert_true(text.contains("0.11x"))
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
      #|  BY SECTION — INDEPENDENT GZIP STREAMS
      #|
      #|  SECTION         RAW  GZIP  RATIO
      #|  code           5166  1543  3.34x
      #|  custom (name)  4975   964  5.16x
      #|  data            252   210  1.20x
      #|
      #|  Section gzip sizes are measured independently and are not additive.
      #|  They do not represent shares of the whole-file gzip size.
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
  assert_true(text.contains("48.7% of raw"))
  assert_false(text.contains("0.5%"))
}

///|
test "the report copes with a module that has no sections" {
  let sections : Array[SectionCompression] = []
  let text = render_compression(8, Ok(27), sections)
  assert_true(text.contains("no sections"))
  assert_true(text.contains("ratio 0.29x"))
  assert_true(text.contains("not additive"))
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
  // own number and ratio. No row depends on the whole-file measurement.
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
  // Its own size and ratio stand, because that stream was measured.
  assert_true(text.contains("2712"))
  assert_true(text.contains("1.90x"))
  assert_true(!text.contains("52.0%"))
}

///|
test "valid empty and whole-file spans use exactly their requested bytes" {
  let data = b"abcd"
  assert_eq(compressed_span(data, 0, 4), compressed_size(data))
  for offset in [0, 4] {
    assert_eq(compressed_span(data, offset, 0), compressed_size(b""))
  }
  assert_eq(compressed_span(data, 1, 2), compressed_size(b"bc"))
  let stream = match compress_gzip(data[1:3].to_owned()) {
    Ok(stream) => stream
    Err(message) => fail(message)
  }
  let (restored, _) = @gzip.decompress(stream) catch {
    error => fail(error.to_string())
  }
  assert_eq(restored, b"bc")
}

///|
test "independent full custom sections round trip but do not sum to whole-file gzip" {
  // Three identical, legal custom sections named x; each payload is 8 bytes.
  let data = b"\x00asm\x01\x00\x00\x00\x00\x08\x01xabcabc\x00\x08\x01xabcabc\x00\x08\x01xabcabc"
  let parsed = match parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(describe_error(error))
  }
  let rows = compress_sections(data, parsed)
  assert_eq(rows.length(), 3)
  let mut sum = 0
  for i, section in ordered_sections(parsed) {
    let bytes = data[section.offset:section.offset + section.total_size].to_owned()
    assert_eq(bytes, b"\x00\x08\x01xabcabc")
    assert_eq(rows[i].raw, 10)
    let stream = match compress_gzip(bytes) {
      Ok(stream) => stream
      Err(message) => fail(message)
    }
    let (restored, _) = @gzip.decompress(stream) catch {
      error => fail(error.to_string())
    }
    assert_eq(restored, bytes)
    assert_eq(rows[i].gzip, Ok(stream.length()))
    assert_true(
      render_compression(data.length(), compressed_size(data), rows).contains(
        ratio_text(10, stream.length()),
      ),
    )
    sum = sum + stream.length()
  }
  let whole = match compressed_size(data) {
    Ok(size) => size
    Err(message) => fail(message)
  }
  // This fixed sample witnesses non-additivity, not an inequality for all files.
  assert_true(sum != whole)
}

///|
test "one invalid section does not discard successful independent measurements" {
  let parsed : WasmModule = {
    version: 1,
    file_size: 4,
    sections: [
      {
        id: 0,
        kind: Custom,
        offset: 0,
        payload_size: 2,
        total_size: 4,
        custom_name: Some("good"),
      },
      {
        id: 0,
        kind: Custom,
        offset: 4,
        payload_size: 0,
        total_size: 2,
        custom_name: Some("bad"),
      },
    ],
  }
  let rows = compress_sections(b"abcd", parsed)
  assert_eq(rows[0].gzip, compressed_size(b"abcd"))
  assert_true(rows[1].gzip is Err(_))
  let text = render_compression(4, Ok(24), rows)
  assert_true(
    text.contains(
      "gzip failed for custom (bad): invalid compression range: offset 4, length 2, file length 4",
    ),
  )
  assert_true(text.contains("600.0% of raw"))
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
