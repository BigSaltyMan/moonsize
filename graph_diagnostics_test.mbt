///|
/// Two () -> () functions. A declarative element segment declares function 1
/// for ref.func; the exported root takes its reference and calls it via type 0.
fn reference_call_fixture(tail? : Bool = false) -> Bytes {
  b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00" +
  b"\x03\x03\x02\x00\x00\x07\x07\x01\x03run\x00\x00" +
  b"\x09\x05\x01\x03\x00\x01\x01\x0a\x0b\x02\x06\x00\xd2\x01" +
  (if tail { b"\x15" } else { b"\x14" }) +
  b"\x00\x0b\x02\x00\x0b"
}

///|
fn reference_analysis(data : Bytes) -> @moonsize.Analysis raise {
  let parsed = match @moonsize.parse_module(data) {
    Ok(parsed) => parsed
    Err(error) => fail(@moonsize.describe_error(error))
  }
  match @moonsize.analyze(data, parsed) {
    Ok(analysis) => analysis
    Err(error) => fail(@moonsize.describe_error(error))
  }
}

///|
test "public analysis refuses completeness for both reference call opcodes" {
  for tail in [false, true] {
    let analysis = reference_analysis(reference_call_fixture(tail~))
    assert_true(!analysis.graph_complete)
    assert_eq(analysis.unresolved_count, 0)
    assert_eq(analysis.graph.unresolved_indirect.length(), 0)
    assert_eq(analysis.graph.diagnostics.length(), 1)
    let diagnostic = analysis.graph.diagnostics[0]
    match diagnostic.kind {
      UnmodeledReferenceCall => ()
      _ => fail("expected reference-call gap")
    }
    assert_eq(diagnostic.caller, 0)
    assert_eq(diagnostic.offset, 42)
    assert_eq(
      diagnostic.opcode.name(),
      if tail {
        "return_call_ref"
      } else {
        "call_ref"
      },
    )
    assert_eq(diagnostic.type_index, Some(0))
    assert_eq(diagnostic.table_index, None)
    assert_true(!@moonsize.is_graph_complete(analysis.graph))
    // ref.func contributes a reference edge, but the call adds no guessed edge.
    assert_eq(analysis.graph.edges.length(), 1)
    match analysis.graph.edges[0].kind {
      Reference => ()
      _ => fail("expected only the ref.func edge")
    }
    for
      report in [
        @moonsize.render_dead_code(analysis, 10),
        @moonsize.render_retained(analysis, 10),
      ] {
      assert_true(report.contains("graph incomplete: 1 analysis gap"))
      assert_true(
        report.contains(
          "call_ref: reference-call target analysis is not implemented.",
        ),
      )
    }
  }
}

///|
test "public scan_calls includes reference calls but excludes ref.func" {
  for tail in [false, true] {
    let data = reference_call_fixture(tail~)
    let sites = match @moonsize.scan_calls(data, 39, 6) {
      Ok(sites) => sites
      Err(error) => fail(@moonsize.describe_error(error))
    }
    assert_eq(sites.length(), 1)
    assert_eq(sites[0].type_index, Some(0))
    assert_eq(sites[0].offset, 42)
    match sites[0].kind {
      Reference => ()
      _ => fail("expected Reference call kind")
    }
  }
}
