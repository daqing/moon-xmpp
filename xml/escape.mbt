///|
/// Escape a string for use as XML character data.
pub fn escape_text(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      c => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Escape a string for use inside a double-quoted XML attribute value.
pub fn escape_attr(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    match c {
      '&' => buf.write_string("&amp;")
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '"' => buf.write_string("&quot;")
      '\'' => buf.write_string("&apos;")
      c => buf.write_char(c)
    }
  }
  buf.to_string()
}
