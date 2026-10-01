///|
test "escape_text" {
  assert_eq(@xml.escape_text("a<b>&c"), "a&lt;b&gt;&amp;c")
  assert_eq(@xml.escape_text("plain"), "plain")
}

///|
test "escape_attr" {
  assert_eq(
    @xml.escape_attr("he said \"hi\" & left"),
    "he said &quot;hi&quot; &amp; left",
  )
  assert_eq(@xml.escape_attr("it's"), "it&apos;s")
}
