///|
#warnings("-alert_internal")
async test "starttls upgrades and restarts the stream" {
  let addr = @socket.Addr::parse("127.0.0.1:46826") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='plain' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><starttls/></stream:features>",
      )
      let mut seen = ""
      for ;; {
        match tcp.read_some() {
          None => fail("eof before starttls request")
          Some(data) => {
            seen = seen + @utf8.decode(data)
            if seen.contains("<starttls") {
              break
            }
          }
        }
      }
      tcp.write("<proceed xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>")
      let server_tls = @tls.Tls::server(
        tcp,
        private_key_file="core/testdata/test_key.pem",
        private_key_type=@tls.X509FileType::PEM,
        certificate_file="core/testdata/test_cert.pem",
        certificate_type=@tls.X509FileType::PEM,
      )
      match server_tls.read_some() {
        Some(data) =>
          assert_true(@utf8.decode(data).contains("to='example.com'"))
        None => fail("expected client stream header over tls")
      }
      server_tls.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='secure' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism><mechanism>SCRAM-SHA-1</mechanism></mechanisms><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      server_tls.close()
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46826)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    let features = @core.Connection::starttls(
      conn,
      domain="example.com",
      verify=false,
    )
    assert_eq(features.mechanisms, ["PLAIN", "SCRAM-SHA-1"])
    assert_true(features.bind)
    assert_true(@core.Connection::is_encrypted(conn))
    assert_eq(@core.Connection::stream_id(conn), Some("secure"))
    conn.close()
  })
}

///|
#warnings("-alert_internal")
async test "starttls raises when not offered" {
  let addr = @socket.Addr::parse("127.0.0.1:46827") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='plain' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism></mechanisms></stream:features>",
      )
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46827)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    try @core.Connection::starttls(conn, domain="example.com") catch {
      err => assert_true(err is @core.XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected error")
    }
    conn.close()
  })
}
