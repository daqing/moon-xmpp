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

///|
/// A received chat message. `body` is None for stanzas that carry no
/// `<body/>` (e.g. chat-state notifications), which per RFC 6120 §8.4 must
/// be ignored rather than treated as errors.
pub struct ChatMessage {
  from : @jid.Jid?
  id : String?
  body : String?
} derive(Eq, Debug)

///|
pub extend ChatMessage with Eq::{not_equal, equal}

///|
pub extend ChatMessage with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The next stanza from the server, dispatched by kind. Unknown top-level
/// elements and iqs surface as `Other`, which callers may ignore.
pub(all) enum IncomingStanza {
  Chat(ChatMessage)
  Presence(Presence)
  Other
} derive(Eq, Debug)

///|
pub extend IncomingStanza with Eq::{not_equal, equal}

///|
pub extend IncomingStanza with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Receive the next stanza, blocking until one arrives.
pub async fn Connection::recv_stanza(
  self : Connection,
) -> IncomingStanza raise XmppError {
  for ;; {
    match self.read_incoming() {
      Header(_) =>
        raise XmppError::ProtocolViolation(
          detail="unexpected stream header while receiving a stanza",
        )
      Element(el) =>
        match el.name {
          "message" => return Chat(parse_chat(el))
          "presence" => return Presence(parse_presence(el))
          _ => return Other
        }
    }
  }
}

///|
fn parse_chat(el : @XMLParser.XMLElement) -> ChatMessage raise XmppError {
  let from : @jid.Jid? = match el.get_attribute("from") {
    Some(f) =>
      Some(
        @jid.Jid::parse(f) catch {
          err =>
            raise XmppError::ProtocolViolation(
              detail="invalid from in message: \{Repr(err)}",
            )
        },
      )
    None => None
  }
  let mut body : String? = None
  for child in el.get_children() {
    guard child is @XMLParser.XMLChildren::Element(e) else { continue }
    if e.name == "body" {
      body = Some(e.get_text())
      break
    }
  }
  { from, id: el.get_attribute("id"), body, }
}
