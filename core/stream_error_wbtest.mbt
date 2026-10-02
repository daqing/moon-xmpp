///|
test "parse stream error with text" {
  let el = @xml.parse_element(
    "<stream:error><see-other-host>other.example.com:5222</see-other-host><text xml:lang='en' xmlns='urn:ietf:params:xml:ns:xmpp-streams'>moved</text></stream:error>",
  )
  let (condition, text) = parse_stream_error(el)
  assert_true(
    condition ==
    StreamErrorCondition::SeeOtherHost(host="other.example.com:5222"),
  )
  assert_eq(text, Some("moved"))
}

///|
test "parse plain and unknown stream errors" {
  let el = @xml.parse_element("<stream:error><system-shutdown/></stream:error>")
  let (condition, text) = parse_stream_error(el)
  assert_true(condition == StreamErrorCondition::SystemShutdown)
  assert_eq(text, None)
  let el2 = @xml.parse_element(
    "<stream:error><weird-condition/></stream:error>",
  )
  let (condition2, _) = parse_stream_error(el2)
  assert_true(condition2 == StreamErrorCondition::Unknown("weird-condition"))
}
