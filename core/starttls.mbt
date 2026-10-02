///|
/// Upgrade the connection to TLS per RFC 6120 §5 and restart the stream.
/// The server must have advertised the starttls feature. When `verify` is
/// true, the server certificate is validated against the system roots with
/// hostname matching against `domain`.
pub async fn Connection::starttls(
  self : Connection,
  domain~ : String,
  verify? : Bool = true,
) -> Features raise XmppError {
  let advertised = match self.features {
    Some(f) => f
    None => raise XmppError::ProtocolViolation(detail="stream not open")
  }
  if !advertised.starttls {
    raise XmppError::ProtocolViolation(detail="server does not offer STARTTLS")
  }
  self.send_raw("<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>")
  let tcp = match self.transport {
    Tcp(tcp) => tcp
    Tls(_, _) =>
      raise XmppError::ProtocolViolation(detail="connection already encrypted")
  }
  let response = read_raw_element(tcp)
  if response.has_prefix("<failure") {
    self.close()
    raise XmppError::ProtocolViolation(detail="server refused STARTTLS")
  }
  if !response.has_prefix("<proceed") {
    raise XmppError::ProtocolViolation(
      detail="unexpected STARTTLS response: \{response}",
    )
  }
  let trust = if verify {
    @tls.TrustedRoot::SystemRoot
  } else {
    @tls.TrustedRoot::NoVerification
  }
  let tls = @tls.Tls::client(tcp, host=domain, trust~) catch {
    err => raise XmppError::Io(detail="tls handshake failed: \{Repr(err)}")
  }
  self.transport = Tls(tls, tcp)
  self.restart_stream(domain~)
}

///|
/// Read one XML element byte-by-byte from the raw socket. Used for the
/// STARTTLS proceed/failure response so that any bytes the server sent
/// after it stay in the socket buffer for the TLS handshake to consume.
async fn read_raw_element(tcp : @socket.Tcp) -> String raise XmppError {
  let buf : Array[Byte] = []
  let mut quote = 0
  let mut in_quote = false
  for ;; {
    let chunk = tcp.read_some(max_len=1) catch {
      err => raise XmppError::Io(detail="read failed: \{Repr(err)}")
    }
    match chunk {
      None => raise XmppError::ConnectionClosed
      Some(data) => {
        if data.length() == 0 {
          continue
        }
        let b = data[0]
        buf.push(b)
        let n = b.to_int()
        if in_quote {
          if n == quote {
            in_quote = false
          }
        } else if n == 0x27 || n == 0x22 {
          in_quote = true
          quote = n
        } else if n == 0x3e {
          return @utf8.decode(Bytes::from_array(buf[:buf.length()])) catch {
            _ =>
              raise XmppError::ProtocolViolation(
                detail="invalid utf-8 in STARTTLS response",
              )
          }
        }
      }
    }
  }
}
