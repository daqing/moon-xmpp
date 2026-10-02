///|
test "parse full argument set" {
  let opts = parse_args([
    "--jid", "user@example.com", "--password=secret", "--to", "bob@example.com",
    "--body", "hello world", "--host", "xmpp.example.net", "--port", "5223", "--resource",
    "laptop",
  ])
  assert_eq(opts.jid, "user@example.com")
  assert_eq(opts.password, "secret")
  assert_eq(opts.to, "bob@example.com")
  assert_eq(opts.body, "hello world")
  assert_eq(opts.host, Some("xmpp.example.net"))
  assert_eq(opts.port, Some(5223))
  assert_eq(opts.resource, Some("laptop"))
}

///|
test "bare arguments default to None" {
  let opts = parse_args([
    "--jid", "user@example.com", "--password", "s", "--to", "b@e.com", "--body",
    "x",
  ])
  assert_eq(opts.host, None)
  assert_eq(opts.port, None)
  assert_eq(opts.resource, None)
  assert_eq(host_for(opts), "example.com")
}

///|
test "host override wins over the jid domain" {
  let opts = parse_args([
    "--jid", "user@example.com", "--password", "s", "--to", "b@e.com", "--body",
    "x", "--host", "dial.example.net",
  ])
  assert_eq(host_for(opts), "dial.example.net")
}

///|
test "missing required arguments raise" {
  try parse_args(["--jid", "user@example.com"]) catch {
    CliError::MissingArg(name=nm) => assert_eq(nm, "--password")
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected error")
  }
  try parse_args([]) catch {
    CliError::MissingArg(name=nm) => assert_eq(nm, "--jid")
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "unknown flag and bad port raise" {
  try parse_args(["--frobnicate"]) catch {
    CliError::UnknownArg(arg=a) => assert_eq(a, "--frobnicate")
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected error")
  }
  try parse_args(["--port", "notanumber"]) catch {
    CliError::BadPort(value=v) => assert_eq(v, "notanumber")
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected error")
  }
}

///|
test "value forms are equivalent" {
  let a = parse_args([
    "--jid=user@example.com", "--password=p", "--to=t@e.com", "--body=b",
  ])
  let b = parse_args([
    "--jid", "user@example.com", "--password", "p", "--to", "t@e.com", "--body",
    "b",
  ])
  assert_eq(a, b)
}

///|
test "usage mentions every flag" {
  let u = usage()
  assert_true(u.contains("--jid"))
  assert_true(u.contains("--password"))
  assert_true(u.contains("--to"))
  assert_true(u.contains("--body"))
  assert_true(u.contains("--host"))
  assert_true(u.contains("--port"))
  assert_true(u.contains("--resource"))
}

///|
test "flag at the end without a value raises" {
  try
    parse_args([
      "--jid", "u@e.com", "--password", "p", "--to", "t@e.com", "--body", "b", "--port",
    ])
  catch {
    CliError::MissingArg(name=nm) => assert_eq(nm, "--port")
    _ => fail("wrong error")
  } noraise {
    _ => fail("expected error")
  }
}
