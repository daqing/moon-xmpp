///|
test "build stream header" {
  assert_eq(
    build_stream_header("example.com"),
    "<?xml version='1.0'?><stream:stream xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams' to='example.com' version='1.0'>",
  )
}

///|
test "parse stream header" {
  let h = parse_stream_header(
    "<stream:stream from='example.com' id='abc123' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'",
  )
  assert_eq(h.id, "abc123")
  assert_eq(h.from, Some("example.com"))
  assert_eq(h.version, "1.0")
}

///|
test "parse stream header rejections" {
  try
    parse_stream_header(
      "<stream:stream version='1.0' xmlns:stream='http://etherx.jabber.org/streams'",
    )
  catch {
    err => assert_true(err is XmppError::ProtocolViolation(detail=_))
  } noraise {
    _ => fail("expected error for missing id")
  }
  try
    parse_stream_header(
      "<stream:stream id='x' version='0.9' xmlns:stream='http://etherx.jabber.org/streams'",
    )
  catch {
    err => assert_true(err is XmppError::ProtocolViolation(detail=_))
  } noraise {
    _ => fail("expected error for bad version")
  }
  try
    parse_stream_header(
      "<stream:stream id='x' version='1.0' xmlns:stream='http://wrong.example/'",
    )
  catch {
    err => assert_true(err is XmppError::ProtocolViolation(detail=_))
  } noraise {
    _ => fail("expected error for wrong namespace")
  }
  try parse_stream_header("<stream:stream id='x' version='1.0'") catch {
    err => assert_true(err is XmppError::ProtocolViolation(detail=_))
  } noraise {
    _ => fail("expected error for missing namespace")
  }
}
