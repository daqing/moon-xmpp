///|
#warnings("-alert_internal")
async test "starttls rejects self-signed certificate with system roots" {
  let addr = @socket.Addr::parse("127.0.0.1:46828") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='plain' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><starttls/></stream:features>",
      )
      let mut seen = ""
      for ;; {
        match tcp.read_some() {
          None => break
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
      server_tls.close()
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46828)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    try
      @core.Connection::starttls(conn, domain="example.com", verify=true)
    catch {
      err => assert_true(err is @core.XmppError::Io(detail=_))
    } noraise {
      _ => fail("expected handshake failure")
    }
    conn.close()
  })
}
