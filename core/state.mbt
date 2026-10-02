///|
/// Session lifecycle of a connection (RFC 6120 §5, §7 and RFC 6121 §4.2):
/// connecting → negotiating-tls → authenticating → bound → online.
/// `Online` is entered once initial presence has been sent.
pub(all) enum ConnectionState {
  Connecting
  NegotiatingTls
  Authenticating
  Bound
  Online
} derive(Eq, Debug)

///|
pub extend ConnectionState with Eq::{not_equal, equal}

///|
pub extend ConnectionState with @moonbitlang/core/debug.Debug::{to_repr}
