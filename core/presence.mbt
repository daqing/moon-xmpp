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

///|
/// A received contact presence broadcast (RFC 6121 §4.4). `presence_type`
/// is None for available and carries e.g. "unavailable" or "error"
/// otherwise. `show` is the availability detail of an available presence:
/// "away", "chat", "dnd", or "xa" (RFC 6121 §4.7.2.1).
pub(all) struct Presence {
  from : @jid.Jid?
  presence_type : String?
  show : String?
  status : String?
} derive(Eq, Debug)

///|
pub extend Presence with Eq::{not_equal, equal}

///|
pub extend Presence with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Receive the next contact presence broadcast. Chat messages and other
/// stanzas encountered first are skipped; use `recv_stanza` to handle all
/// stanza kinds.
pub async fn Connection::recv_presence(
  self : Connection,
) -> Presence raise XmppError {
  for ;; {
    match self.recv_stanza() {
      Presence(p) => return p
      _ => continue
    }
  }
}

///|
fn parse_presence(el : @xml.XMLElement) -> Presence raise XmppError {
  let from : @jid.Jid? = match el.get_attribute("from") {
    Some(f) =>
      Some(
        @jid.Jid::parse(f) catch {
          err =>
            raise XmppError::ProtocolViolation(
              detail="invalid from in presence: \{Repr(err)}",
            )
        },
      )
    None => None
  }
  let mut show : String? = None
  let mut status : String? = None
  for child in el.get_children() {
    guard child is @xml.XMLChildren::Element(e) else { continue }
    if e.name == "status" {
      status = Some(element_text(e))
    }
    if e.name == "show" {
      show = Some(element_text(e).trim().to_owned())
    }
  }
  { from, presence_type: el.get_attribute("type"), show, status, }
}

///|
/// Sign off gracefully: send an unavailable presence, close the XML stream,
/// and disconnect (RFC 6121 §4.5, RFC 6120 §4.4).
pub async fn Connection::signoff(self : Connection) -> Unit raise XmppError {
  if !(self.state is (Bound | Online)) {
    raise XmppError::ProtocolViolation(
      detail="signoff requires a bound session",
    )
  }
  self.send_raw("<presence type='unavailable' xmlns='jabber:client'/>")
  self.send_raw("</stream:stream>")
  self.close()
}
