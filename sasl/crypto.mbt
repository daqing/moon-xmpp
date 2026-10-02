///|
/// Hash algorithm used by a SCRAM mechanism.
pub(all) enum ScramAlg {
  Sha1
  Sha256
} derive(Eq, Debug)

///|
pub extend ScramAlg with Eq::{not_equal, equal}

///|
pub extend ScramAlg with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Hash `data` with the algorithm's plain hash function.
pub fn hash_bytes(alg~ : ScramAlg, data : Bytes) -> FixedArray[Byte] {
  match alg {
    Sha1 => @crypto.sha1(data)
    Sha256 => @crypto.sha256(data)
  }
}

///|
/// HMAC (RFC 2104) computed from the plain hash function:
/// H((K ^ opad) || H((K ^ ipad) || m)). Both SHA-1 and SHA-256 use a
/// 64-byte block.
pub fn hmac_bytes(
  alg~ : ScramAlg,
  key~ : Bytes,
  message~ : Bytes,
) -> FixedArray[Byte] {
  let block = 64
  let key_bytes = if key.length() > block {
    fixed_to_bytes(hash_bytes(alg~, key))
  } else {
    key
  }
  let ipad : Array[Byte] = []
  let opad : Array[Byte] = []
  for i in 0..<block {
    let k = if i < key_bytes.length() { key_bytes[i] } else { b'\x00' }
    ipad.push(k ^ b'\x36')
    opad.push(k ^ b'\x5c')
  }
  let inner = hash_bytes(alg~, concat_bytes(Bytes::from_array(ipad), message))
  let inner_bytes = fixed_to_bytes(inner)
  hash_bytes(alg~, concat_bytes(Bytes::from_array(opad), inner_bytes))
}

///|
/// PBKDF2-HMAC with one block (RFC 8018), as used for SCRAM's Hi().
pub fn pbkdf2(
  alg~ : ScramAlg,
  password~ : Bytes,
  salt~ : Bytes,
  iterations~ : Int,
) -> FixedArray[Byte] {
  let first = concat_bytes(
    salt,
    Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x01']),
  )
  let u1 = hmac_bytes(alg~, key=password, message=first)
  let out = array_of_fixed(u1)
  let mut u = u1
  for _ in 1..<iterations {
    u = hmac_bytes(alg~, key=password, message=fixed_to_bytes(u))
    for i in 0..<u.length() {
      out[i] = out[i] ^ u[i]
    }
  }
  FixedArray::from_array(out)
}

///|
/// XOR two equal-length hash outputs byte-wise (used for the SCRAM proof).
pub fn xor_fixed(
  a : FixedArray[Byte],
  b : FixedArray[Byte],
) -> FixedArray[Byte] {
  let out : FixedArray[Byte] = FixedArray::make(a.length(), b'\x00')
  for i in 0..<a.length() {
    out[i] = a[i] ^ b[i]
  }
  out
}

///|
/// Convert a hash output to `Bytes`.
pub fn fixed_to_bytes(f : FixedArray[Byte]) -> Bytes {
  let arr : Array[Byte] = []
  for i in 0..<f.length() {
    arr.push(f[i])
  }
  Bytes::from_array(arr)
}

///|
fn array_of_fixed(f : FixedArray[Byte]) -> Array[Byte] {
  let arr : Array[Byte] = []
  for i in 0..<f.length() {
    arr.push(f[i])
  }
  arr
}

///|
fn concat_bytes(a : Bytes, b : Bytes) -> Bytes {
  let arr : Array[Byte] = []
  for i in 0..<a.length() {
    arr.push(a[i])
  }
  for i in 0..<b.length() {
    arr.push(b[i])
  }
  Bytes::from_array(arr)
}
