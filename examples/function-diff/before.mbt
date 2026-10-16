///|
fn classify(n : Int) -> String {
  if n % 2 == 0 {
    "even"
  } else {
    "odd"
  }
}

///|
fn main {
  for n in 0..<8 {
    println(classify(n))
  }
}
