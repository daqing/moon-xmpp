///|
/// RFC 6120 §8.4: unknown top-level stanzas are ignored, unknown children
/// of stanzas are ignored, and none of them may crash the session. These
/// tests pin that behavior for the reception path.
async fn unknown_content_test(
  port~ : Int,
  inbound~ : String,
  assert_flow~ : async (Connection) -> Unit,
) -> Unit {
  online_loopback(
    port~,
    server=tcp => {
      tcp.write(inbound)
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => return
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("</message>") || buf.contains("</presence>") {
              return
            }
          }
        }
      }
    },
    client_flow=assert_flow,
  )
}

///|
async test "unknown top-level element is ignored as Other" {
  unknown_content_test(
    port=46849,
    inbound="<whatsit xmlns='urn:example:weird'><data>42</data></whatsit>",
    assert_flow=conn => assert_eq(conn.recv_stanza(), Other),
  )
}

///|
async test "message body with entities is decoded" {
  unknown_content_test(
    port=46850,
    inbound="<message from='bob@example.com' type='chat'><body>a&amp;b &lt;tag&gt; &#65;</body></message>",
    assert_flow=conn => {
      guard conn.recv_stanza() is Chat(msg) else { fail("expected chat") }
      assert_eq(msg.body, Some("a&b <tag> A"))
    },
  )
}

///|
async test "unknown children do not hide the body" {
  unknown_content_test(
    port=46851,
    inbound="<message from='bob@example.com' type='chat' testattr='x'><removed xmlns='urn:example:gone'/><active xmlns='http://jabber.org/protocol/chatstates'/><body>still here</body><delay xmlns='urn:xmpp:delay' stamp='2020'/></message>",
    assert_flow=conn => {
      guard conn.recv_stanza() is Chat(msg) else { fail("expected chat") }
      assert_eq(msg.body, Some("still here"))
    },
  )
}

///|
async test "unknown children in presence are ignored" {
  unknown_content_test(
    port=46852,
    inbound="<presence from='alice@example.com'><x xmlns='vcard-temp:q'/><status>around</status></presence>",
    assert_flow=conn => {
      guard conn.recv_stanza() is Presence(p) else { fail("expected presence") }
      assert_eq(p.status, Some("around"))
      assert_eq(p.presence_type, None)
    },
  )
}
