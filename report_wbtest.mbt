///|
/// Four functions across three packages, with sizes chosen so the ranking is
/// not the same as the index order and each package total is distinct.
fn sample_stats() -> Array[FunctionStat] {
  [
    {
      index: 1,
      name: "demo::sample::src::fib",
      module_name: "demo::sample::src",
      body_size: 300,
      total_size: 302,
      offset: 0,
    },
    {
      index: 2,
      name: "moonbit.println",
      module_name: "moonbit",
      body_size: 80,
      total_size: 82,
      offset: 0,
    },
    {
      index: 3,
      name: "tlsf/insertBlock",
      module_name: "tlsf",
      body_size: 100,
      total_size: 102,
      offset: 0,
    },
    {
      index: 4,
      name: "tlsf/removeBlock",
      module_name: "tlsf",
      body_size: 40,
      total_size: 42,
      offset: 0,
    },
  ]
}

///|
test "ranks by size, not by index" {
  let ranked = rank_functions(sample_stats())
  inspect(
    ranked[0].index,
    content=(
      #|1
    ),
  )
  inspect(
    ranked[1].index,
    content=(
      #|3
    ),
  )
  inspect(
    ranked[2].index,
    content=(
      #|2
    ),
  )
  inspect(
    ranked[3].index,
    content=(
      #|4
    ),
  )
}

///|
test "renders the top table with aligned columns" {
  inspect(
    render_top_functions(sample_stats(), 1000, 2),
    content=(
      #|Top 2 of 4 functions by size
      #|
      #|    #  INDEX        BODY       TOTAL    SHARE  FUNCTION
      #|    1      1         300         302    30.2%  demo::sample::src::fib
      #|    2      3         100         102    10.2%  tlsf/insertBlock
      #|
      #|  these 2 hold 404 bytes (40.4% of file)
    ),
  )
}

///|
test "renders the whole table when --top exceeds what exists" {
  inspect(
    render_top_functions(sample_stats(), 1000, 99),
    content=(
      #|Top 4 of 4 functions by size
      #|
      #|    #  INDEX        BODY       TOTAL    SHARE  FUNCTION
      #|    1      1         300         302    30.2%  demo::sample::src::fib
      #|    2      3         100         102    10.2%  tlsf/insertBlock
      #|    3      2          80          82     8.2%  moonbit.println
      #|    4      4          40          42     4.2%  tlsf/removeBlock
      #|
      #|  these 4 hold 528 bytes (52.8% of file)
    ),
  )
}

///|
test "reports an empty ranking without a table" {
  inspect(
    render_top_functions([], 1000, 10),
    content=(
      #|Top 0 of 0 functions by size
      #|
      #|  no functions in this binary
    ),
  )
}

///|
test "reports a --top of zero without a table" {
  inspect(
    render_top_functions(sample_stats(), 1000, 0),
    content=(
      #|Top 0 of 4 functions by size
      #|
      #|  --top 0 requested, nothing to rank
    ),
  )
}

///|
test "rolls functions up by package" {
  inspect(
    render_module_summary(sample_stats(), 1000),
    content=(
      #|Size by module
      #|
      #|  MODULE             FUNCS        BODY       TOTAL    SHARE
      #|  demo::sample::src      1         300         302    30.2%
      #|  tlsf                   2         140         144    14.4%
      #|  moonbit                1          80          82     8.2%
      #|
      #|  3 modules, 4 functions, 528 bytes (52.8% of file)
    ),
  )
}

///|
test "rolls up an empty binary without a table" {
  inspect(
    render_module_summary([], 1000),
    content=(
      #|Size by module
      #|
      #|  no functions in this binary
    ),
  )
}

///|
test "collects named functions from a real name section" {
  let data = named_module()
  match parse_module(data) {
    Ok(parsed) =>
      match collect_function_stats(parsed, data) {
        Ok(stats) => {
          inspect(
            stats.length(),
            content=(
              #|2
            ),
          )
          inspect(
            stats[0].index,
            content=(
              #|1
            ),
          )
          inspect(
            stats[0].name,
            content=(
              #|moonbit.println
            ),
          )
          inspect(
            stats[0].module_name,
            content=(
              #|moonbit
            ),
          )
          inspect(
            stats[0].body_size,
            content=(
              #|2
            ),
          )
          inspect(
            stats[0].total_size,
            content=(
              #|3
            ),
          )
          inspect(
            stats[1].index,
            content=(
              #|2
            ),
          )
          inspect(
            stats[1].name,
            content=(
              #|demo::sample::src::fib
            ),
          )
          inspect(
            stats[1].module_name,
            content=(
              #|demo::sample::src
            ),
          )
        }
        Err(error) => fail(decode_failure(error))
      }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "labels functions the binary never names" {
  let data = big_body_module()
  match parse_module(data) {
    Ok(parsed) =>
      match collect_function_stats(parsed, data) {
        Ok(stats) => {
          inspect(
            stats.length(),
            content=(
              #|1
            ),
          )
          inspect(
            stats[0].name,
            content=(
              #|(unnamed)
            ),
          )
          inspect(
            stats[0].module_name,
            content=(
              #|(unnamed)
            ),
          )
          inspect(
            stats[0].body_size,
            content=(
              #|200
            ),
          )
        }
        Err(error) => fail(decode_failure(error))
      }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "reports one unnamed function for a module with no name section" {
  // `minimal_module` has a code section of one two-byte body and no `name`
  // section, so the size is known and the name is not.
  let data = minimal_module()
  match parse_module(data) {
    Ok(parsed) =>
      match collect_function_stats(parsed, data) {
        Ok(stats) => {
          inspect(
            stats.length(),
            content=(
              #|1
            ),
          )
          inspect(
            stats[0].name,
            content=(
              #|(unnamed)
            ),
          )
          inspect(
            stats[0].module_name,
            content=(
              #|(unnamed)
            ),
          )
          inspect(
            stats[0].total_size,
            content=(
              #|3
            ),
          )
        }
        Err(error) => fail(decode_failure(error))
      }
    Err(error) => fail(decode_failure(error))
  }
}

///|
test "reports no functions for a module with no code section" {
  // Preamble plus an empty type section, which is a legal module.
  let data = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00"
  match parse_module(data) {
    Ok(parsed) =>
      match collect_function_stats(parsed, data) {
        Ok(stats) =>
          inspect(
            stats.length(),
            content=(
              #|0
            ),
          )
        Err(error) => fail(decode_failure(error))
      }
    Err(error) => fail(decode_failure(error))
  }
}
