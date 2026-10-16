///|
fn classify(n : Int) -> String {
  if n < 0 {
    "negative"
  } else if n == 0 {
    "zero"
  } else if n % 2 == 0 {
    "positive even"
  } else {
    "positive odd"
  }
}

///|
fn weighted_score(n : Int) -> Int {
  let mut score = 0
  for i = 0; i <= n; i = i + 1 {
    score = score + i * (i + 3)
  }
  score
}

///|
fn main {
  for n in 0..<8 {
    println(classify(n) + ": " + weighted_score(n).to_string())
  }
}
