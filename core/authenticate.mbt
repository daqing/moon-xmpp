///|
/// Authenticate with the server (RFC 6120 §6) and restart the stream.
/// With no explicit mechanism the best advertised one is selected
/// (SCRAM-SHA-256, SCRAM-SHA-1, then PLAIN). PLAIN is refused on
/// unencrypted streams.
pub async fn Connection::authenticate(
  self : Connection,
  jid~ : String,
  password~ : String,
  mechanism? : String? = None,
) -> Features raise XmppError {
  let advertised = match self.features {
    Some(f) => f
    None => raise XmppError::ProtocolViolation(detail="stream not open")
  }
  let chosen = match mechanism {
    Some(m) => {
      if !contains(advertised.mechanisms, m) {
        raise XmppError::Auth(detail="server does not offer \{m}")
      }
      Some(m)
    }
    None => select_mechanism(features=advertised, encrypted=self.is_encrypted())
  }
  let mech = match chosen {
    Some(m) => m
    None => raise XmppError::Auth(detail="no supported mechanism offered")
  }
  let reply = match mech {
    "PLAIN" => {
      if !self.is_encrypted() {
        raise XmppError::Auth(detail="PLAIN requires an encrypted stream")
      }
      let payload = @sasl.plain(authcid=jid, password~) catch {
        err => raise XmppError::Auth(detail="\{Repr(err)}")
      }
      self.sasl_auth(mechanism="PLAIN", initial=payload)
    }
    other => raise XmppError::Auth(detail="mechanism not implemented: \{other}")
  }
  match reply {
    Success(_) => ()
    Challenge(_) =>
      // PLAIN has no challenge round; an empty-challenge reply is answered
      // with an empty response, as some servers do.
      match self.sasl_respond(payload="") {
        Success(_) => ()
        Challenge(_) =>
          raise XmppError::ProtocolViolation(
            detail="server sent a second challenge for PLAIN",
          )
      }
  }
  self.restart_stream(domain=self.domain())
}

///|
fn Connection::domain(self : Connection) -> String raise XmppError {
  match self.domain {
    Some(d) => d
    None => raise XmppError::ProtocolViolation(detail="stream not open")
  }
}

///|
fn contains(arr : Array[String], s : String) -> Bool {
  for item in arr {
    if item == s {
      return true
    }
  }
  false
}
