///|
/// Parse one complete stanza into an element tree. Element names keep
/// their prefixes (e.g. `stream:features`); matching is done on those
/// literal names.
pub fn parse_element(s : String) -> XMLElement raise XmlError {
  let reader = @xmlpull.Reader::from_string(s)
  // A synthetic root collects the real root element so that the code below
  // has a parent to attach top-level nodes to.
  let stack : Array[XMLElement] = [
    { name: "", empty_element: false, attributes: Map([]), children: [], },
  ]
  for ;; {
    let event = reader.read_event() catch {
      err => raise XmlError::Malformed(detail=err.to_string())
    }
    match event.kind {
      @xmlpull.EventKind::Start(e) =>
        stack.push({
          name: e.name,
          empty_element: false,
          attributes: attribute_map(e.attributes),
          children: [],
        })
      @xmlpull.EventKind::Empty(e) =>
        append_element(stack, {
          name: e.name,
          empty_element: true,
          attributes: attribute_map(e.attributes),
          children: [],
        })
      @xmlpull.EventKind::End(_) => {
        if stack.length() <= 1 {
          raise XmlError::Malformed(detail="unbalanced closing tag")
        }
        append_element(stack, stack.pop().unwrap())
      }
      @xmlpull.EventKind::Text(t) => append_child(stack, text_child(t))
      @xmlpull.EventKind::CData(t) => append_child(stack, XMLChildren::CDATA(t))
      @xmlpull.EventKind::Comment(t) =>
        append_child(stack, XMLChildren::Comment(t))
      @xmlpull.EventKind::PI(target~, data~) =>
        append_child(
          stack,
          XMLChildren::PI(if data == "" { target } else { "\{target} \{data}" }),
        )
      @xmlpull.EventKind::Eof => break
      _ => ()
    }
  }
  match stack[0].children {
    [XMLChildren::Element(el)] => el
    _ => raise XmlError::Malformed(detail="malformed stanza XML")
  }
}

///|
fn attribute_map(
  attributes : Array[@xmlpull.XmlAttribute],
) -> Map[String, String] {
  let map : Map[String, String] = Map([])
  for attr in attributes {
    map.set(attr.name, attr.value)
  }
  map
}

///|
fn text_child(text : String) -> XMLChildren {
  if text.iter().all(is_xml_whitespace) {
    XMLChildren::WhiteSpace(text)
  } else {
    XMLChildren::Text(text)
  }
}

///|
fn is_xml_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
fn append_child(stack : Array[XMLElement], child : XMLChildren) -> Unit {
  stack[stack.length() - 1].children.push(child)
}

///|
fn append_element(stack : Array[XMLElement], el : XMLElement) -> Unit {
  stack[stack.length() - 1].children.push(XMLChildren::Element(el))
}
