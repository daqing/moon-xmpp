///|
/// Apply the RFC 8264 width map: fullwidth forms to ASCII, and code points
/// mapped to nothing are dropped.
fn width_map(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    let n = c.to_int()
    if n >= 0xff01 && n <= 0xff5e {
      match (n - 0xfee0).to_char() {
        Some(mapped) => buf.write_char(mapped)
        None => buf.write_char(c)
      }
    } else if n == 0xad || (n >= 0x200b && n <= 0x200d) || n == 0xfeff {
      ()
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Apply the RFC 8264 case map (Unicode full lowercase, ASCII subset in
/// effect for the ranges the validator accepts).
fn case_map(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    buf.write_string(@unicode.to_lowercase(c))
  }
  buf.to_string()
}
