///|
/// Locate `needle` in `s`, failing the test when absent.
fn require_index(s : String, needle : String) -> Int raise {
  match s.find(needle) {
    Some(i) => i
    None => fail("needle not found: \{needle}")
  }
}

///|
/// Attribute lookup helper for the fake SCRAM server in tests.
fn test_attr(msg : String, key : String) -> String? {
  for part in msg.split(",") {
    if part.has_prefix("\{key}=") {
      return Some(part[1 + key.length():].to_owned())
    }
  }
  None
}

///|
/// Run a full SCRAM login against a loopback fake server that verifies the
/// client's proof with the known password ("pencil") and answers with a
/// valid server signature.
#warnings("-alert_internal")
async fn scram_loopback(alg~ : @sasl.ScramAlg, port~ : Int) -> Unit {
  let mech = match alg {
    @sasl.Sha1 => "SCRAM-SHA-1"
    @sasl.Sha256 => "SCRAM-SHA-256"
  }
  let addr = @socket.Addr::parse("127.0.0.1:\{port}") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='sc1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>\{mech}</mechanism></mechanisms></stream:features>",
      )
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => fail("eof before auth")
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("</auth>") {
              break
            }
          }
        }
      }
      assert_true(buf.contains("mechanism='\{mech}'"))
      try {
        // extract the <auth> payload: gs2 "n,," + client-first-bare
        let auth_open = require_index(buf, "<auth")
        let open = require_index(buf[auth_open:].to_owned(), ">") + auth_open
        let close = require_index(buf, "</auth>")
        let first = buf[open + 1:close].to_owned()
        let bare = first["n,,".length():].to_owned()
        let client_nonce = test_attr(bare, "r")
        guard client_nonce is Some(cn) else { fail("missing client nonce") }
        let salt : Bytes = b"salt pepper salt pepper salt pepper salt pep"
        let server_first = "r=\{cn}3rfcNHYJY1ZVvWVs7j,s=\{@base64.encode(salt)},i=4096"
        tcp.write(
          "<challenge xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>\{@base64.encode(@utf8.encode(server_first))}</challenge>",
        )
        buf = ""
        for ;; {
          match tcp.read_some() {
            None => fail("eof before response")
            Some(data) => {
              buf = buf + @utf8.decode(data)
              if buf.contains("</response>") {
                break
              }
            }
          }
        }
        let open2 = require_index(buf, "xmpp-sasl'>")
        let close2 = require_index(buf, "</response>")
        let final_msg = buf[open2 + "xmpp-sasl'>".length():close2].to_owned()
        assert_eq(test_attr(final_msg, "r"), Some("\{cn}3rfcNHYJY1ZVvWVs7j"))
        assert_eq(test_attr(final_msg, "c"), Some("biws"))
        // verify the client's proof with the known password; the
        // AuthMessage uses the client-final message WITHOUT the proof
        let p_idx = require_index(final_msg, ",p=")
        let final_bare = final_msg[:p_idx].to_owned()
        let auth_message = "\{bare},\{server_first},\{final_bare}"
        let salted = @sasl.pbkdf2(
          alg~,
          password=@utf8.encode("pencil"),
          salt~,
          iterations=4096,
        )
        let client_key = @sasl.hmac_bytes(
          alg~,
          key=@sasl.fixed_to_bytes(salted),
          message=@utf8.encode("Client Key"),
        )
        let stored_key = @sasl.hash_bytes(
          alg~,
          @sasl.fixed_to_bytes(client_key),
        )
        let client_signature = @sasl.hmac_bytes(
          alg~,
          key=@sasl.fixed_to_bytes(stored_key),
          message=@utf8.encode(auth_message),
        )
        let proof = @sasl.xor_fixed(client_key, client_signature)
        assert_eq(
          test_attr(final_msg, "p"),
          Some(@base64.encode(@sasl.fixed_to_bytes(proof), padding=true)),
        )
        let server_key = @sasl.hmac_bytes(
          alg~,
          key=@sasl.fixed_to_bytes(salted),
          message=@utf8.encode("Server Key"),
        )
        let server_signature = @sasl.hmac_bytes(
          alg~,
          key=@sasl.fixed_to_bytes(server_key),
          message=@utf8.encode(auth_message),
        )
        let v_payload = "v=\{@base64.encode(@sasl.fixed_to_bytes(server_signature), padding=true)}"
        tcp.write(
          "<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>\{@base64.encode(@utf8.encode(v_payload))}</success>",
        )
      } catch {
        msg => fail("\{msg}")
      }
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='sc2' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port~)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    let features = @core.Connection::authenticate(
      conn,
      jid="user",
      password="pencil",
    )
    assert_true(features.bind)
    conn.close()
  })
}

///|
async test "authenticate with scram-sha-1 over loopback" {
  scram_loopback(alg=@sasl.Sha1, port=46833)
}

///|
async test "authenticate with scram-sha-256 over loopback" {
  scram_loopback(alg=@sasl.Sha256, port=46834)
}
