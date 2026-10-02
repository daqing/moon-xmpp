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
