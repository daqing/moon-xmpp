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
pub(all) struct ChatMessage {
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
  RosterPush(RosterItem)
  Subscription(SubscriptionRequest)
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
  if self.pending.length() > 0 {
    return self.pending.remove(0)
  }
  let el = match self.read_incoming() {
    Element(el) => el
    Header(_) =>
      raise XmppError::ProtocolViolation(
        detail="unexpected stream header while receiving a stanza",
      )
  }
  if el.name is "iq" {
    match self.handle_iq(el) {
      Some(event) => return event
      None => return Other
    }
  }
  classify_stanza(el)
}

///|
/// Turn a received element into a stanza event. Presence subscription
/// stanzas are surfaced separately from availability broadcasts so callers
/// can answer them deliberately (RFC 6121 §3.1.3).
fn classify_stanza(el : @xml.XMLElement) -> IncomingStanza raise XmppError {
  match el.name {
    "message" => Chat(parse_chat(el))
    "presence" =>
      match parse_subscription_kind(el) {
        Some(kind) => Subscription(parse_subscription_request(el, kind~))
        None => Presence(parse_presence(el))
      }
    _ => Other
  }
}

///|
fn parse_chat(el : @xml.XMLElement) -> ChatMessage raise XmppError {
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
    guard child is @xml.XMLChildren::Element(e) else { continue }
    if e.name == "body" {
      body = Some(element_text(e))
      break
    }
  }
  { from, id: el.get_attribute("id"), body, }
}

///|
/// Compose the character data of an element. The pull parser decodes entity
/// and character references while reading text, so the character-data,
/// CDATA, and whitespace nodes can be concatenated directly.
fn element_text(el : @xml.XMLElement) -> String {
  let buf = StringBuilder()
  for child in el.get_children() {
    match child {
      @xml.XMLChildren::Text(t) => buf.write_string(t)
      @xml.XMLChildren::CDATA(t) => buf.write_string(t)
      @xml.XMLChildren::WhiteSpace(t) => buf.write_string(t)
      _ => ()
    }
  }
  buf.to_string()
}
