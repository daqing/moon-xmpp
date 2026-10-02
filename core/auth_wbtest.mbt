///|
test "select_mechanism prefers strongest" {
  let f = {
    starttls: false,
    starttls_required: false,
    mechanisms: ["PLAIN", "SCRAM-SHA-1", "SCRAM-SHA-256"],
    bind: false,
  }
  assert_eq(select_mechanism(features=f, encrypted=true), Some("SCRAM-SHA-256"))
  assert_eq(
    select_mechanism(features=f, encrypted=false),
    Some("SCRAM-SHA-256"),
  )
  let f2 = {
    starttls: false,
    starttls_required: false,
    mechanisms: ["PLAIN", "SCRAM-SHA-1"],
    bind: false,
  }
  assert_eq(select_mechanism(features=f2, encrypted=true), Some("SCRAM-SHA-1"))
}

///|
test "select_mechanism refuses PLAIN on plaintext" {
  let f = {
    starttls: false,
    starttls_required: false,
    mechanisms: ["PLAIN"],
    bind: false,
  }
  assert_eq(select_mechanism(features=f, encrypted=false), None)
  assert_eq(select_mechanism(features=f, encrypted=true), Some("PLAIN"))
}

///|
test "select_mechanism handles unknown mechanisms" {
  let f = {
    starttls: false,
    starttls_required: false,
    mechanisms: ["X-OAUTH", "ANONYMOUS"],
    bind: false,
  }
  assert_eq(select_mechanism(features=f, encrypted=true), None)
  let f2 = {
    starttls: false,
    starttls_required: false,
    mechanisms: ["X-OAUTH", "SCRAM-SHA-1-PLUS"],
    bind: false,
  }
  assert_eq(
    select_mechanism(features=f2, encrypted=true),
    Some("SCRAM-SHA-1-PLUS"),
  )
}
