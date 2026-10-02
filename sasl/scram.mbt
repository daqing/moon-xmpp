///|
/// A SCRAM client conversation (RFC 5802). Start with `ScramClient::start`,
/// feed each server challenge to `client_final`, and verify the server's
/// final message with `verify_server_final`.
pub struct ScramClient {
  priv alg : ScramAlg
  priv gs2 : String
  priv cb_data : Bytes
  priv client_nonce : String
  priv client_first_bare : String
  priv password : String
  priv mut auth_message : String?
  priv mut salted : FixedArray[Byte]?
}

///|
/// Begin a SCRAM exchange. `nonce` should come from a CSPRNG (18 random
/// bytes); `gs2` is "n" (no channel binding), "y" (binding supported but
/// unused), or "p=<binding-name>"; `cb_data` is the channel binding data
/// (empty unless gs2 starts with "p=").
pub fn ScramClient::start(
  alg~ : ScramAlg,
  username~ : String,
  password~ : String,
  nonce~ : Bytes,
  gs2~ : String,
  cb_data~ : Bytes,
) -> (ScramClient, String) {
  let client_nonce = @base64.encode(nonce)
  let bare = "n=\{saslname_escape(username)},r=\{client_nonce}"
  let client = {
    alg,
    gs2,
    cb_data,
    client_nonce,
    client_first_bare: bare,
    password,
    auth_message: None,
    salted: None,
  }
  (client, "\{gs2},,\{bare}")
}

///|
/// Process the server-first message and produce the client-final message.
pub fn ScramClient::client_final(
  self : ScramClient,
  server_first~ : String,
) -> String raise SaslError {
  let server_nonce = attr_value(server_first, key="r") catch {
    _ => raise SaslError::InvalidChallenge(detail="missing r= in challenge")
  }
  let salt_b64 = attr_value(server_first, key="s") catch {
    _ => raise SaslError::InvalidChallenge(detail="missing s= in challenge")
  }
  let iterations = attr_value(server_first, key="i") catch {
    _ => raise SaslError::InvalidChallenge(detail="missing i= in challenge")
  }
  if !server_nonce.has_prefix(self.client_nonce) {
    raise SaslError::InvalidChallenge(
      detail="server nonce does not extend the client nonce",
    )
  }
  let iter = @string.parse_int(iterations) catch {
    _ => raise SaslError::InvalidChallenge(detail="invalid i= in challenge")
  }
  if iter <= 0 {
    raise SaslError::InvalidChallenge(detail="non-positive i= in challenge")
  }
  let salt = @base64.decode(salt_b64) catch {
    _ => raise SaslError::InvalidChallenge(detail="invalid s= in challenge")
  }
  let c_b64 = @base64.encode(
    concat_bytes(@utf8.encode("\{self.gs2},,"), self.cb_data),
    padding=true,
  )
  let final_without_proof = "c=\{c_b64},r=\{server_nonce}"
  let auth_message = "\{self.client_first_bare},\{server_first},\{final_without_proof}"
  let salted = pbkdf2(
    alg=self.alg,
    password=@utf8.encode(self.password),
    salt~,
    iterations=iter,
  )
  let client_key = hmac_bytes(
    alg=self.alg,
    key=fixed_to_bytes(salted),
    message=@utf8.encode("Client Key"),
  )
  let stored_key = hash_bytes(alg=self.alg, fixed_to_bytes(client_key))
  let client_signature = hmac_bytes(
    alg=self.alg,
    key=fixed_to_bytes(stored_key),
    message=@utf8.encode(auth_message),
  )
  let proof = xor_fixed(client_key, client_signature)
  self.auth_message = Some(auth_message)
  self.salted = Some(salted)
  "\{final_without_proof},p=\{@base64.encode(fixed_to_bytes(proof), padding=true)}"
}

///|
/// Verify the server-final message: either an error (e=...) or a proof
/// (v=...) that the server knew the password.
pub fn ScramClient::verify_server_final(
  self : ScramClient,
  server_final~ : String,
) -> Unit raise SaslError {
  let err = attr_value(server_final, key="e") catch { _ => "" }
  if err != "" {
    raise SaslError::AuthenticationFailed(detail=err)
  }
  let v = attr_value(server_final, key="v") catch {
    _ => raise SaslError::InvalidChallenge(detail="missing v= in server-final")
  }
  let auth_message = match self.auth_message {
    Some(m) => m
    None => raise SaslError::InvalidState(detail="verify before client_final")
  }
  let salted = match self.salted {
    Some(s) => s
    None => raise SaslError::InvalidState(detail="verify before client_final")
  }
  let server_key = hmac_bytes(
    alg=self.alg,
    key=fixed_to_bytes(salted),
    message=@utf8.encode("Server Key"),
  )
  let server_signature = hmac_bytes(
    alg=self.alg,
    key=fixed_to_bytes(server_key),
    message=@utf8.encode(auth_message),
  )
  let expected = @base64.encode(fixed_to_bytes(server_signature), padding=true)
  if expected != v {
    raise SaslError::AuthenticationFailed(detail="server signature mismatch")
  }
}

///|
/// Escape a username for use as a SCRAM saslname (RFC 5802 §5.1).
fn saslname_escape(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    if c is '=' {
      buf.write_string("=3D")
    } else if c is ',' {
      buf.write_string("=2C")
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Read the value of `key=` from a comma-separated SCRAM attribute list.
fn attr_value(msg : String, key~ : String) -> String raise SaslError {
  for part in msg.split(",") {
    if part.has_prefix("\{key}=") {
      return part[1 + key.length():].to_owned()
    }
  }
  raise SaslError::InvalidChallenge(detail="attribute \{key}= not found")
}
