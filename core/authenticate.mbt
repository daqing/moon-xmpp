///|
/// Authenticate with the server (RFC 6120 §6) and restart the stream.
/// With no explicit mechanism the best advertised one is selected
/// (SCRAM-SHA-256, SCRAM-SHA-1, then PLAIN; -PLUS variants first when
/// `channel_binding` is set). PLAIN is refused on unencrypted streams.
/// Channel binding uses tls-server-end-point (RFC 5929).
pub async fn Connection::authenticate(
  self : Connection,
  jid~ : String,
  password~ : String,
  mechanism? : String? = None,
  channel_binding? : Bool = false,
) -> Features raise XmppError {
  let advertised = match self.features {
    Some(f) => f
    None => raise XmppError::ProtocolViolation(detail="stream not open")
  }
  if !(self.state is (Connecting | NegotiatingTls)) {
    raise XmppError::ProtocolViolation(
      detail="authentication already finished for this session",
    )
  }
  self.state = Authenticating
  let chosen = match mechanism {
    Some(m) => {
      if !contains(advertised.mechanisms, m) {
        raise XmppError::Auth(detail="server does not offer \{m}")
      }
      Some(m)
    }
    None =>
      select_mechanism(
        features=advertised,
        encrypted=self.is_encrypted(),
        channel_binding~,
      )
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
    "SCRAM-SHA-1" =>
      self.scram_exchange(mech, alg=@sasl.Sha1, jid~, password~, plus=false)
    "SCRAM-SHA-256" =>
      self.scram_exchange(mech, alg=@sasl.Sha256, jid~, password~, plus=false)
    "SCRAM-SHA-1-PLUS" =>
      self.scram_exchange(mech, alg=@sasl.Sha1, jid~, password~, plus=true)
    "SCRAM-SHA-256-PLUS" =>
      self.scram_exchange(mech, alg=@sasl.Sha256, jid~, password~, plus=true)
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
  plus~ : Bool,
) -> SaslReply raise XmppError {
  let nonce = @tls.rand_bytes(18) catch {
    err => raise XmppError::Io(detail="nonce generation failed: \{Repr(err)}")
  }
  let (gs2, cb_data) : (String, Bytes) = if plus {
    if !self.is_encrypted() {
      raise XmppError::Auth(
        detail="channel binding requires an encrypted stream",
      )
    }
    let cb = self.server_end_point_binding()
    ("p=tls-server-end-point", cb)
  } else {
    ("n", b"")
  }
  // XMPP servers expect the SCRAM username to be the localpart of the
  // JID (nodeprep rejects "@")
  let parsed = @jid.Jid::parse(jid) catch {
    err =>
      raise XmppError::ProtocolViolation(
        detail="invalid jid for authentication: \{Repr(err)}",
      )
  }
  let username = match parsed.localpart {
    Some(l) => l
    None => jid
  }
  let (client, first) = @sasl.ScramClient::start(
    alg~,
    username~,
    password~,
    nonce~,
    gs2~,
    cb_data~,
  )
  // SASL payloads are base64 without padding (RFC 4422); Prosody rejects
  // padded ones with incorrect-encoding
  let mut reply = self.sasl_auth(
    mechanism=mech,
    initial=@base64.encode(@utf8.encode(first)),
  )
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
        reply = self.sasl_respond(
          payload=@base64.encode(@utf8.encode(final_msg)),
        )
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
/// The tls-server-end-point channel binding data (RFC 5929): the SHA-256
/// hash of the server certificate in DER form. For modern certificates the
/// signature hash is SHA-256 anyway; MD5/SHA-1 certs also map to SHA-256.
#warnings("-alert_internal")
fn Connection::server_end_point_binding(
  self : Connection,
) -> Bytes raise XmppError {
  let der = match self.transport {
    Tls(tls, _) =>
      tls.get_peer_certificate() catch {
        err => raise XmppError::Io(detail="peer certificate: \{Repr(err)}")
      }
    Tcp(_) =>
      raise XmppError::Auth(
        detail="channel binding requires an encrypted stream",
      )
  }
  match der {
    Some(cert) => {
      let hashed = @sasl.hash_bytes(alg=@sasl.Sha256, cert)
      @sasl.fixed_to_bytes(hashed)
    }
    None =>
      raise XmppError::ProtocolViolation(detail="no peer certificate on TLS")
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
