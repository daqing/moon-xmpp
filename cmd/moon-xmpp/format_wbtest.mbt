///|
test "chat messages render as [from] body" {
  let msg : @core.ChatMessage = {
    from: Some(@jid.Jid::parse("bob@example.com")),
    id: Some("a1"),
    body: Some("got it"),
  }
  assert_eq(format_chat(msg), "[bob@example.com] got it")
  let bodyless : @core.ChatMessage = { from: None, id: None, body: None, }
  assert_eq(format_chat(bodyless), "[(unknown)] ")
}

///|
test "presence renders with type and status" {
  let p : @core.Presence = {
    from: Some(@jid.Jid::parse("alice@example.com")),
    presence_type: Some("unavailable"),
    status: Some("brb"),
  }
  assert_eq(format_presence(p), "* alice@example.com is unavailable: brb")
  let plain : @core.Presence = {
    from: None,
    presence_type: None,
    status: None,
  }
  assert_eq(format_presence(plain), "* (unknown) is available")
}
