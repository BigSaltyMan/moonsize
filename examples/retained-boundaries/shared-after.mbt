///|
#inline(never)
fn boundary_shared(n : Int) -> Int {
  let mut score = 0
  for i in 0..<(n + 3) {
    score = score + i * (i + 7)
  }
  score
}

///|
#inline(never)
fn boundary_target(n : Int) -> Int {
  boundary_shared(n) + 23
}

///|
fn main {
  for n in 0..<4 {
    println(boundary_shared(n))
  }
}
