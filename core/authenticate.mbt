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
    "SCRAM-SHA-1" => self.scram_exchange(mech, alg=@sasl.Sha1, jid~, password~)
    "SCRAM-SHA-256" =>
      self.scram_exchange(mech, alg=@sasl.Sha256, jid~, password~)
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
/// Run a SCRAM exchange for `mech` ("SCRAM-SHA-1" or "SCRAM-SHA-256")
/// without channel binding, and return the server's final message.
#warnings("-alert_internal")
async fn Connection::scram_exchange(
  self : Connection,
  mech : String,
  alg~ : @sasl.ScramAlg,
  jid~ : String,
  password~ : String,
) -> SaslReply raise XmppError {
  let nonce = @tls.rand_bytes(18) catch {
    err => raise XmppError::Io(detail="nonce generation failed: \{Repr(err)}")
  }
  let (client, first) = @sasl.ScramClient::start(
    alg~,
    username=jid,
    password~,
    nonce~,
    gs2="n",
    cb_data=b"",
  )
  let mut reply = self.sasl_auth(mechanism=mech, initial=first)
  for ;; {
    let text = match reply {
      Challenge(encoded) => decode_sasl_payload(encoded)
      Success(encoded) => decode_sasl_payload(encoded)
    }
    match reply {
      Challenge(_) => {
        let final_msg = client.client_final(server_first=text) catch {
          err => raise XmppError::Auth(detail="\{Repr(err)}")
        }
        reply = self.sasl_respond(payload=final_msg)
      }
      Success(_) => {
        client.verify_server_final(server_final=text) catch {
          err => raise XmppError::Auth(detail="\{Repr(err)}")
        }
        return reply
      }
    }
  }
}

///|
/// RFC 6120 §6.4.2 carries SASL payloads base64-encoded inside the
/// challenge/response/success elements.
fn decode_sasl_payload(encoded : String) -> String raise XmppError {
  if encoded is "" {
    return ""
  }
  let bytes = @base64.decode(encoded) catch {
    _ =>
      raise XmppError::ProtocolViolation(
        detail="bad base64 in SASL reply: \{Repr(encoded)}",
      )
  }
  @utf8.decode(bytes) catch {
    _ => raise XmppError::ProtocolViolation(detail="bad utf-8 in SASL reply")
  }
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
