///|
pub(all) suberror XmppError {
  ConnectionClosed
  StreamError(condition~ : String)
  ProtocolViolation(detail~ : String)
} derive(Eq, Debug)

///|
pub extend XmppError with Eq::{not_equal, equal}

///|
pub extend XmppError with @moonbitlang/core/debug.Debug::{to_repr}
