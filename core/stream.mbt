///|
pub struct StreamHeader {
  id : String
  from : String?
  version : String
} derive(Eq, Debug)

///|
pub extend StreamHeader with Eq::{not_equal, equal}

///|
pub extend StreamHeader with @moonbitlang/core/debug.Debug::{to_repr}

///|
priv enum Incoming {
  Header(String)
  Element(@XMLParser.XMLElement)
}

///|
/// Build the client's opening stream header (RFC 6120 §4.7).
fn build_stream_header(domain : String) -> String {
  "<?xml version='1.0'?><stream:stream xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams' to='\{domain}' version='1.0'>"
}

///|
/// Parse the server's response stream header. The root tag never closes, so
/// it is parsed with a synthetic closing tag.
fn parse_stream_header(root : String) -> StreamHeader raise XmppError {
  let el = @xml.parse_element(root + "></stream:stream>") catch {
    err =>
      raise XmppError::ProtocolViolation(
        detail="malformed stream header: \{Repr(err)}",
      )
  }
  match el.get_attribute("xmlns:stream") {
    Some("http://etherx.jabber.org/streams") => ()
    Some(other) =>
      raise XmppError::ProtocolViolation(
        detail="unexpected stream namespace \{other}",
      )
    None =>
      raise XmppError::ProtocolViolation(
        detail="missing stream namespace declaration",
      )
  }
  match el.get_attribute("version") {
    Some("1.0") => ()
    Some(other) =>
      raise XmppError::ProtocolViolation(
        detail="unsupported stream version \{other}",
      )
    None =>
      raise XmppError::ProtocolViolation(detail="stream header without version")
  }
  match el.get_attribute("id") {
    Some(id) => { id, from: el.get_attribute("from"), version: "1.0", }
    None =>
      raise XmppError::ProtocolViolation(detail="stream header without id")
  }
}

///|
async fn Connection::read_incoming(
  self : Connection,
) -> Incoming raise XmppError {
  for ;; {
    if self.frame_pos >= self.frames.length() {
      self.frames.clear()
      self.frame_pos = 0
      for frame in self.pump() {
        self.frames.push(frame)
      }
    }
    let frame = self.frames[self.frame_pos]
    self.frame_pos += 1
    match frame {
      @xml.Frame::Root(text) => return Header(text)
      @xml.Frame::Stanza(text) => {
        let el = @xml.parse_element(text) catch {
          err =>
            raise XmppError::ProtocolViolation(
              detail="malformed stanza: \{Repr(err)}",
            )
        }
        if el.name is "stream:error" {
          let (condition, error_text) = parse_stream_error(el)
          raise XmppError::StreamError(condition~, text=error_text)
        }
        return Element(el)
      }
      @xml.Frame::StreamEnd => raise XmppError::ConnectionClosed
    }
  }
}

///|
/// Open the XML stream and return the server's advertised features.
pub async fn Connection::open_stream(
  self : Connection,
  domain~ : String,
) -> Features raise XmppError {
  self.send_raw(build_stream_header(domain))
  match self.read_incoming() {
    Header(text) => self.stream_header = Some(parse_stream_header(text))
    Element(_) =>
      raise XmppError::ProtocolViolation(detail="expected stream header")
  }
  match self.read_incoming() {
    Element(el) =>
      if el.name is "stream:features" {
        parse_features(el)
      } else {
        raise XmppError::ProtocolViolation(
          detail="expected stream:features, got \{el.name}",
        )
      }
    Header(_) =>
      raise XmppError::ProtocolViolation(
        detail="unexpected second stream header",
      )
  }
}

///|
/// Restart the XML stream (after TLS or SASL negotiation) and return the
/// server's advertised features.
pub async fn Connection::restart_stream(
  self : Connection,
  domain~ : String,
) -> Features raise XmppError {
  self.byte_stream.reset()
  self.frames.clear()
  self.frame_pos = 0
  self.open_stream(domain~)
}
