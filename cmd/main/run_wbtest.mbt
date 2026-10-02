///|
/// Read from the TLS connection until `marker` appears, returning the
/// accumulated text.
#warnings("-alert_internal")
async fn tls_read_until(tls : @tls.Tls, marker~ : String) -> String {
  let mut buf = ""
  for ;; {
    match tls.read_some() {
      None => fail("eof while waiting for \{marker}")
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
/// Drive `run` against a fake server that walks the whole session:
/// STARTTLS upgrade, PLAIN auth, binding, presence, and one chat message.
#warnings("-alert_internal")
async test "run completes the full chain and delivers the chat message" {
  let addr = @socket.Addr::parse("127.0.0.1:46853") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='c1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><starttls/></stream:features>",
      )
      let mut plain = ""
      for ;; {
        match tcp.read_some() {
          None => fail("eof before starttls")
          Some(data) => {
            plain = plain + @utf8.decode(data)
            if plain.contains("<starttls") {
              break
            }
          }
        }
      }
      tcp.write("<proceed xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>")
      let tls = @tls.Tls::server(
        tcp,
        private_key_file="core/testdata/test_key.pem",
        private_key_type=@tls.X509FileType::PEM,
        certificate_file="core/testdata/test_cert.pem",
        certificate_type=@tls.X509FileType::PEM,
      )
      // post-TLS features: PLAIN and bind
      tls.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='c2' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism></mechanisms><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      ignore(tls_read_until(tls, marker="</auth>"))
      tls.write("<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>")
      tls.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='c3' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      ignore(tls_read_until(tls, marker="</iq>"))
      tls.write(
        "<iq type='result' id='bind_1'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><jid>user@example.com/cli</jid></bind></iq>",
      )
      // presence
      let after_presence = tls_read_until(tls, marker="<presence")
      assert_true(after_presence.contains("jabber:client"))
      // the chat message under test
      let msg_buf = tls_read_until(tls, marker="</message>")
      assert_true(msg_buf.contains("to='bob@example.com'"))
      assert_true(msg_buf.contains("type='chat'"))
      assert_true(msg_buf.contains("<body>hello from the cli</body>"))
      tls.write(
        "<message from='bob@example.com' type='chat'><body>got it</body></message>",
      )
      tls.write(
        "<presence from='alice@example.com' type='unavailable'><status>brb</status></presence>",
      )
      @async.sleep(200)
      tls.close()
      tcp.close()
    })
    let opts : CliOptions = {
      jid: "user@example.com",
      password: "secret",
      to: "bob@example.com",
      body: "hello from the cli",
      host: Some("127.0.0.1"),
      port: Some(46853),
      resource: None,
      ca_file: None,
    }
    let conn = run(opts, host="127.0.0.1", port=46853, verify=false)
    assert_eq(conn.state(), Online)
    guard conn.bound_jid() is Some(jid) else { fail("not bound") }
    assert_eq(jid.to_string(), "user@example.com/cli")
    let lines : Array[String] = []
    let print = fn(line : String) { lines.push(line) }
    try receive_loop(conn, print~) catch {
      err => assert_true(err is @core.XmppError::ConnectionClosed)
    } noraise {
      _ => fail("expected stream end")
    }
    assert_eq(lines, [
      "[bob@example.com] got it", "* alice@example.com is unavailable: brb",
    ])
    conn.close()
  })
}
