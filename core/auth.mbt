///|
/// A SASL server message during negotiation (RFC 6120 §6.4.2).
pub(all) enum SaslReply {
  Challenge(String)
  Success(String)
} derive(Eq, Debug)

///|
pub extend SaslReply with Eq::{not_equal, equal}

///|
pub extend SaslReply with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// SASL failure conditions from RFC 6120 §6.5.3.
pub(all) suberror SaslFailureCondition {
  Aborted
  AccountDisabled
  CredentialsExpired
  EncryptionRequired
  IncorrectEncoding
  InvalidAuthzid
  InvalidCredential
  InvalidMechanism
  InvalidSaslState
  NotAuthorized
  PolicyViolation
  TemporaryAuthFailure
  Unknown(String)
} derive(Eq, Debug)

///|
pub extend SaslFailureCondition with Eq::{not_equal, equal}

///|
pub extend SaslFailureCondition with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Pick the best mechanism the server offers: SCRAM-SHA-256, then
/// SCRAM-SHA-1, then PLAIN. PLAIN is only usable on an encrypted stream.
pub fn select_mechanism(features~ : Features, encrypted~ : Bool) -> String? {
  let preferred = [
    "SCRAM-SHA-256", "SCRAM-SHA-1", "SCRAM-SHA-256-PLUS", "SCRAM-SHA-1-PLUS", "PLAIN",
  ]
  let mut best : String? = None
  let mut best_rank = preferred.length()
  for m in features.mechanisms {
    let rank = index_of(preferred, m)
    if rank < best_rank {
      if m is "PLAIN" && !encrypted {
        continue
      }
      best = Some(m)
      best_rank = rank
    }
  }
  best
}

///|
fn index_of(arr : Array[String], s : String) -> Int {
  let mut i = 0
  for item in arr {
    if item == s {
      return i
    }
    i += 1
  }
  arr.length()
}

///|
/// Send `<auth/>` with the chosen mechanism and initial response, then read
/// the server's reply. Also usable to drive custom SASL mechanisms.
pub async fn Connection::sasl_auth(
  self : Connection,
  mechanism~ : String,
  initial~ : String,
) -> SaslReply raise XmppError {
  let payload = if initial is "" { "" } else { initial }
  self.send_raw(
    "<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='\{@xml.escape_attr(mechanism)}'>\{payload}</auth>",
  )
  self.read_sasl_reply()
}

///|
/// Respond to a challenge with `<response/>`, then read the server's reply.
/// Also usable to drive custom SASL mechanisms.
pub async fn Connection::sasl_respond(
  self : Connection,
  payload~ : String,
) -> SaslReply raise XmppError {
  self.send_raw(
    "<response xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>\{payload}</response>",
  )
  self.read_sasl_reply()
}

///|
/// Read one SASL message: challenge, success, or failure. SASL elements are
/// read byte-wise from the raw transport so that bytes the server coalesced
/// after `</success>` stay buffered for the restarted stream.
async fn Connection::read_sasl_reply(
  self : Connection,
) -> SaslReply raise XmppError {
  for ;; {
    let text = self.read_raw_element()
    let el = @xml.parse_element(text) catch {
      err =>
        raise XmppError::ProtocolViolation(
          detail="malformed SASL element: \{Repr(err)}",
        )
    }
    match el.name {
      "challenge" => return Challenge(el.get_text())
      "success" => {
        self.byte_stream.reset()
        self.frames.clear()
        self.frame_pos = 0
        return Success(el.get_text())
      }
      "failure" => {
        let (condition, text) = parse_sasl_failure(el)
        let detail = match text {
          Some(t) => "\{Repr(condition)}: \{t}"
          None => "\{Repr(condition)}"
        }
        raise XmppError::Auth(detail~)
      }
      other =>
        raise XmppError::ProtocolViolation(
          detail="unexpected <\{other}> during SASL",
        )
    }
  }
}

///|
/// Read one XML element byte-by-byte from the raw transport. Used for
/// protocol messages that must not be consumed by the stream framer
/// (STARTTLS proceed/failure, SASL challenge/success/failure), so that any
/// bytes the server sent after the element stay buffered for the next
/// protocol stage. Depth counting handles nested children; quotes keep
/// `>` inside attribute values from confusing the scan.
pub async fn Connection::read_raw_element(
  self : Connection,
) -> String raise XmppError {
  let buf : Array[Byte] = []
  let mut depth = 0
  let mut tag_start = 0
  let mut in_tag = false
  let mut in_quote = false
  let mut quote = 0
  for ;; {
    let chunk = match self.transport {
      Tcp(tcp) =>
        tcp.read_some(max_len=1) catch {
          err => raise XmppError::Io(detail="read failed: \{Repr(err)}")
        }
      Tls(tls, _) =>
        tls.read_some(max_len=1) catch {
          err => raise XmppError::Io(detail="read failed: \{Repr(err)}")
        }
    }
    match chunk {
      None => raise XmppError::ConnectionClosed
      Some(data) => {
        if data.length() == 0 {
          continue
        }
        let b = data[0]
        let n = b.to_int()
        buf.push(b)
        let pos = buf.length() - 1
        if in_quote {
          if n == quote {
            in_quote = false
          }
          continue
        }
        if in_tag {
          if n == 0x27 || n == 0x22 {
            in_quote = true
            quote = n
          } else if n == 0x3e {
            let is_closing = buf[tag_start + 1] == b'/'
            let self_closing = buf[pos - 1] == b'/'
            if is_closing {
              depth -= 1
            } else if !self_closing {
              depth += 1
            }
            in_tag = false
            if depth == 0 {
              return @utf8.decode(Bytes::from_array(buf)) catch {
                _ =>
                  raise XmppError::ProtocolViolation(
                    detail="invalid utf-8 in raw element",
                  )
              }
            }
          }
          continue
        }
        if n == 0x3c {
          in_tag = true
          tag_start = pos
        }
      }
    }
  }
}

///|
fn parse_sasl_failure(
  el : @XMLParser.XMLElement,
) -> (SaslFailureCondition, String?) {
  let mut condition : SaslFailureCondition = Unknown("missing-condition")
  let mut text : String? = None
  let mut seen = false
  for child in el.get_children() {
    guard child is @XMLParser.XMLChildren::Element(item) else { continue }
    if item.name is "text" {
      text = Some(item.get_text())
    } else if !seen {
      condition = sasl_failure_condition(item)
      seen = true
    }
  }
  (condition, text)
}

///|
fn sasl_failure_condition(el : @XMLParser.XMLElement) -> SaslFailureCondition {
  match el.name {
    "aborted" => Aborted
    "account-disabled" => AccountDisabled
    "credentials-expired" => CredentialsExpired
    "encryption-required" => EncryptionRequired
    "incorrect-encoding" => IncorrectEncoding
    "invalid-authzid" => InvalidAuthzid
    "invalid-credentials" => InvalidCredential
    "invalid-mechanism" => InvalidMechanism
    "invalid-sasl-state" => InvalidSaslState
    "not-authorized" => NotAuthorized
    "policy-violation" => PolicyViolation
    "temporary-auth-failure" => TemporaryAuthFailure
    _ => Unknown(el.name)
  }
}
