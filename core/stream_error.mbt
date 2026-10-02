///|
/// Stream error conditions from RFC 6120 §4.9.3.
pub(all) suberror StreamErrorCondition {
  BadFormat
  BadNamespacePrefix
  Conflict
  ConnectionTimeout
  HostGone
  HostUnknown
  ImproperAddressing
  InternalServerError
  InvalidFrom
  InvalidNamespace
  InvalidXml
  NotAuthorized
  PolicyViolation
  RemoteConnectionFailed
  Reset
  ResourceConstraint
  RestrictedXml
  SeeOtherHost(host~ : String)
  SystemShutdown
  UndefinedCondition
  UnsupportedEncoding
  UnsupportedStanzaType
  UnsupportedVersion
  Unknown(String)
} derive(Eq, Debug)

///|
pub extend StreamErrorCondition with Eq::{not_equal, equal}

///|
pub extend StreamErrorCondition with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Parse a `<stream:error/>` element into its condition and optional text.
fn parse_stream_error(
  el : @XMLParser.XMLElement,
) -> (StreamErrorCondition, String?) {
  let mut condition : StreamErrorCondition = UndefinedCondition
  let mut text : String? = None
  let mut seen = false
  for child in el.get_children() {
    guard child is @XMLParser.XMLChildren::Element(item) else { continue }
    if item.name is "text" {
      text = Some(item.get_text())
    } else if !seen {
      condition = stream_error_condition(item)
      seen = true
    }
  }
  (condition, text)
}

///|
fn stream_error_condition(el : @XMLParser.XMLElement) -> StreamErrorCondition {
  match el.name {
    "bad-format" => BadFormat
    "bad-namespace-prefix" => BadNamespacePrefix
    "conflict" => Conflict
    "connection-timeout" => ConnectionTimeout
    "host-gone" => HostGone
    "host-unknown" => HostUnknown
    "improper-addressing" => ImproperAddressing
    "internal-server-error" => InternalServerError
    "invalid-from" => InvalidFrom
    "invalid-namespace" => InvalidNamespace
    "invalid-xml" => InvalidXml
    "not-authorized" => NotAuthorized
    "policy-violation" => PolicyViolation
    "remote-connection-failed" => RemoteConnectionFailed
    "reset" => Reset
    "resource-constraint" => ResourceConstraint
    "restricted-xml" => RestrictedXml
    "see-other-host" => SeeOtherHost(host=el.get_text())
    "system-shutdown" => SystemShutdown
    "undefined-condition" => UndefinedCondition
    "unsupported-encoding" => UnsupportedEncoding
    "unsupported-stanza-type" => UnsupportedStanzaType
    "unsupported-version" => UnsupportedVersion
    _ => Unknown(el.name)
  }
}
