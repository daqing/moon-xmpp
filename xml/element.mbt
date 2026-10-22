///|
/// A parsed XML element. Names keep their prefixes (e.g. `stream:features`);
/// matching is done on those literal names.
pub(all) struct XMLElement {
  name : String
  empty_element : Bool
  attributes : Map[String, String]
  children : Array[XMLChildren]
}

///|
/// The content of an element: child elements plus the character-data,
/// reference, comment, and processing-instruction nodes a pull parser emits.
pub(all) enum XMLChildren {
  Element(XMLElement)
  CDATA(String)
  PI(String)
  Comment(String)
  Text(String)
  WhiteSpace(String)
}

///|
/// Look up an attribute by its literal (possibly prefixed) name.
pub fn XMLElement::get_attribute(self : XMLElement, attr : String) -> String? {
  self.attributes.get(attr)
}

///|
/// Concatenate the character data of an element. Whitespace-only text nodes
/// are skipped, so callers get the meaningful content of leaf elements
/// (mechanism names, JIDs, error text) without surrounding indentation.
pub fn XMLElement::get_text(self : XMLElement) -> String {
  self.children.fold(init="", fn(str, child) {
    match child {
      Text(text) => str + text
      _ => str
    }
  })
}

///|
/// The child nodes of an element, in document order.
pub fn XMLElement::get_children(self : XMLElement) -> Array[XMLChildren] {
  self.children
}
