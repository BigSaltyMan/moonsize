///|
fn data_group_kind(kind : DataPayloadGroupKind) -> String {
  match kind {
    SharedPayload => "shared_payload"
    BaselineOnly => "baseline_only"
    CurrentOnly => "current_only"
  }
}

///|
fn data_diff_scope() -> String {
  "Exact payload content groups are not source or stable entry identities. Equal payloads do not prove equal initialization semantics; duplicates do not prove safe deduplication. " +
  "Raw byte differences do not predict recompiled or whole-file gzip savings. " +
  data_scope()
}

///|
/// Display only: absolute encoded delta descending, full hash, length, local id.
fn ranked_data_groups(
  report : DataSegmentsComparison,
) -> Array[DataPayloadGroup] {
  let groups = report.groups.copy()
  groups.sort_by(fn(a, b) {
    let magnitude = delta_magnitude(b.delta.encoded_size) -
      delta_magnitude(a.delta.encoded_size)
    if magnitude != 0 {
      return magnitude
    }
    let hash = diff_identity_compare(a.sha256, b.sha256)
    if hash != 0 {
      return hash
    }
    if a.payload_length != b.payload_length {
      return a.payload_length - b.payload_length
    }
    a.id - b.id
  })
  groups
}

///|
/// Paths are display labels; complete file digests identify the compared bytes.
pub fn render_data_segments_diff(
  report : DataSegmentsComparison,
  baseline_path : String,
  current_path : String,
  top : Int,
) -> String {
  let out = StringBuilder()
  out.write_string("DATA SEGMENT CONTENT COMPARISON\n")
  out.write_string(
    "  baseline: " +
    baseline_path +
    "\n    SHA-256 " +
    report.baseline_sha256 +
    "\n",
  )
  out.write_string(
    "  current:  " +
    current_path +
    "\n    SHA-256 " +
    report.current_sha256 +
    "\n",
  )
  out.write_string(
    "  data section B: before " +
    report.baseline.section_size.to_string() +
    "; after " +
    report.current.section_size.to_string() +
    "; delta " +
    report.delta.section_size.to_string() +
    "\n",
  )
  out.write_string(
    "  delta (current - baseline): payload " +
    report.delta.payload_size.to_string() +
    " B; entry metadata " +
    report.delta.entry_metadata_size.to_string() +
    " B; section overhead " +
    report.delta.section_overhead_size.to_string() +
    " B\n",
  )
  for
    (label, side) in [
      ("baseline", report.baseline),
      ("current", report.current),
    ] {
    out.write_string(
      "  " +
      label +
      ": data " +
      (if side.section is Some(_) { "present" } else { "absent" }) +
      "; file offset " +
      (match side.section {
        Some(section) => section.offset.to_string()
        None => "n/a"
      }) +
      "; payload " +
      side.payload_size.to_string() +
      "; entry metadata " +
      side.entry_metadata_size.to_string() +
      "; section overhead " +
      (side.header_size + side.count_size).to_string() +
      " B; datacount " +
      (match side.datacount {
        Some(n) => n.to_string()
        None => "absent"
      }) +
      " (separate)\n",
    )
  }
  let groups = ranked_data_groups(report)
  let shown = if top < 0 {
    0
  } else if top < groups.length() {
    top
  } else {
    groups.length()
  }
  out.write_string(
    "  Showing " +
    shown.to_string() +
    " of " +
    groups.length().to_string() +
    " content groups; Top affects display only.\n",
  )
  out.write_string(
    "  PAYLOAD HASH  LENGTH  BEFORE COUNT  AFTER COUNT  PAYLOAD DELTA  ENCODED DELTA\n",
  )
  for i = 0; i < shown; i = i + 1 {
    let group = groups[i]
    // Prefix is only a display aid; local group id remains explicit.
    let prefix = @utf8.decode_lossy(@utf8.encode(group.sha256)[0:12])
    out.write_string(
      "  " +
      prefix +
      "  " +
      pad_left(group.payload_length.to_string(), 6) +
      "  " +
      pad_left(group.baseline.count.to_string(), 12) +
      "  " +
      pad_left(group.current.count.to_string(), 11) +
      "  " +
      pad_left(group.delta.payload_size.to_string(), 13) +
      "  " +
      pad_left(group.delta.encoded_size.to_string(), 13) +
      "\n",
    )
    out.write_string(
      "    group " +
      group.id.to_string() +
      " " +
      data_group_kind(group.kind) +
      "; metadata delta " +
      group.delta.metadata_size.to_string() +
      " B\n",
    )
  }
  out.write_string("\n  " + data_diff_scope())
  out.to_string()
}

///|
fn data_group_totals_json(totals : DataGroupTotals) -> Json {
  Json::object({
    "count": int_json(totals.count),
    "payload_size": int_json(totals.payload_size),
    "encoded_size": int_json(totals.encoded_size),
    "metadata_size": int_json(totals.metadata_size),
  })
}

///|
pub fn render_data_segments_diff_json(
  report : DataSegmentsComparison,
  baseline_path : String,
  current_path : String,
) -> String {
  let root : Map[String, Json] = Map([])
  root.set("format", Json::string("moonsize-data-segments-diff"))
  root.set("schema_version", int_json(1))
  root.set("scope", Json::string(data_diff_scope()))
  for
    (key, label, hash, details) in [
      ("baseline", baseline_path, report.baseline_sha256, report.baseline),
      ("current", current_path, report.current_sha256, report.current),
    ] {
    root.set(
      key,
      Json::object({
        "path": Json::string(label),
        "sha256": Json::string(hash),
        "details": data_segments_json(details),
      }),
    )
  }
  root.set(
    "delta",
    Json::object({
      "section_size": int_json(report.delta.section_size),
      "payload_size": int_json(report.delta.payload_size),
      "entry_metadata_size": int_json(report.delta.entry_metadata_size),
      "section_overhead_size": int_json(report.delta.section_overhead_size),
    }),
  )
  root.set(
    "groups",
    Json::array(
      report.groups.map(fn(group) {
        Json::object({
          "id": int_json(group.id),
          "sha256": Json::string(group.sha256),
          "payload_length": int_json(group.payload_length),
          "kind": Json::string(data_group_kind(group.kind)),
          "baseline_indices": Json::array(group.baseline_indices.map(int_json)),
          "current_indices": Json::array(group.current_indices.map(int_json)),
          "baseline": data_group_totals_json(group.baseline),
          "current": data_group_totals_json(group.current),
          "delta": data_group_totals_json(group.delta),
        })
      }),
    ),
  )
  Json::object(root).stringify(indent=2) + "\n"
}
