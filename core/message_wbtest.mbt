///|
/// Run `client_flow` on a session fast-forwarded to Online against a fake
/// server that streams the given outbound bytes and returns what it
/// observed from the client.
async fn online_loopback(
  port~ : Int,
  server~ : async (@socket.Tcp) -> Unit,
  client_flow~ : async (Connection) -> Unit,
) -> Unit {
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ => fail("invalid test addr")
  }
  let srv = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = srv.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='m1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      server(tcp)
      tcp.close()
    })
    let conn = connect(host="127.0.0.1", port~)
    ignore(conn.open_stream(domain="example.com"))
    conn.state = Online
    client_flow(conn)
    conn.close()
  })
}

///|
async test "send_chat wire format and escaping" {
  online_loopback(
    port=46846,
    server=tcp => {
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => return
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("</message>") {
              break
            }
          }
        }
      }
      assert_true(
        buf.contains("<message type='chat' id='msg_1' to='bob@example.com'"),
      )
      assert_true(buf.contains("<body>a&lt;b&gt;&amp;c</body>"))
    },
    client_flow=conn => {
      let id = conn.send_chat(to="bob@example.com", body="a<b>&c")
      assert_eq(id, "msg_1")
      let id2 = conn.send_chat(to="bob@example.com", body="second")
      assert_eq(id2, "msg_2")
    },
  )
}

///|
async test "send_chat requires a bound session" {
  online_loopback(port=46847, server=_tcp => (), client_flow=conn => {
    conn.state = Connecting
    try conn.send_chat(to="bob@example.com", body="hi") catch {
      err => assert_true(err is XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected refusal")
    }
  })
}

///|
async test "recv_stanza dispatches chat, presence, and other" {
  online_loopback(
    port=46848,
    server=tcp => {
      tcp.write(
        "<iq type='result' id='x'/><message from='bob@example.com' id='a1' type='chat'><body>hello</body></message><presence from='alice@example.com/home'/><message from='bob@example.com' type='chat'><composing xmlns='http://jabber.org/protocol/chatstates'/></message>",
      )
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => return
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("</message>") {
              return
            }
          }
        }
      }
    },
    client_flow=conn => {
      assert_eq(conn.recv_stanza(), Other)
      guard conn.recv_stanza() is Chat(msg) else { fail("expected chat") }
      assert_eq(msg.id, Some("a1"))
      assert_eq(msg.body, Some("hello"))
      guard msg.from is Some(f) else { fail("missing from") }
      assert_eq(f.to_string(), "bob@example.com")
      guard conn.recv_stanza() is Presence(p) else { fail("expected presence") }
      guard p.from is Some(pf) else { fail("missing presence from") }
      assert_eq(pf.to_string(), "alice@example.com/home")
      // chat-state notification without a body: parsed, body stays None
      guard conn.recv_stanza() is Chat(typing) else { fail("expected chat") }
      assert_eq(typing.body, None)
    },
  )
}
