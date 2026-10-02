///|
/// Full SCRAM-SHA-256-PLUS login over a real TLS upgrade. The fake server
/// verifies that the client bound the connection: the gs2 header names
/// tls-server-end-point and the c= value carries the binding data.
#warnings("-alert_internal")
async test "authenticate with scram-sha-256-plus over tls" {
  let addr = @socket.Addr::parse("127.0.0.1:46835") catch {
    _ => fail("invalid test addr")
  }
  let server = @socket.TcpServer::TcpServer(addr, reuse_addr=true)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let (tcp, _) = server.accept()
      tcp.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='cb1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><starttls/></stream:features>",
      )
      let mut buf = ""
      for ;; {
        match tcp.read_some() {
          None => fail("eof before starttls")
          Some(data) => {
            buf = buf + @utf8.decode(data)
            if buf.contains("<starttls") {
              break
            }
          }
        }
      }
      tcp.write("<proceed xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>")
      let tls_server = @tls.Tls::server(
        tcp,
        private_key_file="core/testdata/test_key.pem",
        private_key_type=@tls.X509FileType::PEM,
        certificate_file="core/testdata/test_cert.pem",
        certificate_type=@tls.X509FileType::PEM,
      )
      tls_server.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='cb1' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>SCRAM-SHA-256</mechanism><mechanism>SCRAM-SHA-256-PLUS</mechanism></mechanisms></stream:features>",
      )
      try {
        let auth_buf = StringBuilder()
        for ;; {
          match tls_server.read_some() {
            None => fail("eof before auth")
            Some(data) => {
              auth_buf.write_string(@utf8.decode(data))
              if auth_buf.to_string().contains("</auth>") {
                break
              }
            }
          }
        }
        let s = auth_buf.to_string()
        assert_true(s.contains("mechanism='SCRAM-SHA-256-PLUS'"))
        let auth_open = require_index(s, "<auth")
        let open = require_index(s[auth_open:].to_owned(), ">") + auth_open
        let close = require_index(s, "</auth>")
        let encoded = s[open + 1:close].to_owned()
        let first = @utf8.decode(@base64.decode(encoded))
        // client-first = gs2 ",," bare; with binding the gs2 names the
        // binding and no "y" fallback is used
        let gs2 = "p=tls-server-end-point"
        assert_true(first.has_prefix("\{gs2},,"))
        let bare = first[gs2.length() + 2:].to_owned()
        let client_nonce = test_attr(bare, "r")
        guard client_nonce is Some(cn) else { fail("missing client nonce") }
        let salt : Bytes = b"plus salt plus salt plus salt plus sa"
        let server_first = "r=\{cn}WvBYaepP8S2csBkN,s=\{@base64.encode(salt)},i=4096"
        tls_server.write(
          "<challenge xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>\{@base64.encode(@utf8.encode(server_first))}</challenge>",
        )
        let resp_buf = StringBuilder()
        for ;; {
          match tls_server.read_some() {
            None => fail("eof before response")
            Some(data) => {
              resp_buf.write_string(@utf8.decode(data))
              if resp_buf.to_string().contains("</response>") {
                break
              }
            }
          }
        }
        let rs = resp_buf.to_string()
        let open2 = require_index(rs, "xmpp-sasl'>")
        let close2 = require_index(rs, "</response>")
        let final_msg = @utf8.decode(
          @base64.decode(rs[open2 + "xmpp-sasl'>".length():close2].to_owned()),
        )
        assert_eq(test_attr(final_msg, "r"), Some("\{cn}WvBYaepP8S2csBkN"))
        // c= must decode to gs2 ",," plus the 32-byte binding data
        let c_b64 = test_attr(final_msg, "c")
        guard c_b64 is Some(c_val) else { fail("missing c=") }
        let c_bytes = @base64.decode(c_val)
        assert_eq(c_bytes.length(), gs2.length() + 2 + 32)
        let gs2_bytes = @utf8.encode("\{gs2},,")
        for i in 0..<gs2_bytes.length() {
          assert_eq(c_bytes[i], gs2_bytes[i])
        }
        // verify the proof
        let p_idx = require_index(final_msg, ",p=")
        let final_bare = final_msg[:p_idx].to_owned()
        let auth_message = "\{bare},\{server_first},\{final_bare}"
        let salted = @sasl.pbkdf2(
          alg=@sasl.Sha256,
          password=@utf8.encode("pencil"),
          salt~,
          iterations=4096,
        )
        let client_key = @sasl.hmac_bytes(
          alg=@sasl.Sha256,
          key=@sasl.fixed_to_bytes(salted),
          message=@utf8.encode("Client Key"),
        )
        let stored_key = @sasl.hash_bytes(
          alg=@sasl.Sha256,
          @sasl.fixed_to_bytes(client_key),
        )
        let client_signature = @sasl.hmac_bytes(
          alg=@sasl.Sha256,
          key=@sasl.fixed_to_bytes(stored_key),
          message=@utf8.encode(auth_message),
        )
        let proof = @sasl.xor_fixed(client_key, client_signature)
        assert_eq(
          test_attr(final_msg, "p"),
          Some(@base64.encode(@sasl.fixed_to_bytes(proof), padding=true)),
        )
        let server_key = @sasl.hmac_bytes(
          alg=@sasl.Sha256,
          key=@sasl.fixed_to_bytes(salted),
          message=@utf8.encode("Server Key"),
        )
        let server_signature = @sasl.hmac_bytes(
          alg=@sasl.Sha256,
          key=@sasl.fixed_to_bytes(server_key),
          message=@utf8.encode(auth_message),
        )
        let v_payload = "v=\{@base64.encode(@sasl.fixed_to_bytes(server_signature), padding=true)}"
        tls_server.write(
          "<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>\{@base64.encode(@utf8.encode(v_payload))}</success>",
        )
      } catch {
        msg => fail("\{msg}")
      }
      tls_server.write(
        "<?xml version='1.0'?><stream:stream from='example.com' id='cb2' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'><stream:features><bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/></stream:features>",
      )
      tls_server.close()
      tcp.close()
    })
    let conn = @core.connect(host="127.0.0.1", port=46835)
    ignore(@core.Connection::open_stream(conn, domain="example.com"))
    ignore(@core.Connection::starttls(conn, domain="example.com", verify=false))
    let features = @core.Connection::authenticate(
      conn,
      jid="user",
      password="pencil",
      channel_binding=true,
    )
    assert_true(features.bind)
    conn.close()
  })
}
