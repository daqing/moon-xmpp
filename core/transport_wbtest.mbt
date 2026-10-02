///|
async test "pump reads frames from socket" {
  let addr = @socket.Addr::parse("127.0.0.1:46822") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (client, _) = server.accept()
      client.write("<stream:stream>")
      client.close()
    })
    let conn = connect(host="127.0.0.1", port=46822)
    let frames = conn.pump()
    assert_eq(frames.length(), 1)
    assert_true(frames[0] is @xml.Frame::Root("<stream:stream>"))
    conn.close()
  })
}
