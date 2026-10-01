///|
pub(all) suberror JidError {
  MissingDomainpart
  EmptyPart(part~ : String)
  InvalidChar(part~ : String, char~ : Char)
  TooLong(part~ : String)
} derive(Eq, Debug)

///|
pub extend JidError with Eq::{not_equal, equal}

///|
pub extend JidError with @moonbitlang/core/debug.Debug::{to_repr}
