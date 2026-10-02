///|
/// Stanza error types from RFC 6120 §8.3.2.
pub(all) enum StanzaErrorType {
  Auth
  Cancel
  Continue
  Modify
  Wait
  Unknown(String)
} derive(Eq, Debug)

///|
pub extend StanzaErrorType with Eq::{not_equal, equal}

///|
pub extend StanzaErrorType with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Stanza error conditions from RFC 6120 §8.3.3.
pub(all) suberror StanzaErrorCondition {
  BadRequest
  Conflict
  FeatureNotImplemented
  Forbidden
  Gone
  InternalServerError
  ItemNotFound
  JidMalformed
  NotAcceptable
  NotAllowed
  NotAuthorized
  PolicyViolation
  RecipientUnavailable
  Redirect(uri~ : String)
  RegistrationRequired
  RemoteServerNotFound
  RemoteServerTimeout
  ResourceConstraint
  ServiceUnavailable
  SubscriptionRequired
  UndefinedCondition
  UnexpectedRequest
  Unknown(String)
} derive(Eq, Debug)

///|
pub extend StanzaErrorCondition with Eq::{not_equal, equal}

///|
pub extend StanzaErrorCondition with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A parsed stanza error (RFC 6120 §8.3).
pub struct StanzaError {
  error_type : StanzaErrorType
  condition : StanzaErrorCondition
  text : String?
} derive(Eq, Debug)

///|
pub extend StanzaError with Eq::{not_equal, equal}

///|
pub extend StanzaError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Parse the `<error/>` child of a stanza.
pub fn StanzaError::parse(
  el : @XMLParser.XMLElement,
) -> StanzaError raise XmppError {
  let error_type = match el.get_attribute("type") {
    Some("auth") => StanzaErrorType::Auth
    Some("cancel") => Cancel
    Some("continue") => Continue
    Some("modify") => Modify
    Some("wait") => Wait
    Some(other) => Unknown(other)
    None =>
      raise XmppError::ProtocolViolation(detail="stanza error without type")
  }
  let mut condition : StanzaErrorCondition = UndefinedCondition
  let mut text : String? = None
  let mut seen = false
  for child in el.get_children() {
    guard child is @XMLParser.XMLChildren::Element(item) else { continue }
    if item.name is "text" {
      text = Some(item.get_text())
    } else if !seen {
      condition = stanza_error_condition(item)
      seen = true
    }
  }
  { error_type, condition, text, }
}

///|
fn stanza_error_condition(el : @XMLParser.XMLElement) -> StanzaErrorCondition {
  match el.name {
    "bad-request" => BadRequest
    "conflict" => Conflict
    "feature-not-implemented" => FeatureNotImplemented
    "forbidden" => Forbidden
    "gone" => Gone
    "internal-server-error" => InternalServerError
    "item-not-found" => ItemNotFound
    "jid-malformed" => JidMalformed
    "not-acceptable" => NotAcceptable
    "not-allowed" => NotAllowed
    "not-authorized" => NotAuthorized
    "policy-violation" => PolicyViolation
    "recipient-unavailable" => RecipientUnavailable
    "redirect" => Redirect(uri=el.get_text())
    "registration-required" => RegistrationRequired
    "remote-server-not-found" => RemoteServerNotFound
    "remote-server-timeout" => RemoteServerTimeout
    "resource-constraint" => ResourceConstraint
    "service-unavailable" => ServiceUnavailable
    "subscription-required" => SubscriptionRequired
    "undefined-condition" => UndefinedCondition
    "unexpected-request" => UnexpectedRequest
    _ => Unknown(el.name)
  }
}
