///|
/// Send a one-on-one chat message (RFC 6121 §5.2): `type='chat'` with a
/// `<body/>`. Returns the generated stanza id.
pub async fn Connection::send_chat(
  self : Connection,
  to~ : String,
  body~ : String,
) -> String raise XmppError {
  if !(self.state is (Bound | Online)) {
    raise XmppError::ProtocolViolation(
      detail="sending chat requires a bound session",
    )
  }
  self.iq_counter += 1
  let id = "msg_\{self.iq_counter}"
  self.send_raw(
    "<message type='chat' id='\{id}' to='\{@xml.escape_attr(to)}' xmlns='jabber:client'><body>\{@xml.escape_text(body)}</body></message>",
  )
  id
}
