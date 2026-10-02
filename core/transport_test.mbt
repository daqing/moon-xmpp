///|
async test "connect, send, close over loopback" {
  let addr = @socket.Addr::parse("127.0.0.1:46821") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (client, _) = server.accept()
      let mut total = 0
      for ;; {
        match client.read_some() {
          None => break
          Some(data) => total += data.length()
        }
      }
      assert_eq(total, 5)
      client.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46821)
    @core.Connection::send_raw(conn, "hello")
    @core.Connection::close(conn)
    assert_true(conn.is_closed())
  })
}
