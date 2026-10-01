///|
pub(all) suberror XmlError {
  UnexpectedEof
  Malformed(detail~ : String)
} derive(Eq, Debug)

///|
pub extend XmlError with Eq::{not_equal, equal}

///|
pub extend XmlError with @moonbitlang/core/debug.Debug::{to_repr}
