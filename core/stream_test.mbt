///|
async test "open stream reads server header and features" {
  let addr = @socket.Addr::parse("127.0.0.1:46823") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (client, _) = server.accept()
      let sent = client.read_some()
      match sent {
        Some(data) => {
          let text = @utf8.decode(data)
          assert_true(text.contains("<stream:stream"))
          assert_true(text.contains("to='example.com'"))
        }
        None => fail("expected client header")
      }
      client.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='abc123' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><starttls/><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism><mechanism>SCRAM-SHA-1</mechanism></mechanisms><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      client.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46823)
    let features = @core.Connection::open_stream(conn, domain="example.com")
    assert_eq(features.mechanisms, ["PLAIN", "SCRAM-SHA-1"])
    assert_true(features.starttls)
    assert_true(features.bind)
    assert_eq(@core.Connection::stream_id(conn), Some("abc123"))
    conn.close()
  })
}
