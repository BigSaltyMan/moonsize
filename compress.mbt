///|
/// Compression, for the question raw sizes cannot answer: what a module costs
/// once it is on the wire.
///
/// Servers serve WebAssembly gzip-compressed, and how much that saves depends
/// almost entirely on what the bytes look like. A name section full of symbols
/// and strings shrinks several times over; a data section full of already-packed
/// numbers barely moves. The raw section table therefore overstates what some
/// sections cost and understates others, and it is the compressed shares that
/// describe a transfer.

///|
/// Compress `data` as a gzip stream.
///
/// The compressor runs at its default level — six, which is what servers use —
/// so the result is what a transfer would pay rather than the best a compressor
/// could manage. It stays an estimate in two ways worth knowing about: a server
/// may be configured for a different level, and it compresses the response as a
/// whole rather than each section on its own.
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
/// A section measured before and after compression.
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
    let start = section.offset
    let end = start + section.total_size
    // A truncated file can claim a section that runs past its own end, so what
    // is missing is measured as nothing rather than indexed out of bounds.
    let bytes = if start >= 0 && start <= end && end <= data.length() {
      data[start:end].to_owned()
    } else {
      Bytes::new(0)
    }
    rows.push({
      label: section_label(section),
      raw: section.total_size,
      gzip: compressed_size(bytes),
    })
  }
  rows
}

///|
/// The compressed size of `data[offset : offset + length]`, or why there is none.
///
/// This is how a section or a function body is measured on its own: the caller
/// has the offsets the decoder recorded, not a slice of its own. A range that
/// does not fit the file is reported too — measuring it as its own length would
/// be the same silent guess in a different place.
fn compressed_span(
  data : Bytes,
  offset : Int,
  length : Int,
) -> Result[Int, String] {
  let end = offset + length
  if offset < 0 || offset > end || end > data.length() {
    return Err(
      "range " +
      offset.to_string() +
      ".." +
      end.to_string() +
      " is outside a file of " +
      data.length().to_string() +
      " bytes",
    )
  }
  compressed_size(data[offset:end].to_owned())
}
