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
