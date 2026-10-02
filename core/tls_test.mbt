///|
#warnings("-alert_internal")
async test "tls upgrade over established tcp" {
  let addr = @socket.Addr::parse("127.0.0.1:46825") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      let server_tls = @tls.Tls::server(
        tcp,
        private_key_file="core/testdata/test_key.pem",
        private_key_type=@tls.X509FileType::PEM,
        certificate_file="core/testdata/test_cert.pem",
        certificate_type=@tls.X509FileType::PEM,
      )
      match server_tls.read_some() {
        Some(data) => assert_eq(@utf8.decode(data), "ping")
        None => fail("expected client data")
      }
      server_tls.write("pong")
      server_tls.close()
      tcp.close()
    })
    let tcp = @socket.Tcp::connect_to_host("127.0.0.1", port=46825)
    let client_tls = @tls.Tls::client(
      tcp,
      host="localhost",
      trust=@tls.TrustedRoot::NoVerification,
    )
    client_tls.write("ping")
    match client_tls.read_some() {
      Some(data) => assert_eq(@utf8.decode(data), "pong")
      None => fail("expected server data")
    }
    client_tls.close()
    tcp.close()
  })
}
