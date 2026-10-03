// The source `fib.wasm` was built from:
//
//   moon build --target wasm        (MoonBit 0.1.20260920, debug)
//
// Kept here so the checked-in report can be regenerated and compared.

fn fib(n : Int) -> Int {
  if n < 2 {
    n
  } else {
    fib(n - 1) + fib(n - 2)
  }
}

fn classify(n : Int) -> String {
  if n % 2 == 0 {
    "even"
  } else {
    "odd"
  }
}

fn main {
  let mut total = 0
  for i = 0; i < 12; i = i + 1 {
    total = total + fib(i)
  }
  println(classify(total) + " " + total.to_string())
}
