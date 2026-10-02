///|
test "parse features" {
  let el = @xml.parse_element(
    "<stream:features><starttls xmlns='urn:ietf:params:xml:ns:xmpp-starttls'/><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism><mechanism>SCRAM-SHA-1</mechanism></mechanisms><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/><ver xmlns='urn:xmpp:features:ver-0'/></stream:features>",
  )
  let f = parse_features(el)
  assert_true(f.starttls)
  assert_false(f.starttls_required)
  assert_eq(f.mechanisms, ["PLAIN", "SCRAM-SHA-1"])
  assert_true(f.bind)
}

///|
test "parse features with required starttls" {
  let el = @xml.parse_element(
    "<stream:features><starttls><required/></starttls></stream:features>",
  )
  let f = parse_features(el)
  assert_true(f.starttls)
  assert_true(f.starttls_required)
  assert_eq(f.mechanisms, [])
  assert_false(f.bind)
}

///|
test "parse empty features" {
  let el = @xml.parse_element("<stream:features/>")
  let f = parse_features(el)
  assert_false(f.starttls)
  assert_false(f.starttls_required)
  assert_eq(f.mechanisms, [])
  assert_false(f.bind)
}
