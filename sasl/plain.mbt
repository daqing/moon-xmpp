///|
/// Build the PLAIN initial response payload (RFC 4616):
/// base64(authzid NUL authcid NUL password). An empty authzid is allowed
/// and means "derive from the authcid".
pub fn plain(
  authcid~ : String,
  password~ : String,
  authzid? : String = "",
) -> String raise SaslError {
  reject_nul(authzid, field="authzid")
  reject_nul(authcid, field="authcid")
  reject_nul(password, field="password")
  let arr : Array[Byte] = []
  append_utf8(arr, authzid)
  arr.push(b'\x00')
  append_utf8(arr, authcid)
  arr.push(b'\x00')
  append_utf8(arr, password)
  @base64.encode(Bytes::from_array(arr))
}

///|
fn append_utf8(arr : Array[Byte], s : String) -> Unit {
  let bytes = @utf8.encode(s)
  for i in 0..<bytes.length() {
    arr.push(bytes[i])
  }
}

///|
fn reject_nul(s : String, field~ : String) -> Unit raise SaslError {
  for c in s {
    if c.to_int() == 0 {
      raise SaslError::InvalidState(detail="NUL in \{field}")
    }
  }
}
