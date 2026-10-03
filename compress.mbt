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
/// The compressed size of `data` in bytes, or its raw size when it cannot be
/// compressed at all.
///
/// Falling back rather than failing keeps a report renderable: one stream the
/// compressor refuses should not take the run down, and claiming it shrank would
/// be worse than saying it did not.
pub fn compressed_size(data : Bytes) -> Int {
  match compress_gzip(data) {
    Ok(compressed) => compressed.length()
    Err(_) => data.length()
  }
}

///|
/// A section measured before and after compression.
pub struct SectionCompression {
  label : String
  raw : Int
  gzip : Int
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
