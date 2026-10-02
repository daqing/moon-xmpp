///|
test "parse stanza error" {
  let el = @xml.parse_element(
    "<error type='modify'><bad-request xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/><text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'>bad</text></error>",
  )
  let e = StanzaError::parse(el)
  assert_true(e.error_type == StanzaErrorType::Modify)
  assert_true(e.condition == StanzaErrorCondition::BadRequest)
  assert_eq(e.text, Some("bad"))
}

///|
test "parse stanza error redirect and app condition" {
  let el = @xml.parse_element(
    "<error type='cancel'><redirect xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'>xmpp:other.example.com</redirect></error>",
  )
  let e = StanzaError::parse(el)
  assert_true(
    e.condition == StanzaErrorCondition::Redirect(uri="xmpp:other.example.com"),
  )
  let el2 = @xml.parse_element(
    "<error type='wait'><app-condition xmlns='urn:example'/></error>",
  )
  let e2 = StanzaError::parse(el2)
  assert_true(e2.error_type == StanzaErrorType::Wait)
  assert_true(e2.condition == StanzaErrorCondition::Unknown("app-condition"))
}

///|
test "stanza error without type raises" {
  let el = @xml.parse_element("<error><bad-request/></error>")
  try StanzaError::parse(el) catch {
    err => assert_true(err is XmppError::ProtocolViolation(detail=_))
  } noraise {
    _ => fail("expected error")
  }
}
