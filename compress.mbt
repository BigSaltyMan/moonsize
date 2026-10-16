///|
/// Whole-file gzip measures one complete Wasm file as one stream. Independent
/// section and function streams measure local compressibility: they are not
/// additive and do not attribute whole-file transfer bytes to individual pieces.

///|
/// Compress `data` as a gzip stream.
///
/// Keep the compressor's current defaults. A server may use another gzip
/// configuration, another content encoding, or no compression at all.
pub fn compress_gzip(data : Bytes) -> Result[Bytes, String] {
  Ok(@gzip.compress(data)) catch {
    error => Err(error.to_string())
  }
}

///|
/// The compressed size of `data` in bytes, or why the compressor would not take
/// it.
///
/// The failure comes back as a failure rather than being swallowed into the raw
/// size. Returning `data.length()` would render as a ratio of 1.00x, which reads
/// as "this stream does not compress" when the truth is that nothing was measured
/// at all — a report that cannot tell those apart is worse than one that admits
/// it is missing a number.
pub fn compressed_size(data : Bytes) -> Result[Int, String] {
  match compress_gzip(data) {
    Ok(compressed) => Ok(compressed.length())
    Err(message) => Err(message)
  }
}

///|
/// A section's complete encoding (id, length prefix and payload), measured as
/// its own gzip stream. `raw` is the length of that same encoding.
pub struct SectionCompression {
  label : String
  raw : Int
  /// The section's compressed size, or why the compressor refused it.
  gzip : Result[Int, String]
}

///|
/// Compress each section of `parsed` on its own, out of the file it was read
/// from, heaviest raw section first.
///
/// Each section becomes its own gzip stream, so each pays its own container —
/// roughly twenty bytes of magic, header, CRC and length. That is invisible for a
/// section of kilobytes and dominant for one of a handful of bytes, which is why
/// a tiny section can come back larger than it went in.
///
/// This is what `render_compression` is handed instead of bare `Section`s: a
/// `Section` records where its bytes are, not what they are, and a section
/// cannot be compressed without them.
pub fn compress_sections(
  data : Bytes,
  parsed : WasmModule,
) -> Array[SectionCompression] {
  let rows : Array[SectionCompression] = []
  for section in ordered_sections(parsed) {
    rows.push({
      label: section_label(section),
      raw: section.total_size,
      gzip: compressed_span(data, section.offset, section.total_size),
    })
  }
  rows
}

///|
/// The compressed size of `data[offset : offset + length]`, or why there is none.
///
/// This is how a complete section or encoded function (including its size
/// prefix, using `total_size`) is measured independently: the caller
/// has the offsets the decoder recorded, not a slice of its own. A range that
/// does not fit the file is reported too — measuring it as its own length would
/// be the same silent guess in a different place.
fn compressed_span(
  data : Bytes,
  offset : Int,
  length : Int,
) -> Result[Int, String] {
  // Validate by subtraction before adding: even a huge length cannot overflow.
  if offset < 0 ||
    length < 0 ||
    offset > data.length() ||
    length > data.length() - offset {
    return Err(
      "invalid compression range: offset " +
      offset.to_string() +
      ", length " +
      length.to_string() +
      ", file length " +
      data.length().to_string(),
    )
  }
  let end = offset + length
  compressed_size(data[offset:end].to_owned())
}
