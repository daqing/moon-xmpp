///|
#warnings("-alert_internal")
async test "state machine across a full tls session" {
  let addr = @socket.Addr::parse("127.0.0.1:46839") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='s1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><starttls/></stream:features>",
      )
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => fail("eof before starttls")
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("<starttls") {
              break
            }
          }
        }
      }
      tcp.write("<proceed xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>")
      let tls_server = @tls.Tls::server(
        tcp,
        private_key_file="core/testdata/test_key.pem",
        private_key_type=@tls.X509FileType::PEM,
        certificate_file="core/testdata/test_cert.pem",
        certificate_type=@tls.X509FileType::PEM,
      )
      tls_server.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='s2' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism></mechanisms></stream:features>",
      )
      let auth_buf = StringBuilder()
      for ;; {
        match tls_server.read_some() {
          None => fail("eof before auth")
          Some(data) => {
            auth_buf.write_string(@utf8.decode(data))
            if auth_buf.to_string().contains("</auth>") {
              break
            }
          }
        }
      }
      tls_server.write("<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>")
      tls_server.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='s3' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      let iq_buf = StringBuilder()
      for ;; {
        match tls_server.read_some() {
          None => fail("eof before bind")
          Some(data) => {
            iq_buf.write_string(@utf8.decode(data))
            if iq_buf.to_string().contains("</iq>") {
              break
            }
          }
        }
      }
      tls_server.write(
        "<iq type='result' id='bind_1'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><jid>user@example.com/laptop</jid></bind></iq>",
      )
      tls_server.close()
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46839)
    assert_eq(@core.Connection::state(conn), @core.Connecting)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    assert_eq(@core.Connection::state(conn), @core.Connecting)
    ignore(@core.Connection::starttls(conn, domain="example.com", verify=false))
    assert_eq(@core.Connection::state(conn), @core.NegotiatingTls)
    ignore(
      @core.Connection::authenticate(
        conn,
        jid="user@example.com",
        password="secret",
      ),
    )
    assert_eq(@core.Connection::state(conn), @core.Authenticating)
    let jid = @core.Connection::bind_resource(conn, resource="laptop")
    assert_eq(@core.Connection::state(conn), @core.Bound)
    assert_eq(jid.to_string(), "user@example.com/laptop")
    conn.close()
  })
}

///|
async test "bind before authenticate raises" {
  let addr = @socket.Addr::parse("127.0.0.1:46840") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='s1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      // the client must refuse to bind before authenticating; when its
      // connection closes without an iq, we are done
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => break
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("<iq") {
              fail("client bound without authenticating")
            }
          }
        }
      }
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46840)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    assert_eq(@core.Connection::state(conn), @core.Connecting)
    try @core.Connection::bind_resource(conn, resource="laptop") catch {
      err => assert_true(err is @core.XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected bind to be refused")
    }
    assert_eq(@core.Connection::state(conn), @core.Connecting)
    conn.close()
  })
}
