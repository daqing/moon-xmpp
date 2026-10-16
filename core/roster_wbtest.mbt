///|
/// Read from the fake server until `marker` has been received, and return
/// everything read so far.
async fn read_until(tcp : @socket.Tcp, marker : String) -> String {
  let mut buf = ""
  for ;; {
    match tcp.read_some() {
      None => return buf
      Some(data) => {
        buf = buf + @utf8.decode(data)
        if buf.contains(marker) {
          return buf
        }
      }
    }
  }
}

///|
async test "get_roster fetches items and caches them" {
  online_loopback(
    port=46858,
    server=tcp => {
      let req = read_until(tcp, "</iq>")
      assert_true(req.contains("type='get'"))
      assert_true(req.contains("<query xmlns='jabber:iq:roster'/>"))
      tcp.write(
        "<iq type='result' id='roster_1'><query xmlns='jabber:iq:roster'><item jid='alice@example.com' name='Alice' subscription='both' ask='subscribe'><group>Friends</group><group>Work</group></item><item jid='bob@example.com' subscription='none'/></query></iq>",
      )
    },
    client_flow=conn => {
      let items = conn.get_roster()
      assert_eq(items.length(), 2)
      assert_eq(items[0].jid.to_string(), "alice@example.com")
      assert_eq(items[0].name, Some("Alice"))
      assert_eq(items[0].subscription, SubBoth)
      assert_eq(items[0].ask, Some("subscribe"))
      assert_eq(items[0].groups, ["Friends", "Work"])
      assert_eq(items[1].jid.to_string(), "bob@example.com")
      assert_eq(items[1].name, None)
      assert_eq(items[1].subscription, SubNone)
      assert_eq(items[1].ask, None)
      assert_eq(items[1].groups, [])
      assert_eq(conn.roster().length(), 2)
    },
  )
}

///|
async test "get_roster surfaces iq errors" {
  online_loopback(
    port=46859,
    server=tcp => {
      let req = read_until(tcp, "</iq>")
      assert_true(req.contains("id='roster_1'"))
      tcp.write(
        "<iq type='error' id='roster_1'><error type='cancel'><item-not-found xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>",
      )
    },
    client_flow=conn => {
      try conn.get_roster() catch {
        err => assert_true(err is XmppError::ProtocolViolation(detail=_))
      } noraise {
        _ => fail("expected the iq error to surface")
      }
      assert_eq(conn.roster().length(), 0)
    },
  )
}

///|
async test "get_roster keeps other stanzas in order" {
  online_loopback(
    port=46860,
    server=tcp => {
      ignore(read_until(tcp, "</iq>"))
      tcp.write(
        "<message from='bob@example.com' type='chat'><body>while you wait</body></message><iq type='result' id='roster_1'><query xmlns='jabber:iq:roster'><item jid='alice@example.com' subscription='to'/></query></iq>",
      )
    },
    client_flow=conn => {
      assert_eq(conn.get_roster().length(), 1)
      guard conn.recv_stanza() is Chat(msg) else {
        fail("expected the queued chat")
      }
      assert_eq(msg.body, Some("while you wait"))
    },
  )
}

///|
async test "a roster push is acknowledged and cached" {
  online_loopback(
    port=46861,
    server=tcp => {
      tcp.write(
        "<iq type='set' id='push1'><query xmlns='jabber:iq:roster'><item jid='bob@example.com' name='Bobby' subscription='both'/></query></iq>",
      )
      let req = read_until(tcp, "id='push1'/>")
      assert_true(req.contains("<iq type='result' id='push1'/>"))
    },
    client_flow=conn => {
      guard conn.recv_stanza() is RosterPush(item) else {
        fail("expected a roster push")
      }
      assert_eq(item.name, Some("Bobby"))
      assert_eq(item.subscription, SubBoth)
      assert_eq(conn.roster().length(), 1)
      assert_eq(conn.roster()[0].jid.to_string(), "bob@example.com")
    },
  )
}

