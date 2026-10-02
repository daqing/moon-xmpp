///|
/// RFC 5802 §5.1 test vector: user / pencil, SCRAM-SHA-1.
test "rfc5802 sha-1 vector" {
  let nonce = @base64.decode("fyko+d2lbbFgONRv9qkxdawL")
  let (client, first) = @sasl.ScramClient::start(
    alg=@sasl.Sha1,
    username="user",
    password="pencil",
    nonce~,
    gs2="n",
    cb_data=b"",
  )
  assert_eq(first, "n,,n=user,r=fyko+d2lbbFgONRv9qkxdawL")
  let server_first = "r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=QSXCR+Q6sek8bf92,i=4096"
  let final_msg = client.client_final(server_first~)
  assert_eq(
    final_msg, "c=biws,r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,p=v0X8v3Bz2T0CJGbJQyF0X+HI4Ts=",
  )
  client.verify_server_final(server_final="v=rmF9pqV8S7suAoZWja4dJRkFsKQ=")
}

///|
/// RFC 7677 Â§3 test vector: user / pencil, SCRAM-SHA-256.
test "rfc7677 sha-256 vector" {
  let nonce = @base64.decode("rOprNGfwEbeRWgbNEkqO")
  let (client, first) = @sasl.ScramClient::start(
    alg=@sasl.Sha256,
    username="user",
    password="pencil",
    nonce~,
    gs2="n",
    cb_data=b"",
  )
  assert_eq(first, "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
  let server_first = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"
  let final_msg = client.client_final(server_first~)
  assert_eq(
    final_msg, "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=",
  )
  client.verify_server_final(
    server_final="v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=",
  )
}

///|
test "channel binding gs2 lands in first and c=" {
  let cb : Bytes = b"\x01\x02\x03\x04"
  let nonce = @base64.decode("fyko+d2lbbFgONRv9qkxdawL")
  let (client, first) = @sasl.ScramClient::start(
    alg=@sasl.Sha256,
    username="user",
    password="pencil",
    nonce~,
    gs2="p=tls-server-end-point",
    cb_data=cb,
  )
  assert_eq(first, "p=tls-server-end-point,,n=user,r=fyko+d2lbbFgONRv9qkxdawL")
  let server_first = "r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=QSXCR+Q6sek8bf92,i=4096"
  let final_msg = client.client_final(server_first~)
  let raw : Array[Byte] = []
  for b in @utf8.encode("p=tls-server-end-point,,") {
    raw.push(b)
  }
  for b in cb {
    raw.push(b)
  }
  let expected_c = @base64.encode(Bytes::from_array(raw), padding=true)
  assert_eq(test_c_value(final_msg), Some(expected_c))
}

///|
fn test_c_value(final_msg : String) -> String? {
  for part in final_msg.split(",") {
    if part.has_prefix("c=") {
      return Some(part["c=".length():].to_owned())
    }
  }
  None
}

///|
test "rejects bad server signature" {
  let nonce = @base64.decode("fyko+d2lbbFgONRv9qkxdawL")
  let (client, _) = @sasl.ScramClient::start(
    alg=@sasl.Sha1,
    username="user",
    password="pencil",
    nonce~,
    gs2="n",
    cb_data=b"",
  )
  ignore(
    client.client_final(
      server_first="r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=QSXCR+Q6sek8bf92,i=4096",
    ),
  )
  try
    client.verify_server_final(server_final="v=badSignatureAAAAAAAAAAAAAAAAAA=")
  catch {
    err => assert_true(err is @sasl.SaslError::AuthenticationFailed(detail=_))
  } noraise {
    _ => fail("expected failure")
  }
}

///|
test "server error message raises" {
  let nonce = @base64.decode("fyko+d2lbbFgONRv9qkxdawL")
  let (client, _) = @sasl.ScramClient::start(
    alg=@sasl.Sha1,
    username="user",
    password="pencil",
    nonce~,
    gs2="n",
    cb_data=b"",
  )
  try client.verify_server_final(server_final="e=invalid-credential") catch {
    err =>
      assert_true(
        err
        is @sasl.SaslError::AuthenticationFailed(detail="invalid-credential"),
      )
  } noraise {
    _ => fail("expected failure")
  }
}

///|
test "rejects unrelated server nonce" {
  let nonce = @base64.decode("fyko+d2lbbFgONRv9qkxdawL")
  let (client, _) = @sasl.ScramClient::start(
    alg=@sasl.Sha1,
    username="user",
    password="pencil",
    nonce~,
    gs2="n",
    cb_data=b"",
  )
  try
    client.client_final(
      server_first="r=completelyDifferent,s=QSXCR+Q6sek8bf92,i=4096",
    )
  catch {
    err => assert_true(err is @sasl.SaslError::InvalidChallenge(detail=_))
  } noraise {
    _ => fail("expected failure")
  }
}

///|
test "saslname escaping" {
  let nonce = @base64.decode("fyko+d2lbbFgONRv9qkxdawL")
  let (client, first) = @sasl.ScramClient::start(
    alg=@sasl.Sha1,
    username="u=s,er",
    password="pencil",
    nonce~,
    gs2="n",
    cb_data=b"",
  )
  assert_eq(first, "n,,n=u=3Ds=2Cer,r=fyko+d2lbbFgONRv9qkxdawL")
  let _ = client
}
