///|
/// Run `client_flow` against a fake server that has a bound session and
/// echoes nothing on its own. White-box: the session is fast-forwarded to
/// Bound before the client flow runs.
async fn presence_loopback(
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
        "<?xml version='1.0'?><stream:stream from='example.com' id='pr1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      server(tcp)
      tcp.close()
    })
    let conn = connect(host="127.0.0.1", port~)
    ignore(conn.open_stream(domain="example.com"))
    conn.state = Bound
    client_flow(conn)
    conn.close()
  })
}

///|
async test "initial presence is sent and goes online" {
  presence_loopback(
    port=46841,
    server=tcp => {
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => return
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("<presence") {
              break
            }
          }
        }
      }
      assert_true(buf.contains("<presence xmlns='jabber:client'/>"))
    },
    client_flow=conn => {
      conn.send_initial_presence()
      assert_eq(conn.state(), Online)
    },
  )
}

///|
async test "initial presence requires a bound session" {
  presence_loopback(port=46842, server=_tcp => (), client_flow=conn => {
    conn.state = Connecting
    try conn.send_initial_presence() catch {
      err => assert_true(err is XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected refusal")
    }
    assert_eq(conn.state(), Connecting)
  })
}

///|
async test "recv_presence parses broadcasts and skips other stanzas" {
  presence_loopback(
    port=46843,
    server=tcp => {
      tcp.write(
        "<iq type='result' id='x'/><presence from='alice@example.com/home'/><presence from='bob@example.com' type='unavailable'><status>gone fishing</status></presence>",
      )
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => return
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("</presence>") {
              return
            }
          }
        }
      }
    },
    client_flow=conn => {
      let p1 = conn.recv_presence()
      assert_eq(p1.presence_type, None)
      assert_eq(p1.status, None)
      guard p1.from is Some(f1) else { fail("missing from") }
      assert_eq(f1.to_string(), "alice@example.com/home")
      let p2 = conn.recv_presence()
      assert_eq(p2.presence_type, Some("unavailable"))
      assert_eq(p2.status, Some("gone fishing"))
      assert_eq(
        p2.from.map(fn(j) { j.bare().to_string() }),
        Some("bob@example.com"),
      )
    },
  )
}