///|
async test "a removal push drops the item from the cache" {
  online_loopback(
    port=46862,
    server=tcp => {
      tcp.write(
        "<iq type='set' id='push1'><query xmlns='jabber:iq:roster'><item jid='bob@example.com' subscription='both'/></query></iq>",
      )
      ignore(read_until(tcp, "id='push1'/>"))
      tcp.write(
        "<iq type='set' id='push2'><query xmlns='jabber:iq:roster'><item jid='bob@example.com' subscription='remove'/></query></iq>",
      )
      ignore(read_until(tcp, "id='push2'/>"))
    },
    client_flow=conn => {
      guard conn.recv_stanza() is RosterPush(_) else { fail("expected add") }
      assert_eq(conn.roster().length(), 1)
      guard conn.recv_stanza() is RosterPush(removed) else {
        fail("expected remove")
      }
      assert_eq(removed.subscription, SubRemove)
      assert_eq(conn.roster().length(), 0)
    },
  )
}

///|
async test "a removal push for an unknown item leaves the cache alone" {
  online_loopback(
    port=46863,
    server=tcp => {
      tcp.write(
        "<iq type='set' id='push1'><query xmlns='jabber:iq:roster'><item jid='ghost@example.com' subscription='remove'/></query></iq>",
      )
      ignore(read_until(tcp, "id='push1'/>"))
    },
    client_flow=conn => {
      guard conn.recv_stanza() is RosterPush(_) else { fail("expected remove") }
      assert_eq(conn.roster().length(), 0)
    },
  )
}

///|
async test "set_roster_item escapes and updates the cache" {
  online_loopback(
    port=46864,
    server=tcp => {
      let req = read_until(tcp, "</iq>")
      assert_true(req.contains("id='roster_set_1'"))
      assert_true(req.contains("type='set'"))
      assert_true(
        req.contains("<item jid='carol@example.com' name='Carol &amp; Co'>"),
      )
      assert_true(req.contains("<group>Friends &amp; Family</group>"))
      tcp.write("<iq type='result' id='roster_set_1'/>")
    },
    client_flow=conn => {
      conn.set_roster_item(jid="carol@example.com", name="Carol & Co", groups=[
        "Friends & Family",
      ])
      assert_eq(conn.roster().length(), 1)
      assert_eq(conn.roster()[0].name, Some("Carol & Co"))
      assert_eq(conn.roster()[0].groups, ["Friends & Family"])
    },
  )
}

///|
async test "remove_roster_item sends a removal and drops the cache entry" {
  online_loopback(
    port=46865,
    server=tcp => {
      ignore(read_until(tcp, "</iq>"))
      tcp.write("<iq type='result' id='roster_set_1'/>")
      let req = read_until(tcp, "</iq>")
      assert_true(req.contains("id='roster_set_2'"))
      assert_true(req.contains("subscription='remove'"))
      tcp.write("<iq type='result' id='roster_set_2'/>")
    },
    client_flow=conn => {
      conn.set_roster_item(jid="carol@example.com", name="Carol")
      assert_eq(conn.roster().length(), 1)
      conn.remove_roster_item(jid="carol@example.com")
      assert_eq(conn.roster().length(), 0)
    },
  )
}

///|
async test "roster items tolerate unknown attributes and children" {
  online_loopback(
    port=46866,
    server=tcp => {
      ignore(read_until(tcp, "</iq>"))
      tcp.write(
        "<iq type='result' id='roster_1'><query xmlns='jabber:iq:roster'><item jid='dave@example.com' subscription='to' approved='true'><x xmlns='urn:example:extras'/><group>G</group></item></query></iq>",
      )
    },
    client_flow=conn => {
      let items = conn.get_roster()
      assert_eq(items.length(), 1)
      assert_eq(items[0].jid.to_string(), "dave@example.com")
      assert_eq(items[0].subscription, SubTo)
      assert_eq(items[0].groups, ["G"])
    },
  )
}

