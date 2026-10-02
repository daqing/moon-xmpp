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
      body = Some(element_text(e))
      break
    }
  }
  { from, id: el.get_attribute("id"), body, }
}

///|
/// Compose the character data of an element. The XML parser keeps entity
/// references as separate children, so they are decoded here: the five
/// predefined entities plus decimal and hex character references. Unknown
/// references are kept literally.
fn element_text(el : @XMLParser.XMLElement) -> String {
  let buf = StringBuilder()
  for child in el.get_children() {
    match child {
      @XMLParser.XMLChildren::Text(t) => buf.write_string(t)
      @XMLParser.XMLChildren::CDATA(t) => buf.write_string(t)
      @XMLParser.XMLChildren::WhiteSpace(t) => buf.write_string(t)
      @XMLParser.XMLChildren::Reference(r) =>
        buf.write_string(decode_reference(r))
      _ => ()
    }
  }
  buf.to_string()
}

///|
/// Parse an uppercase or lowercase hex number, None on invalid input.
fn parse_hex(s : String) -> Int? {
  let mut n = 0
  for c in s {
    let d = match c {
      '0'..='9' => c.to_int() - 0x30
      'a'..='f' => c.to_int() - 0x61 + 10
      'A'..='F' => c.to_int() - 0x41 + 10
      _ => return None
    }
    n = n * 16 + d
  }
  Some(n)
}

///|
fn decode_reference(r : String) -> String {
  // the parser stores named references as "&amp;" but numeric ones as
  // "#65;", so strip the trailing ";" and an optional leading "&"
  guard r.has_suffix(";") && r.length() >= 2 else { return r }
  let name = if r.has_prefix("&") {
    r[1:r.length() - 1].to_owned()
  } else {
    r[:r.length() - 1].to_owned()
  }
  match name {
    "amp" => return "&"
    "lt" => return "<"
    "gt" => return ">"
    "quot" => return "\""
    "apos" => return "'"
    _ => ()
  }
  if name.has_prefix("#x") || name.has_prefix("#X") {
    match parse_hex(name[2:].to_owned()) {
      Some(n) =>
        match n.to_char() {
          Some(c) => return char_to_string(c)
          None => return r
        }
      None => return r
    }
  }
  if name.has_prefix("#") {
    let n = @string.parse_int(name[1:].to_owned()) catch { _ => -1 }
    if n >= 0 {
      match n.to_char() {
        Some(c) => return char_to_string(c)
        None => return r
      }
    }
  }
  r
}

///|
fn char_to_string(c : Char) -> String {
  let b = StringBuilder()
  b.write_char(c)
  b.to_string()
}
