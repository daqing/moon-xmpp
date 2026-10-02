///|
async test "sasl challenge response and success" {
  let addr = @socket.Addr::parse("127.0.0.1:46829") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='s1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>TEST</mechanism></mechanisms></stream:features>",
      )
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => fail("eof during sasl")
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("<auth") {
              break
            }
          }
        }
      }
      assert_true(buf.contains("mechanism='TEST'"))
      tcp.write(
        "<challenge xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>Z28=</challenge>",
      )
      buf = ""
      for ;; {
        match tcp.read_some() {
          None => fail("eof during sasl challenge")
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("<response") {
              break
            }
          }
        }
      }
      assert_true(buf.contains("Zm9v"))
      tcp.write("<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>")
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='s2' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46829)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    let reply = @core.Connection::sasl_auth(
      conn,
      mechanism="TEST",
      initial="aGVsbG8=",
    )
    guard reply is @core.SaslReply::Challenge(text) else {
      fail("expected challenge")
    }
    assert_eq(@base64.decode(text), b"go")
    let reply2 = @core.Connection::sasl_respond(conn, payload="Zm9v")
    guard reply2 is @core.SaslReply::Success(_) else {
      fail("expected success")
    }
    let features = @core.Connection::restart_stream(conn, domain="example.com")
    assert_true(features.bind)
    conn.close()
  })
}

///|
async test "sasl failure raises with condition" {
  let addr = @socket.Addr::parse("127.0.0.1:46830") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='s1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>TEST</mechanism></mechanisms></stream:features>",
      )
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => break
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("<auth") {
              break
            }
          }
        }
      }
      tcp.write(
        "<failure xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><not-authorized/><text>bad login</text></failure>",
      )
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46830)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    try @core.Connection::sasl_auth(conn, mechanism="TEST", initial="") catch {
      err => assert_true(err is @core.XmppError::Auth(detail=_))
    } noraise {
      _ => fail("expected auth failure")
    }
    conn.close()
  })
}
