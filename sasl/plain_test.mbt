///|
test "plain payload" {
  let payload = @sasl.plain(authcid="user@example.com", password="secret")
  assert_eq(@base64.decode(payload), b"\x00user@example.com\x00secret")
}

///|
test "plain payload with authzid" {
  let payload = @sasl.plain(
    authcid="user",
    password="p",
    authzid="admin@example.com",
  )
  assert_eq(@base64.decode(payload), b"admin@example.com\x00user\x00p")
}

///|
test "plain rejects nul" {
  try @sasl.plain(authcid="us\u{0}er", password="p") catch {
    err => assert_true(err is @sasl.SaslError::InvalidState(detail=_))
  } noraise {
    _ => fail("expected error")
  }
}
