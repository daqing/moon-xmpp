///|
/// Send the initial presence (RFC 6121 §4.2): an empty `<presence/>`
/// announces availability. The session moves to Online; the server starts
/// delivering the contact presence broadcasts and messages only after this.
pub async fn Connection::send_initial_presence(
  self : Connection,
) -> Unit raise XmppError {
  if self.state != Bound {
    raise XmppError::ProtocolViolation(
      detail="initial presence requires a bound session",
    )
  }
  self.send_raw("<presence xmlns='jabber:client'/>")
  self.state = Online
}
