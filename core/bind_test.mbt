///|
/// Run `client_flow` against a fake server that completes a session up to
/// the bind step and answers a single bind iq. Both sides run inside one
/// task group so the server task can wait for the client's iq without
/// deadlocking the group.
async fn bind_loopback(
  port~ : Int,
  resource_offered~ : String,
  reply_jid~ : String,
  error_reply? : Bool = false,
  client_flow~ : async (@core.Connection) -> Unit,
) -> Unit {
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='b1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => return
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("</iq>") {
              break
            }
          }
        }
      }
      if resource_offered is "" {
        assert_true(
          buf.contains("<bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/>"),
        )
      } else {
        assert_true(buf.contains("<resource>\{resource_offered}</resource>"))
      }
      if error_reply {
        tcp.write(
          "<iq type='error' id='bind_1'><error type='cancel'><conflict xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>",
        )
      } else {
        tcp.write(
          "<iq type='result' id='bind_1'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><jid>\{reply_jid}</jid></bind></iq>",
        )
      }
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port~)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    client_flow(conn)
    conn.close()
  })
}

///|
async test "bind with a requested resource" {
  bind_loopback(
    port=46836,
    resource_offered="laptop",
    reply_jid="user@example.com/laptop",
    client_flow=conn => {
      let jid = @core.Connection::bind_resource(conn, resource="laptop")
      assert_eq(jid.to_string(), "user@example.com/laptop")
      guard @core.Connection::bound_jid(conn) is Some(bound) else {
        fail("bound jid not stored")
      }
      assert_eq(bound.localpart, Some("user"))
      assert_eq(bound.resourcepart, Some("laptop"))
    },
  )
}

///|
async test "bind without a resource gets a server-assigned one" {
  bind_loopback(
    port=46837,
    resource_offered="",
    reply_jid="user@example.com/server-assigned-1",
    client_flow=conn => {
      let jid = @core.Connection::bind_resource(conn)
      assert_eq(jid.resourcepart, Some("server-assigned-1"))
    },
  )
}

///|
async test "bind error raises with the condition" {
  bind_loopback(
    port=46838,
    resource_offered="dup",
    reply_jid="",
    error_reply=true,
    client_flow=conn => {
      try @core.Connection::bind_resource(conn, resource="dup") catch {
        err => assert_true(err is @core.XmppError::ProtocolViolation(detail=_))
      } noraise {
        _ => fail("expected bind error")
      }
    },
  )
}
