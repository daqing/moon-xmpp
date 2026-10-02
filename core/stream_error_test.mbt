///|
async test "stream error is raised during open_stream" {
  let addr = @socket.Addr::parse("127.0.0.1:46824") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (client, _) = server.accept()
      ignore(client.read_some())
      client.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='x' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:error><system-shutdown/></stream:error></stream:stream>",
      )
      client.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46824)
    try @core.Connection::open_stream(conn, domain="example.com") catch {
      err =>
        assert_true(
          err
          is @core.XmppError::StreamError(
            condition=@core.StreamErrorCondition::SystemShutdown,
            text=_,
          ),
        )
    } noraise { _ => fail("expected stream error") }
    conn.close()
  })
}
