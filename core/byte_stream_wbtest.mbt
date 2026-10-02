///|
test "complete_utf8_prefix" {
  assert_eq(complete_utf8_prefix([]), 0)
  assert_eq(complete_utf8_prefix([b'a', b'b']), 2)
  assert_eq(complete_utf8_prefix([b'a', b'\xe4', b'\xb8']), 1)
  assert_eq(complete_utf8_prefix([b'\xe4', b'\xb8', b'\xad']), 3)
  assert_eq(complete_utf8_prefix([b'\xf0', b'\x9f']), 0)
}

///|
test "push_bytes splits utf-8 across chunk boundary" {
  let bs = ByteStream::new()
  ignore(bs.push_bytes(b"<stream:stream>"))
  let f1 = bs.push_bytes(b"<message><body>\xe4\xb8")
  assert_eq(f1.length(), 0)
  let f2 = bs.push_bytes(b"\xad!</body></message>")
  assert_eq(f2.length(), 1)
  assert_true(
    f2[0] is @xml.Frame::Stanza("<message><body>中!</body></message>"),
  )
}

///|
test "push_bytes rejects invalid utf-8" {
  let bs = ByteStream::new()
  ignore(bs.push_bytes(b"<stream:stream>"))
  try bs.push_bytes(b"<message>\xff") catch {
    err => assert_true(err is @xml.XmlError::Malformed(detail=_))
  } noraise {
    _ => fail("expected error")
  }
}
