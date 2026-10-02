///|
/// A complete top-level piece of an XML stream.
pub(all) enum Frame {
  Root(String)
  Stanza(String)
  StreamEnd
} derive(Eq, Debug)

///|
pub extend Frame with Eq::{not_equal, equal}

///|
pub extend Frame with @moonbitlang/core/debug.Debug::{to_repr}

///|
priv enum ScanState {
  Text
  TagStart
  Tag
  Bang
  CommentStart
  Comment
  CDataC
  CDataD
  CDataA
  CDataT
  CDataA2
  CDataBracket
  CData
  PI
}

///|
/// Split an XMPP XML stream into complete top-level pieces. The stream root
/// never closes, so its opening tag is reported as a `Root` frame, each
/// top-level child as a `Stanza` frame, and the closing root tag as
/// `StreamEnd`. After `StreamEnd` the framer is reusable for a stream
/// restart (TLS and SASL each restart the stream).
pub struct Framer {
  priv buf : StringBuilder
  priv name_buf : StringBuilder
  priv open_tags : Array[String]
  priv mut state : ScanState
  priv mut quote : Char?
  priv mut closing : Bool
  priv mut name_done : Bool
  priv mut self_closing : Bool
  priv mut dashes : Int
  priv mut brackets : Int
  priv mut question : Int
  priv mut accumulating : Bool
}

///|
pub fn Framer::new() -> Framer {
  {
    buf: StringBuilder(),
    name_buf: StringBuilder(),
    open_tags: [],
    state: Text,
    quote: None,
    closing: false,
    name_done: false,
    self_closing: false,
    dashes: 0,
    brackets: 0,
    question: 0,
    accumulating: false,
  }
}

///|
/// Feed one chunk of stream text and return the frames completed by it.
pub fn Framer::push(
  self : Framer,
  chunk : String,
) -> Array[Frame] raise XmlError {
  let frames : Array[Frame] = []
  for c in chunk {
    match self.state {
      Text => self.scan_text(c)
      TagStart => self.scan_tag_start(c)
      Tag => self.scan_tag(c, frames)
      Bang => self.scan_bang(c)
      CommentStart => self.scan_comment_start(c)
      Comment => self.scan_comment(c)
      CDataC => self.scan_cdata_expected(c, 'C', CDataD)
      CDataD => self.scan_cdata_expected(c, 'D', CDataA)
      CDataA => self.scan_cdata_expected(c, 'A', CDataT)
      CDataT => self.scan_cdata_expected(c, 'T', CDataA2)
      CDataA2 => self.scan_cdata_expected(c, 'A', CDataBracket)
      CDataBracket => self.scan_cdata_expected(c, '[', CData)
      CData => self.scan_cdata(c)
      PI => self.scan_pi(c)
    }
  }
  frames
}

///|
/// Reset the framer to its initial state, for a stream restart.
pub fn Framer::reset(self : Framer) -> Unit {
  self.buf.reset()
  self.name_buf.reset()
  self.open_tags.clear()
  self.state = Text
  self.quote = None
  self.closing = false
  self.name_done = false
  self.self_closing = false
  self.dashes = 0
  self.brackets = 0
  self.question = 0
  self.accumulating = false
}

///|
/// Drop the buffered markup when a comment, PI, or stray tag completes
/// outside of a stanza.
fn Framer::end_markup(self : Framer) -> Unit {
  if self.open_tags.length() < 2 {
    self.buf.reset()
    self.accumulating = false
  }
}

///|
fn Framer::scan_text(self : Framer, c : Char) -> Unit raise XmlError {
  if !self.accumulating && c is (' ' | '\t' | '\n' | '\r') {
    return
  }
  if c is '<' {
    self.accumulating = true
    self.buf.write_char(c)
    self.name_buf.reset()
    self.state = TagStart
    return
  }
  if !self.accumulating {
    raise XmlError::Malformed(detail="unexpected character outside of markup")
  }
  self.buf.write_char(c)
}

///|
fn Framer::scan_tag_start(self : Framer, c : Char) -> Unit raise XmlError {
  self.buf.write_char(c)
  if c is '/' {
    self.closing = true
    self.name_done = false
    self.state = Tag
    return
  }
  if c is '!' {
    self.state = Bang
    return
  }
  if c is '?' {
    self.question = 0
    self.state = PI
    return
  }
  if c is ('<' | '>' | ' ' | '\t' | '\n' | '\r') {
    raise XmlError::Malformed(detail="invalid tag name")
  }
  self.name_buf.reset()
  self.name_buf.write_char(c)
  self.closing = false
  self.name_done = false
  self.self_closing = false
  self.quote = None
  self.state = Tag
}

