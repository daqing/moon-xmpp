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
  let response = self.read_raw_element()
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
