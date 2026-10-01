///|
test "parse stanza element" {
  let el = @xml.parse_element(
    "<message to='a@b' type='chat'><body>hi</body></message>",
  )
  assert_eq(el.name, "message")
  assert_eq(el.get_attribute("type"), Some("chat"))
  let mut body : @XMLParser.XMLElement? = None
  for child in el.get_children() {
    guard child is @XMLParser.XMLChildren::Element(e) else { continue }
    if e.name is "body" {
      body = Some(e)
      break
    }
  }
  guard body is Some(body_el) else { fail("expected body element") }
  assert_eq(body_el.get_text(), "hi")
}

///|
test "parse prefixed names keep their prefix" {
  let el = @xml.parse_element(
    "<stream:features><mechanisms/></stream:features>",
  )
  assert_eq(el.name, "stream:features")
}

///|
test "parse failure raises" {
  try @xml.parse_element("<message><body>") catch {
    err => assert_true(err is @xml.XmlError::Malformed(detail=_))
  } noraise {
    _ => fail("expected error")
  }
}