///|
fn Framer::scan_tag(
  self : Framer,
  c : Char,
  frames : Array[Frame],
) -> Unit raise XmlError {
  self.buf.write_char(c)
  if !self.name_done {
    if c is (' ' | '\t' | '\n' | '\r') {
      self.name_done = true
      return
    }
    if c is '/' {
      if self.closing {
        raise XmlError::Malformed(detail="unexpected / in closing tag")
      }
      self.self_closing = true
      self.name_done = true
      return
    }
    if c is '>' {
      self.finish_tag(frames)
      return
    }
    if c is '<' {
      raise XmlError::Malformed(detail="unexpected < inside tag")
    }
    self.name_buf.write_char(c)
    return
  }
  if self.quote is Some(q) {
    if c == q {
      self.quote = None
    }
    return
  }
  if c is ('"' | '\'') {
    self.quote = Some(c)
    return
  }
  if c is '/' {
    self.self_closing = true
    return
  }
  if c is '>' {
    self.finish_tag(frames)
    return
  }
  if c is '<' {
    raise XmlError::Malformed(detail="unexpected < inside tag")
  }
}

///|
fn Framer::finish_tag(
  self : Framer,
  frames : Array[Frame],
) -> Unit raise XmlError {
  let name = self.name_buf.to_string()
  self.state = Text
  if name is "" {
    raise XmlError::Malformed(detail="empty tag name")
  }
  if self.closing {
    match self.open_tags.pop() {
      None =>
        raise XmlError::Malformed(
          detail="closing tag </\{name}> without an opening tag",
        )
      Some(open_name) =>
        if open_name != name {
          raise XmlError::Malformed(
            detail="mismatched </\{name}> for <\{open_name}>",
          )
        }
    }
    if self.open_tags.is_empty() {
      frames.push(StreamEnd)
      self.reset()
    } else if self.open_tags.length() == 1 {
      frames.push(Stanza(self.buf.to_string()))
      self.buf.reset()
      self.accumulating = false
    }
    return
  }
  if self.self_closing {
    if self.open_tags.length() == 1 {
      frames.push(Stanza(self.buf.to_string()))
      self.buf.reset()
      self.accumulating = false
    } else if self.open_tags.is_empty() {
      self.end_markup()
    }
    return
  }
  self.open_tags.push(name)
  if self.open_tags.length() == 1 {
    frames.push(Root(self.buf.to_string()))
    self.buf.reset()
    self.accumulating = false
  } else {
    self.accumulating = true
  }
}

///|
fn Framer::scan_bang(self : Framer, c : Char) -> Unit raise XmlError {
  self.buf.write_char(c)
  if c is '-' {
    self.state = CommentStart
  } else if c is '[' {
    self.state = CDataC
  } else {
    raise XmlError::Malformed(detail="unsupported markup declaration")
  }
}

///|
fn Framer::scan_comment_start(self : Framer, c : Char) -> Unit raise XmlError {
  self.buf.write_char(c)
  if c is '-' {
    self.dashes = 0
    self.state = Comment
  } else {
    raise XmlError::Malformed(detail="invalid comment")
  }
}

///|
fn Framer::scan_comment(self : Framer, c : Char) -> Unit {
  self.buf.write_char(c)
  if c is '-' {
    self.dashes += 1
  } else if c is '>' && self.dashes >= 2 {
    self.end_markup()
    self.dashes = 0
    self.state = Text
  } else {
    self.dashes = 0
  }
}

///|
fn Framer::scan_cdata_expected(
  self : Framer,
  c : Char,
  expect : Char,
  next : ScanState,
) -> Unit raise XmlError {
  self.buf.write_char(c)
  if c == expect {
    self.state = next
  } else {
    raise XmlError::Malformed(detail="invalid CDATA section")
  }
}

///|
fn Framer::scan_cdata(self : Framer, c : Char) -> Unit {
  self.buf.write_char(c)
  if c is ']' {
    self.brackets += 1
  } else if c is '>' && self.brackets >= 2 {
    self.end_markup()
    self.brackets = 0
    self.state = Text
  } else {
    self.brackets = 0
  }
}

///|
fn Framer::scan_pi(self : Framer, c : Char) -> Unit {
  self.buf.write_char(c)
  if c is '?' {
    self.question += 1
  } else if c is '>' && self.question >= 1 {
    self.end_markup()
    self.question = 0
    self.state = Text
  } else {
    self.question = 0
  }
}
