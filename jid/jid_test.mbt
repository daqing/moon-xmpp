///|
test "parse full jid" {
  let j = @jid.Jid::parse("user@example.com/laptop")
  assert_eq(j.localpart, Some("user"))
  assert_eq(j.domainpart, "example.com")
  assert_eq(j.resourcepart, Some("laptop"))
}

///|
test "parse bare domain jid" {
  let j = @jid.Jid::parse("example.com")
  assert_eq(j.localpart, None)
  assert_eq(j.domainpart, "example.com")
  assert_eq(j.resourcepart, None)
}

///|
test "parse domain jid with resource" {
  let j = @jid.Jid::parse("example.com/res")
  assert_eq(j.localpart, None)
  assert_eq(j.resourcepart, Some("res"))
}

///|
test "separators inside resourcepart" {
  let j = @jid.Jid::parse("user@example.com/office/2nd floor@x")
  assert_eq(j.resourcepart, Some("office/2nd floor@x"))
  let j2 = @jid.Jid::parse("example.com/res@x")
  assert_eq(j2.localpart, None)
  assert_eq(j2.resourcepart, Some("res@x"))
}

///|
test "slash before at means no localpart" {
  let j = @jid.Jid::parse("example.com/user@host")
  assert_eq(j.domainpart, "example.com")
  assert_eq(j.localpart, None)
  assert_eq(j.resourcepart, Some("user@host"))
}

///|
test "to_string roundtrip" {
  let j = @jid.Jid::parse("user@example.com/laptop")
  assert_eq(j.to_string(), "user@example.com/laptop")
  assert_eq(@jid.Jid::parse(j.to_string()), j)
  assert_eq(@jid.Jid::parse("example.com").to_string(), "example.com")
  assert_eq(@jid.Jid::bare(j), @jid.Jid::parse("user@example.com"))
}

///|
test "rejects empty parts" {
  try @jid.Jid::parse("") catch {
    err => assert_true(err == @jid.JidError::MissingDomainpart)
  } noraise {
    _ => fail("expected error")
  }
  try @jid.Jid::parse("user@") catch {
    err => assert_true(err == @jid.JidError::MissingDomainpart)
  } noraise {
    _ => fail("expected error")
  }
  try @jid.Jid::parse("/resource") catch {
    err => assert_true(err == @jid.JidError::MissingDomainpart)
  } noraise {
    _ => fail("expected error")
  }
  try @jid.Jid::parse("@example.com") catch {
    err => assert_true(err == @jid.JidError::EmptyPart(part="localpart"))
  } noraise {
    _ => fail("expected error")
  }
  try @jid.Jid::parse("user@example.com/") catch {
    err => assert_true(err == @jid.JidError::EmptyPart(part="resourcepart"))
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "rejects forbidden characters" {
  try @jid.Jid::parse("us\"er@example.com") catch {
    err =>
      assert_true(err == @jid.JidError::InvalidChar(part="localpart", char='"'))
  } noraise {
    _ => fail("expected error")
  }
  try @jid.Jid::parse("us:er@example.com") catch {
    err =>
      assert_true(err == @jid.JidError::InvalidChar(part="localpart", char=':'))
  } noraise {
    _ => fail("expected error")
  }
  try @jid.Jid::parse("us\ner@example.com") catch {
    err =>
      assert_true(
        err == @jid.JidError::InvalidChar(part="localpart", char='\n'),
      )
  } noraise {
    _ => fail("expected error")
  }
  try @jid.Jid::parse("user@exa mple.com") catch {
    err =>
      assert_true(
        err == @jid.JidError::InvalidChar(part="domainpart", char=' '),
      )
  } noraise {
    _ => fail("expected error")
  }
  try @jid.Jid::parse("user@exa_mple.com") catch {
    err =>
      assert_true(
        err == @jid.JidError::InvalidChar(part="domainpart", char='_'),
      )
  } noraise {
    _ => fail("expected error")
  }
  try @jid.Jid::parse("user@example.com/a\nb") catch {
    err =>
      assert_true(
        err == @jid.JidError::InvalidChar(part="resourcepart", char='\n'),
      )
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "accepts ipv6 and non-ascii domainparts" {
  assert_eq(@jid.Jid::parse("[::1]").domainpart, "[::1]")
  assert_eq(@jid.Jid::parse("[2001:db8::1]").domainpart, "[2001:db8::1]")
  assert_eq(@jid.Jid::parse("用例.测试").domainpart, "用例.测试")
  try @jid.Jid::parse("[::1") catch {
    err =>
      assert_true(
        err == @jid.JidError::InvalidChar(part="domainpart", char='['),
      )
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "rejects over-long parts" {
  try @jid.Jid::parse("a".repeat(1024) + "@example.com") catch {
    err => assert_true(err == @jid.JidError::TooLong(part="localpart"))
  } noraise {
    _ => fail("expected error")
  }
  assert_eq(
    @jid.Jid::parse("a".repeat(1023) + "@example.com").localpart,
    Some("a".repeat(1023)),
  )
  try @jid.Jid::parse("example.com/" + "r".repeat(1024)) catch {
    err => assert_true(err == @jid.JidError::TooLong(part="resourcepart"))
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "length counts utf-8 bytes" {
  assert_eq(
    @jid.Jid::parse("用".repeat(300) + "@example.com").domainpart,
    "example.com",
  )
  try @jid.Jid::parse("用".repeat(400) + "@example.com") catch {
    err => assert_true(err == @jid.JidError::TooLong(part="localpart"))
  } noraise {
    _ => fail("expected error")
  }
}
