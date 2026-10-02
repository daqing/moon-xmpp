///|
/// Full PLAIN login over a real TLS upgrade with a loopback server.
#warnings("-alert_internal")
async test "authenticate with plain over tls" {
  let addr = @socket.Addr::parse("127.0.0.1:46831") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='p1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><starttls/></stream:features>",
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
        "<?xml version='1.0'?><stream:stream from='example.com' id='p1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism></mechanisms></stream:features>",
      )
      let auth_buf = StringBuilder()
      for ;; {
        match tls_server.read_some() {
          None => fail("eof before auth")
          Some(data) => {
            auth_buf.write_string(@utf8.decode(data))
            let s = auth_buf.to_string()
            if s.contains("</auth>") {
              break
            }
          }
        }
      }
      assert_true(auth_buf.to_string().contains("mechanism='PLAIN'"))
      assert_true(
        auth_buf.to_string().contains("AHVzZXJAZXhhbXBsZS5jb20Ac2VjcmV0"),
      )
      tls_server.write("<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>")
      tls_server.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='p2' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      tls_server.close()
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46831)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    ignore(@core.Connection::starttls(conn, domain="example.com", verify=false))
    let features = @core.Connection::authenticate(
      conn,
      jid="user@example.com",
      password="secret",
    )
    assert_true(features.bind)
    conn.close()
  })
}

///|
async test "authenticate refuses plain on unencrypted stream" {
  let addr = @socket.Addr::parse("127.0.0.1:46832") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='p1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism></mechanisms></stream:features>",
      )
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46832)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    try
      @core.Connection::authenticate(
        conn,
        jid="user@example.com",
        password="secret",
      )
    catch {
      err => assert_true(err is @core.XmppError::Auth(detail=_))
    } noraise {
      _ => fail("expected auth failure")
    }
    conn.close()
  })
}
