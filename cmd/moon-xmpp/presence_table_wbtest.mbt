///|
fn available_presence(from : String) -> @core.Presence raise {
  {
    from: Some(@jid.Jid::parse(from)),
    presence_type: None,
    show: None,
    status: None,
  }
}

///|
fn unavailable_presence(from : String) -> @core.Presence raise {
  {
    from: Some(@jid.Jid::parse(from)),
    presence_type: Some("unavailable"),
    show: None,
    status: None,
  }
}

///|
test "available presence marks the contact online" {
  let table = PresenceTable::new()
  assert_false(table.is_online("bob@example.com"))
  table.apply(available_presence("bob@example.com/phone"))
  assert_true(table.is_online("bob@example.com"))
  assert_eq(table.resources("bob@example.com"), ["bob@example.com/phone"])
  table.apply(available_presence("bob@example.com/laptop"))
  assert_eq(table.resources("bob@example.com").length(), 2)
}

///|
test "a contact stays online while any resource is available" {
  let table = PresenceTable::new()
  table.apply(available_presence("bob@example.com/phone"))
  table.apply(available_presence("bob@example.com/laptop"))
  table.apply(unavailable_presence("bob@example.com/phone"))
  assert_true(table.is_online("bob@example.com"))
  assert_eq(table.resources("bob@example.com"), ["bob@example.com/laptop"])
  table.apply(unavailable_presence("bob@example.com/laptop"))
  assert_false(table.is_online("bob@example.com"))
  assert_eq(table.resources("bob@example.com").length(), 0)
}

///|
test "unavailable from a bare jid takes the whole account offline" {
  let table = PresenceTable::new()
  table.apply(available_presence("bob@example.com/phone"))
  table.apply(available_presence("bob@example.com/laptop"))
  table.apply(unavailable_presence("bob@example.com"))
  assert_false(table.is_online("bob@example.com"))
  assert_eq(table.resources("bob@example.com").length(), 0)
}

///|
test "a show value such as dnd still counts as online" {
  let table = PresenceTable::new()
  table.apply({
    from: Some(@jid.Jid::parse("bob@example.com/phone")),
    presence_type: None,
    show: Some("dnd"),
    status: Some("Busy"),
  })
  assert_true(table.is_online("bob@example.com"))
}

///|
test "error presence and presence without a from are ignored" {
  let table = PresenceTable::new()
  table.apply({
    from: Some(@jid.Jid::parse("bob@example.com")),
    presence_type: Some("error"),
    show: None,
    status: None,
  })
  table.apply({ from: None, presence_type: None, show: None, status: None, })
  assert_false(table.is_online("bob@example.com"))
  assert_eq(table.resources("bob@example.com").length(), 0)
}
