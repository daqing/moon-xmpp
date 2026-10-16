///|
async test "the four subscription requests use the right presence types" {
  online_loopback(
    port=46869,
    server=tcp => {
      let req = read_until(tcp, "type='unsubscribed'")
      assert_true(
        req.contains(
          "<presence to='bob@example.com' type='subscribe' xmlns='jabber:client'/>",
        ),
      )
      assert_true(req.contains("type='subscribed'"))
      assert_true(req.contains("type='unsubscribe'"))
      assert_true(req.contains("type='unsubscribed'"))
    },
    client_flow=conn => {
      conn.send_subscribe(to="bob@example.com")
      conn.send_subscribed(to="bob@example.com")
      conn.send_unsubscribe(to="bob@example.com")
      conn.send_unsubscribed(to="bob@example.com")
    },
  )
}

///|
async test "an inbound subscribe is surfaced and never auto-answered" {
  online_loopback(
    port=46870,
    server=tcp => {
      tcp.write(
        "<presence from='carol@example.com/p1' type='subscribe'><status>please add me</status></presence>",
      )
      // The next thing the client writes must be its own traffic, not an
      // automatic authorization reply (RFC 6121 §3.1.3).
      let req = read_until(tcp, "</message>")
      assert_false(req.contains("type='subscribed'"))
    },
    client_flow=conn => {
      let req = conn.recv_subscription()
      assert_eq(req.kind, Subscribe)
      assert_eq(req.status, Some("please add me"))
      guard req.from is Some(f) else { fail("missing from") }
      assert_eq(f.to_string(), "carol@example.com/p1")
      ignore(conn.send_chat(to="carol@example.com", body="hello"))
    },
  )
}

///|
async test "inbound subscription kinds are parsed in order" {
  online_loopback(
    port=46871,
    server=tcp => {
      tcp.write(
        "<presence from='bob@example.com' type='subscribed'/><presence from='bob@example.com' type='unsubscribe'/><presence from='bob@example.com' type='unsubscribed'/>",
      )
      ignore(read_until(tcp, "ignored"))
    },
    client_flow=conn => {
      guard conn.recv_stanza() is Subscription(a) else { fail("expected a") }
      assert_eq(a.kind, Subscribed)
      guard conn.recv_stanza() is Subscription(b) else { fail("expected b") }
      assert_eq(b.kind, Unsubscribe)
      guard conn.recv_stanza() is Subscription(c) else { fail("expected c") }
      assert_eq(c.kind, Unsubscribed)
      assert_eq(c.kind, Unsubscribed)
    },
  )
}

///|
async test "an approval is sent explicitly after an inbound request" {
  online_loopback(
    port=46872,
    server=tcp => {
      tcp.write("<presence from='bob@example.com' type='subscribe'/>")
      let req = read_until(tcp, "</presence>")
      assert_true(
        req.contains(
          "<presence to='bob@example.com' type='subscribed' xmlns='jabber:client'/>",
        ),
      )
    },
    client_flow=conn => {
      let req = conn.recv_subscription()
      assert_eq(req.kind, Subscribe)
      conn.send_subscribed(to="bob@example.com")
    },
  )
}

///|
async test "recv_presence skips subscription stanzas" {
  online_loopback(
    port=46873,
    server=tcp => {
      tcp.write(
        "<presence from='carol@example.com' type='subscribe'/><presence from='dave@example.com' type='error'/><presence from='erin@example.com' type='unavailable'/>",
      )
      ignore(read_until(tcp, "ignored"))
    },
    client_flow=conn => {
      let p = conn.recv_presence()
      assert_eq(p.presence_type, Some("error"))
      let q = conn.recv_presence()
      assert_eq(q.presence_type, Some("unavailable"))
    },
  )
}

///|
async test "recv_subscription skips non-subscription stanzas" {
  online_loopback(
    port=46879,
    server=tcp => {
      tcp.write(
        "<message from='bob@example.com' type='chat'><body>hi</body></message><presence from='carol@example.com' type='subscribe'/>",
      )
      ignore(read_until(tcp, "ignored"))
    },
    client_flow=conn => {
      let req = conn.recv_subscription()
      assert_eq(req.kind, Subscribe)
      guard req.from is Some(f) else { fail("missing from") }
      assert_eq(f.to_string(), "carol@example.com")
    },
  )
}

///|
async test "subscription management requires a bound session" {
  online_loopback(port=46874, server=_tcp => (), client_flow=conn => {
    conn.state = Connecting
    for
      send in [
        (c : Connection) => c.send_subscribe(to="bob@example.com"),
        (c : Connection) => c.send_subscribed(to="bob@example.com"),
        (c : Connection) => c.send_unsubscribe(to="bob@example.com"),
        (c : Connection) => c.send_unsubscribed(to="bob@example.com"),
      ] {
      try send(conn) catch {
        err => assert_true(err is XmppError::ProtocolViolation(detail=_))
      } noraise {
        _ => fail("expected refusal")
      }
    }
  })
}
