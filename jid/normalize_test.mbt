///|
test "case mapping applies to localpart and domainpart" {
  let j = @jid.Jid::parse("UsEr@ExAmPlE.CoM")
  assert_eq(j.localpart, Some("user"))
  assert_eq(j.domainpart, "example.com")
}

///|
test "fullwidth forms are width-mapped" {
  let j = @jid.Jid::parse("ＵＳＥＲ@example.com")
  assert_eq(j.localpart, Some("user"))
  try
    @jid.Jid::parse("ｕｓｅｒ＠ｅｘａｍｐｌｅ．ｃｏｍ")
  catch {
    err =>
      // the fullwidth @ is not a separator; after width mapping the
      // domainpart contains an ASCII @ and is rejected
      assert_true(
        err == @jid.JidError::InvalidChar(part="domainpart", char='@'),
      )
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "nfkc folding" {
  assert_eq(@jid.Jid::parse("ﬁ@example.com").localpart, Some("fi"))
  assert_eq(@jid.Jid::parse("①@example.com").localpart, Some("1"))
}

///|
test "resourcepart keeps its case but is width-mapped" {
  let j = @jid.Jid::parse("user@example.com/Ｒes")
  assert_eq(j.resourcepart, Some("Res"))
  let j2 = @jid.Jid::parse("user@example.com/ReS")
  assert_eq(j2.resourcepart, Some("ReS"))
}

///|
test "width map removes zero-width code points" {
  let j = @jid.Jid::parse("us­er@example.com")
  assert_eq(j.localpart, Some("user"))
}
