///|
/// Parse one complete stanza into an element tree. Element names keep
/// their prefixes (e.g. `stream:features`); matching is done on those
/// literal names.
pub fn parse_element(s : String) -> @XMLParser.XMLElement raise XmlError {
  match @XMLParser.xml_from_string(s) {
    Some(doc) => doc.root
    None => raise XmlError::Malformed(detail="malformed stanza XML")
  }
}
