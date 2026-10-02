///|
test "frames root and stanza" {
  let f = @xml.Framer::new()
  let frames = f.push(
    "<stream:stream to='example.com' version='1.0'><message to='a@b'><body>hi</body></message>",
  )
  assert_eq(frames.length(), 2)
  assert_true(
    frames[0]
    is @xml.Frame::Root("<stream:stream to='example.com' version='1.0'>"),
  )
  assert_true(
    frames[1]
    is @xml.Frame::Stanza("<message to='a@b'><body>hi</body></message>"),
  )
}

///|
test "handles chunks split mid-tag" {
  let f = @xml.Framer::new()
  let f1 = f.push(
    "<stream:stream xmlns:stream='http://etherx.jabber.org/streams'",
  )
  assert_eq(f1.length(), 0)
  let f2 = f.push("><message body='a>b'><body>1</bod")
  assert_eq(f2.length(), 1)
  assert_true(
    f2[0]
    is @xml.Frame::Root(
      "<stream:stream xmlns:stream='http://etherx.jabber.org/streams'>"
    ),
  )
  let f3 = f.push("y></message>")
  assert_eq(f3.length(), 1)
  assert_true(
    f3[0] is @xml.Frame::Stanza("<message body='a>b'><body>1</body></message>"),
  )
}

///|
test "cdata and comments survive inside stanzas" {
  let f = @xml.Framer::new()
  ignore(f.push("<stream:stream>"))
  let frames = f.push("<message><![CDATA[<notag>&]]></message>")
  assert_true(
    frames[0] is @xml.Frame::Stanza("<message><![CDATA[<notag>&]]></message>"),
  )
  let keepalive = f.push("<!-- keepalive -->")
  assert_eq(keepalive.length(), 0)
  let with_comment = f.push("<message>x<!-- c -->y</message>")
  assert_true(
    with_comment[0] is @xml.Frame::Stanza("<message>x<!-- c -->y</message>"),
  )
}

///|
test "stream end and restart" {
  let f = @xml.Framer::new()
  ignore(f.push("<stream:stream>"))
  let frames = f.push("</stream:stream>")
  assert_true(frames[0] is @xml.Frame::StreamEnd)
  let restarted = f.push("<stream:stream>")
  assert_true(restarted[0] is @xml.Frame::Root("<stream:stream>"))
}

///|
test "mismatched tags raise" {
  let f = @xml.Framer::new()
  ignore(f.push("<stream:stream>"))
  try f.push("<message></mesage>") catch {
    err => assert_true(err is @xml.XmlError::Malformed(detail=_))
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "inter-stanza whitespace and self-closing stanzas" {
  let f = @xml.Framer::new()
  ignore(f.push("<stream:stream>"))
  ignore(f.push("<message><body>a</body></message>"))
  let frames = f.push("\n  <presence/>")
  assert_eq(frames.length(), 1)
  assert_true(frames[0] is @xml.Frame::Stanza("<presence/>"))
}

///|
test "prolog is skipped" {
  let f = @xml.Framer::new()
  let frames = f.push("<?xml version='1.0'?><stream:stream>")
  assert_eq(frames.length(), 1)
  assert_true(frames[0] is @xml.Frame::Root("<stream:stream>"))
}

///|
test "self-closing tag with attributes" {
  let f = @xml.Framer::new()
  ignore(f.push("<stream:stream>"))
  let frames = f.push(
    "<stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
  )
  assert_eq(frames.length(), 1)
  assert_true(
    frames[0]
    is @xml.Frame::Stanza(
      "<stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>"
    ),
  )
}
