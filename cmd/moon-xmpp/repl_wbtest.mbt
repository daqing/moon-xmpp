///|
test "parse repl commands" {
  assert_eq(parse_repl_command(""), ReplCommand::Empty)
  assert_eq(parse_repl_command("   "), ReplCommand::Empty)
  assert_eq(parse_repl_command("help"), ReplCommand::Help)
  assert_eq(parse_repl_command(" ? "), ReplCommand::Help)
  assert_eq(parse_repl_command("roster"), ReplCommand::Roster)
  assert_eq(parse_repl_command("quit"), ReplCommand::Quit)
  assert_eq(parse_repl_command("exit"), ReplCommand::Quit)
}

///|
test "parse send keeps the message body" {
  assert_eq(
    parse_repl_command("send bob@example.com hello there"),
    ReplCommand::Send(to="bob@example.com", body="hello there"),
  )
  assert_eq(
    parse_repl_command("  send   bob@example.com    hello   there  "),
    ReplCommand::Send(to="bob@example.com", body="hello   there"),
  )
}

///|
test "parse subscription commands" {
  assert_eq(
    parse_repl_command("subscribe bob@example.com"),
    ReplCommand::Subscribe(jid="bob@example.com"),
  )
  assert_eq(
    parse_repl_command("approve bob@example.com"),
    ReplCommand::Approve(jid="bob@example.com"),
  )
  assert_eq(
    parse_repl_command("unsubscribe bob@example.com"),
    ReplCommand::Unsubscribe(jid="bob@example.com"),
  )
  assert_eq(
    parse_repl_command("deny bob@example.com"),
    ReplCommand::Deny(jid="bob@example.com"),
  )
}

///|
test "missing arguments and unknown commands" {
  assert_eq(
    parse_repl_command("send"),
    ReplCommand::MissingArgument(usage="send <jid> <message>"),
  )
  assert_eq(
    parse_repl_command("send bob@example.com"),
    ReplCommand::MissingArgument(usage="send <jid> <message>"),
  )
  assert_eq(
    parse_repl_command("subscribe"),
    ReplCommand::MissingArgument(usage="subscribe <jid>"),
  )
  assert_eq(
    parse_repl_command("frobnicate"),
    ReplCommand::Unknown(name="frobnicate"),
  )
}

///|
test "help lists every command" {
  let help = repl_help()
  for
    command in [
      "roster", "send", "subscribe", "approve", "unsubscribe", "deny", "help", "quit",
    ] {
    assert_true(help.contains(command))
  }
}

///|
#warnings("-alert_internal")
async fn tcp_read_until(tcp : @socket.Tcp, marker~ : String) -> String {
  let mut buf = ""
  for ;; {
    match tcp.read_some() {
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
/// A TLS reader with its own buffer, so that stanzas arriving in the same
/// chunk as the one being awaited are not dropped.
struct FakeTls {
  tls : @tls.Tls
  mut buf : String
}

///|
#warnings("-alert_internal")
async fn FakeTls::read_until(self : FakeTls, marker~ : String) -> String {
  for ;; {
    match self.buf.find(marker) {
      Some(index) => {
        let end = index + marker.length()
        let result = self.buf[:end].to_owned()
        self.buf = self.buf[end:].to_owned()
        return result
      }
      None =>
        match self.tls.read_some() {
          None => fail("eof while waiting for \{marker}")
          Some(data) => self.buf = self.buf + @utf8.decode(data)
        }
    }
  }
}

///|
/// Drive `repl_loop` against a fake server that walks the session and
/// records the stanzas the REPL sends.
#warnings("-alert_internal")
async test "repl loop dispatches commands onto the connection" {
  let addr = @socket.Addr::parse("127.0.0.1:46890") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='c1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><starttls/></stream:features>",
      )
      ignore(tcp_read_until(tcp, marker="<starttls"))
      tcp.write("<proceed xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>")
      let tls = @tls.Tls::server(
        tcp,
        private_key_file="core/testdata/test_key.pem",
        private_key_type=@tls.X509FileType::PEM,
        certificate_file="core/testdata/test_cert.pem",
        certificate_type=@tls.X509FileType::PEM,
      )
      let reader : FakeTls = { tls, buf: "", }
      tls.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='c2' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism></mechanisms><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      ignore(reader.read_until(marker="</auth>"))
      tls.write("<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>")
      tls.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='c3' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      ignore(reader.read_until(marker="</iq>"))
      tls.write(
        "<iq type='result' id='bind_1'><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><jid>user@example.com/cli</jid></bind></iq>",
      )
      ignore(reader.read_until(marker="<presence"))
      let roster_req = reader.read_until(marker="</iq>")
      assert_true(roster_req.contains("jabber:iq:roster"))
      assert_true(roster_req.contains("id='roster_2'"))
      tls.write(
        "<iq type='result' id='roster_2'><query xmlns='jabber:iq:roster'><item jid='bob@example.com' name='Bob' subscription='both'><group>Friends</group></item></query></iq>",
      )
      let message = reader.read_until(marker="</message>")
      assert_true(message.contains("to='bob@example.com'"))
      assert_true(message.contains("<body>hello there</body>"))
      let subscribe = reader.read_until(marker="type='subscribe'")
      assert_true(subscribe.contains("to='bob@example.com'"))
      let approve = reader.read_until(marker="type='subscribed'")
      assert_true(approve.contains("to='bob@example.com'"))
    })
    let opts : CliOptions = {
      jid: "user@example.com",
      password: "secret",
      to: None,
      body: None,
      host: Some("127.0.0.1"),
      port: Some(46890),
      resource: None,
      ca_file: None,
      roster: false,
      subscribe: None,
      approve: None,
      repl: true,
    }
    let conn = run(opts, host="127.0.0.1", port=46890, verify=false)
    let items = conn.get_roster()
    assert_eq(items.length(), 1)
    let input = [
      "help", "roster", "send bob@example.com hello there", "subscribe bob@example.com",
      "approve bob@example.com", "quit",
    ]
    let mut next = 0
    let read_line = async fn() {
      @async.pause()
      if next < input.length() {
        let line = input[next]
        next += 1
        Some(line)
      } else {
        None
      }
    }
    let output : Array[String] = []
    let prompts : Array[Unit] = []
    let prompt = fn() { prompts.push(()) }
    let presence = PresenceTable::new()
    presence.apply({
      from: Some(@jid.Jid::parse("bob@example.com/phone")),
      presence_type: None,
      show: None,
      status: None,
    })
    repl_loop(
      conn,
      read_line~,
      print_line=fn(line) { output.push(line) },
      prompt~,
      presence~,
    )
    assert_eq(prompts.length(), input.length())
    let text = output.join("\n")
    assert_true(text.contains("commands:"))
    assert_true(text.contains("roster: 1 item(s)"))
    assert_true(
      text.contains(
        "* bob@example.com name=\"Bob\" subscription=SubBoth groups=[Friends] status=online",
      ),
    )
    assert_true(text.contains("sent to bob@example.com"))
    assert_true(text.contains("* subscription request sent to bob@example.com"))
    assert_true(text.contains("* approved subscription from bob@example.com"))
    assert_true(text.contains("bye"))
    conn.close()
  })
}
