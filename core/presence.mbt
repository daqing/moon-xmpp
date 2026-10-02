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
/// otherwise.
pub struct Presence {
  from : @jid.Jid?
  presence_type : String?
  status : String?
} derive(Eq, Debug)

///|
pub extend Presence with Eq::{not_equal, equal}

///|
pub extend Presence with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Receive the next contact presence broadcast. Stanzas that are not
/// presence (messages, iqs) are currently skipped; message reception
/// arrives with the chat support.
pub async fn Connection::recv_presence(
  self : Connection,
) -> Presence raise XmppError {
  for ;; {
    match self.read_incoming() {
      Header(_) =>
        raise XmppError::ProtocolViolation(
          detail="unexpected stream header while receiving presence",
        )
      Element(el) => {
        if el.name != "presence" {
          continue
        }
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
        let mut status : String? = None
        for child in el.get_children() {
          guard child is @XMLParser.XMLChildren::Element(e) else { continue }
          if e.name == "status" {
            status = Some(e.get_text())
          }
        }
        return { from, presence_type: el.get_attribute("type"), status, }
      }
    }
  }
}
