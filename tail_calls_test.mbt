///|
/// Public-interface regression: the original 39-byte module, with no patched graph.
fn direct_tail_fixture() -> Bytes {
  b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00" +
  b"\x03\x03\x02\x00\x00\x07\x07\x01\x03run\x00\x00" +
  b"\x0a\x09\x02\x04\x00\x12\x01\x0b\x02\x00\x0b"
}

///|
fn public_tail_analysis(data : Bytes) -> @moonsize.Analysis raise {
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
/// Compare the public scanner with analysis for every body in a fixture.
fn assert_public_tail_scans(analysis : @moonsize.Analysis) -> Unit raise {
  let mut direct = 0
  let mut indirect = 0
  for stat in analysis.stats {
    let start = stat.offset + stat.total_size - stat.body_size
    let sites = match
      @moonsize.scan_calls(analysis.data, start, stat.body_size) {
      Ok(sites) => sites
      Err(error) => fail(@moonsize.describe_error(error))
    }
    for site in sites {
      match site.kind {
        Direct(target) => {
          direct = direct + 1
          let matching = analysis.graph.edges.filter(edge => {
            edge.caller == stat.index &&
            edge.callee == target &&
            edge.offset == site.offset
          })
          assert_eq(matching.length(), 1)
          match matching[0].kind {
            Direct => ()
            _ => fail("expected Direct edge")
          }
          assert_eq(site.type_index, None)
        }
        Indirect(table) => {
          indirect = indirect + 1
          let matching = analysis.graph.indirect_sites.filter(found => {
            found.caller == stat.index && found.offset == site.offset
          })
          assert_eq(matching.length(), 1)
          assert_eq(matching[0].table_index, table)
          assert_eq(Some(matching[0].type_index), site.type_index)
        }
        Reference => fail("tail fixtures contain no reference calls")
      }
    }
  }
  assert_eq(direct + indirect, 1)
  assert_eq(analysis.graph.edges.length(), direct)
  assert_eq(analysis.graph.indirect_sites.length(), indirect)
}

///|
test "public analysis keeps the direct tail target live and retained" {
  let data = direct_tail_fixture()
  assert_eq(data.length(), 39)
  let analysis = public_tail_analysis(data)
  assert_true(analysis.graph_complete)
  assert_eq(analysis.unresolved_count, 0)
  assert_eq(analysis.stats.length(), 2)
  assert_true(
    analysis.stats.all(stat => analysis.reachable.contains(stat.index)),
  )
  assert_eq(analysis.stats[0].total_size, 5)
  assert_eq(analysis.stats[1].total_size, 3)
  let root = analysis.retained.filter(entry => entry.index == 0)
  assert_eq(root.length(), 1)
  assert_eq(root[0].retained, 8)
  assert_eq(root[0].retained_functions, 1)
  assert_public_tail_scans(analysis)
}

///|
test "public analysis marks an unresolved indirect tail call incomplete" {
  let data = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00" +
    b"\x03\x02\x01\x00\x04\x04\x01\x70\x00\x01" +
    b"\x07\x07\x01\x03run\x00\x00\x0a\x09\x01\x07\x00\x41\x00\x13\x00\x00\x0b"
  let analysis = public_tail_analysis(data)
  assert_true(!analysis.graph_complete)
  assert_eq(analysis.unresolved_count, 1)
  assert_eq(analysis.graph.unresolved_indirect.length(), 1)
  assert_eq(analysis.graph.unresolved_indirect[0].candidates.length(), 0)
  assert_public_tail_scans(analysis)
}