///|
async test "roster items without a subscription attribute default to none" {
  online_loopback(
    port=46875,
    server=tcp => {
      ignore(read_until(tcp, "</iq>"))
      tcp.write(
        "<iq type='result' id='roster_1'><query xmlns='jabber:iq:roster'><x xmlns='urn:example:extras'/><item jid='alice@example.com' subscription='from'/><item jid='bob@example.com'/></query></iq>",
      )
    },
    client_flow=conn => {
      let items = conn.get_roster()
      assert_eq(items.length(), 2)
      assert_eq(items[0].subscription, SubFrom)
      assert_eq(items[0].groups, [])
      assert_eq(items[1].subscription, SubNone)
    },
  )
}

///|
async test "non-roster iqs stay out of band" {
  online_loopback(
    port=46876,
    server=tcp => {
      tcp.write(
        "<iq type='set' id='a'><query xmlns='urn:example:other'/></iq><iq type='get' id='b'/><presence from='x@example.com'/>",
      )
      ignore(read_until(tcp, "ignored"))
    },
    client_flow=conn => {
      assert_eq(conn.recv_stanza(), Other)
      assert_eq(conn.recv_stanza(), Other)
      guard conn.recv_stanza() is Presence(_) else { fail("expected presence") }
    },
  )
}

///|
async test "a roster push without items is ignored" {
  online_loopback(
    port=46877,
    server=tcp => {
      tcp.write(
        "<iq type='set' id='p1'><query xmlns='jabber:iq:roster'/></iq><presence from='x@example.com' type='unavailable'/>",
      )
      ignore(read_until(tcp, "ignored"))
    },
    client_flow=conn => {
      assert_eq(conn.recv_stanza(), Other)
      guard conn.recv_stanza() is Presence(p) else { fail("expected presence") }
      assert_eq(p.presence_type, Some("unavailable"))
    },
  )
}

///|
async test "a push replaces its item and keeps the others" {
  online_loopback(
    port=46878,
    server=tcp => {
      ignore(read_until(tcp, "</iq>"))
      tcp.write(
        "<iq type='result' id='roster_1'><query xmlns='jabber:iq:roster'><item jid='alice@example.com' subscription='to'/><item jid='bob@example.com' subscription='none'/></query></iq><iq type='set' id='p1'><query xmlns='jabber:iq:roster'><item jid='alice@example.com' subscription='both'/></query></iq>",
      )
      ignore(read_until(tcp, "id='p1'/>"))
    },
    client_flow=conn => {
      assert_eq(conn.get_roster().length(), 2)
      guard conn.recv_stanza() is RosterPush(updated) else {
        fail("expected the push")
      }
      assert_eq(updated.subscription, SubBoth)
      assert_eq(conn.roster().length(), 2)
      assert_eq(conn.roster()[0].jid.to_string(), "alice@example.com")
      assert_eq(conn.roster()[0].subscription, SubBoth)
      assert_eq(conn.roster()[1].jid.to_string(), "bob@example.com")
    },
  )
}

///|
async test "an id-less iq while awaiting a reply is not mistaken for it" {
  online_loopback(
    port=46880,
    server=tcp => {
      ignore(read_until(tcp, "</iq>"))
      tcp.write(
        "<iq type='result'/><iq type='result' id='roster_1'><query xmlns='jabber:iq:roster'><item jid='alice@example.com' subscription='both'/></query></iq>",
      )
    },
    client_flow=conn => assert_eq(conn.get_roster().length(), 1),
  )
}

///|
async test "roster management requires a bound session" {
  online_loopback(port=46867, server=_tcp => (), client_flow=conn => {
    conn.state = Connecting
    try conn.get_roster() catch {
      err => assert_true(err is XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected refusal")
    }
    try conn.set_roster_item(jid="bob@example.com") catch {
      err => assert_true(err is XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected refusal")
    }
  })
}

///|
async test "an invalid roster jid is rejected before sending" {
  online_loopback(port=46868, server=_tcp => (), client_flow=conn => {
    try conn.set_roster_item(jid="not a jid") catch {
      err => assert_true(err is XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected refusal")
    }
    try conn.remove_roster_item(jid="") catch {
      err => assert_true(err is XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected refusal")
    }
  })
}
