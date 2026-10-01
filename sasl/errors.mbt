///|
pub(all) suberror SaslError {
  InvalidState(detail~ : String)
  InvalidChallenge(detail~ : String)
  AuthenticationFailed(detail~ : String)
} derive(Eq, Debug)

///|
pub extend SaslError with Eq::{not_equal, equal}

///|
pub extend SaslError with @moonbitlang/core/debug.Debug::{to_repr}
