///|
/// Run `flow` with a connection whose TCP session is held open by a
/// placeholder server. The guards under test only inspect connection
/// state, so the server never speaks.
async fn with_fake_session(
  port~ : Int,
  flow~ : async (Connection) -> Unit,
) -> Unit {
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      @async.sleep(10_000)
      tcp.close()
    })
    let conn = connect(host="127.0.0.1", port~)
    flow(conn)
    group.return_immediately(())
  })
}

///|
async test "authenticate refuses when the stream is not open" {
  with_fake_session(port=46855, flow=conn => {
    conn.features = None
    try conn.authenticate(jid="u@e.com", password="p") catch {
      err => assert_true(err is XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected refusal")
    }
  })
}

///|
async test "authenticate refuses twice" {
  with_fake_session(port=46856, flow=conn => {
    conn.features = Some({
      starttls: false,
      starttls_required: false,
      mechanisms: ["PLAIN"],
      bind: false,
    })
    conn.state = Authenticating
    try conn.authenticate(jid="u@e.com", password="p") catch {
      err => assert_true(err is XmppError::ProtocolViolation(detail=_))
    } noraise {
      _ => fail("expected refusal")
    }
  })
}

///|
async test "explicit mechanism must be advertised" {
  with_fake_session(port=46857, flow=conn => {
    conn.features = Some({
      starttls: false,
      starttls_required: false,
      mechanisms: ["PLAIN"],
      bind: false,
    })
    try
      conn.authenticate(
        jid="u@e.com",
        password="p",
        mechanism=Some("SCRAM-SHA-256"),
      )
    catch {
      err => assert_true(err is XmppError::Auth(detail=_))
    } noraise {
      _ => fail("expected refusal")
    }
  })
}
