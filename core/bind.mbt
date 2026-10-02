///|
/// Bind a resource (RFC 6120 §7) and return the server-assigned full JID.
/// With an empty `resource` the server picks one. The server must have
/// advertised the bind feature (i.e. authentication already succeeded).
pub async fn Connection::bind_resource(
  self : Connection,
  resource? : String = "",
) -> @jid.Jid raise XmppError {
  let advertised = match self.features {
    Some(f) => f
    None => raise XmppError::ProtocolViolation(detail="stream not open")
  }
  if !advertised.bind {
    raise XmppError::ProtocolViolation(detail="server does not offer bind")
  }
  self.iq_counter += 1
  let id = "bind_\{self.iq_counter}"
  let bind_xml = if resource is "" {
    "<bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'/>"
  } else {
    "<bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><resource>\{@xml.escape_text(resource)}</resource></bind>"
  }
  self.send_raw(
    "<iq type='set' id='\{id}' xmlns='jabber:client'>\{bind_xml}</iq>",
  )
  let el = match self.read_incoming() {
    Element(el) => el
    Header(_) =>
      raise XmppError::ProtocolViolation(
        detail="unexpected stream header while binding",
      )
  }
  if el.name != "iq" {
    raise XmppError::ProtocolViolation(
      detail="expected iq reply, got \{el.name}",
    )
  }
  if el.get_attribute("type") != Some("result") {
    self.raise_iq_error(el)
  }
  let bind_child = find_child(el, name="bind")
  let jid_text = match bind_child {
    Some(b) => find_child(b, name="jid")
    None => None
  }
  let full = match jid_text {
    Some(j) => j.get_text()
    None =>
      raise XmppError::ProtocolViolation(
        detail="bind result without a jid element",
      )
  }
  let jid = @jid.Jid::parse(full) catch {
    err =>
      raise XmppError::ProtocolViolation(
        detail="server returned invalid jid: \{Repr(err)}",
      )
  }
  self.bound = Some(jid)
  jid
}

///|
fn find_child(
  el : @XMLParser.XMLElement,
  name~ : String,
) -> @XMLParser.XMLElement? {
  for child in el.get_children() {
    guard child is @XMLParser.XMLChildren::Element(e) else { continue }
    if e.name == name {
      return Some(e)
    }
  }
  None
}

///|
fn Connection::raise_iq_error(
  self : Connection,
  el : @XMLParser.XMLElement,
) -> Unit raise XmppError {
  let _ = self
  for child in el.get_children() {
    guard child is @XMLParser.XMLChildren::Element(e) else { continue }
    if e.name is "error" {
      let stanza_error = StanzaError::parse(e)
      let text_part = match stanza_error.text {
        Some(t) => ": \{t}"
        None => ""
      }
      raise XmppError::ProtocolViolation(
        detail="iq error \{Repr(stanza_error.condition)}\{text_part}",
      )
    }
  }
  raise XmppError::ProtocolViolation(detail="iq error without an error element")
}
