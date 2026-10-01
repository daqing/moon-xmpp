///|
pub struct Jid {
  localpart : String?
  domainpart : String
  resourcepart : String?
} derive(Eq, Debug)

///|
pub extend Jid with Eq::{not_equal, equal}

///|
pub extend Jid with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Parse a JID of the form [localpart@]domainpart[/resourcepart] and
/// validate it against RFC 8264.
pub fn Jid::parse(s : String) -> Jid raise JidError {
  let mut at = -1
  let mut slash = -1
  for i in 0..<s.length() {
    let u = s[i].to_int()
    if u == 0x2f {
      slash = i
      break
    }
    if u == 0x40 && at < 0 {
      at = i
    }
  }
  let prefix : String = if slash < 0 { s } else { s[0:slash].to_owned() }
  let resourcepart : String? = if slash < 0 {
    None
  } else {
    Some(s[slash + 1:].to_owned())
  }
  let localpart : String? = if at < 0 {
    None
  } else {
    Some(prefix[0:at].to_owned())
  }
  let domainpart : String = if at < 0 {
    prefix
  } else {
    prefix[at + 1:].to_owned()
  }
  if s is "" || domainpart is "" {
    raise JidError::MissingDomainpart
  }
  if localpart is Some("") {
    raise JidError::EmptyPart(part="localpart")
  }
  if resourcepart is Some("") {
    raise JidError::EmptyPart(part="resourcepart")
  }
  match localpart {
    Some(l) => validate_part(l, part="localpart", is_local=true)
    None => ()
  }
  validate_domainpart(domainpart)
  match resourcepart {
    Some(r) => validate_part(r, part="resourcepart", is_local=false)
    None => ()
  }
  { localpart, domainpart, resourcepart, }
}

///|
/// Return the JID without its resourcepart.
pub fn Jid::bare(self : Jid) -> Jid {
  {
    localpart: self.localpart,
    domainpart: self.domainpart,
    resourcepart: None,
  }
}

///|
/// Return the string form of the JID.
pub fn Jid::to_string(self : Jid) -> String {
  let prefix = match self.localpart {
    Some(l) => "\{l}@"
    None => ""
  }
  let suffix = match self.resourcepart {
    Some(r) => "/\{r}"
    None => ""
  }
  prefix + self.domainpart + suffix
}

///|
fn validate_part(
  s : String,
  part~ : String,
  is_local~ : Bool,
) -> Unit raise JidError {
  for c in s {
    let n = c.to_int()
    if n < 0x20 || n == 0x7f {
      raise JidError::InvalidChar(part~, char=c)
    }
    if is_local && c is ('"' | '&' | '\'' | '/' | ':' | '<' | '>' | '@') {
      raise JidError::InvalidChar(part~, char=c)
    }
  }
  if @utf8.encode(s).length() > 1023 {
    raise JidError::TooLong(part~)
  }
}

///|
fn validate_domainpart(s : String) -> Unit raise JidError {
  if s.has_prefix("[") {
    if !s.has_suffix("]") {
      raise JidError::InvalidChar(part="domainpart", char='[')
    }
    let inner = s[1:s.length() - 1].to_owned()
    for c in inner {
      if !(c is ('0'..='9' | 'a'..='f' | 'A'..='F' | ':' | '.')) {
        raise JidError::InvalidChar(part="domainpart", char=c)
      }
    }
  } else {
    for c in s {
      let n = c.to_int()
      if n < 0x20 || n == 0x7f {
        raise JidError::InvalidChar(part="domainpart", char=c)
      } else if n < 0x80 {
        if !(c is ('0'..='9' | 'a'..='z' | 'A'..='Z' | '-' | '.')) {
          raise JidError::InvalidChar(part="domainpart", char=c)
        }
      }
    }
  }
  if @utf8.encode(s).length() > 1023 {
    raise JidError::TooLong(part="domainpart")
  }
}
