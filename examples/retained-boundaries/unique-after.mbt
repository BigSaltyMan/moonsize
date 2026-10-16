///|
#inline(never)
fn boundary_leaf(n : Int) -> String {
  if n % 2 == 0 {
    "Optional report: even numbers include an explanation stored in the data segment."
  } else {
    "Optional report: odd numbers include another explanation stored in the data segment."
  }
}

///|
#inline(never)
fn boundary_target(n : Int) -> String {
  boundary_leaf(n) + " [optional feature]"
}

///|
fn main {
  for n in 0..<4 {
    println("base: " + n.to_string())
  }
}
