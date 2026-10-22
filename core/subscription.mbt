///|
/// The four presence subscription stanzas (RFC 6121 §3.1): asking for, and
/// granting or revoking, authorization to see a contact's presence.
pub(all) enum PresenceSubscription {
  Subscribe
  Subscribed
  Unsubscribe
  Unsubscribed
} derive(Eq, Debug)

///|
pub extend PresenceSubscription with Eq::{not_equal, equal}

///|
pub extend PresenceSubscription with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An inbound presence subscription stanza. `from` is the contact whose
/// authorization state is changing.
pub(all) struct SubscriptionRequest {
  kind : PresenceSubscription
  from : @jid.Jid?
  status : String?
} derive(Eq, Debug)

///|
pub extend SubscriptionRequest with Eq::{not_equal, equal}

///|
pub extend SubscriptionRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The subscription action carried by a presence stanza's `type`, if any.
fn parse_subscription_kind(el : @xml.XMLElement) -> PresenceSubscription? {
  match el.get_attribute("type") {
    Some("subscribe") => Some(Subscribe)
    Some("subscribed") => Some(Subscribed)
    Some("unsubscribe") => Some(Unsubscribe)
    Some("unsubscribed") => Some(Unsubscribed)
    _ => None
  }
}

///|
fn parse_subscription_request(
  el : @xml.XMLElement,
  kind~ : PresenceSubscription,
) -> SubscriptionRequest raise XmppError {
  let p = parse_presence(el)
  { kind, from: p.from, status: p.status, }
}

///|
/// The wire value of a subscription stanza's `type` attribute.
fn PresenceSubscription::wire(self : PresenceSubscription) -> String {
  match self {
    Subscribe => "subscribe"
    Subscribed => "subscribed"
    Unsubscribe => "unsubscribe"
    Unsubscribed => "unsubscribed"
  }
}

///|
async fn Connection::send_subscription_presence(
  self : Connection,
  to : String,
  kind : PresenceSubscription,
) -> Unit raise XmppError {
  if !(self.state is (Bound | Online)) {
    raise XmppError::ProtocolViolation(
      detail="presence subscription requires a bound session",
    )
  }
  self.send_raw(
    "<presence to='\{@xml.escape_attr(to)}' type='\{kind.wire()}' xmlns='jabber:client'/>",
  )
}

///|
/// Ask a contact for permission to see their presence (RFC 6121 §3.1.1).
/// The outbound request stays pending (`ask='subscribe'` in the roster)
/// until the contact answers with `subscribed` or `unsubscribed`.
pub async fn Connection::send_subscribe(
  self : Connection,
  to~ : String,
) -> Unit raise XmppError {
  self.send_subscription_presence(to, Subscribe)
}

///|
/// Grant a contact permission to see our presence (RFC 6121 §3.1.3),
/// answering a `subscribe` request.
pub async fn Connection::send_subscribed(
  self : Connection,
  to~ : String,
) -> Unit raise XmppError {
  self.send_subscription_presence(to, Subscribed)
}

///|
/// Stop receiving a contact's presence (RFC 6121 §3.3).
pub async fn Connection::send_unsubscribe(
  self : Connection,
  to~ : String,
) -> Unit raise XmppError {
  self.send_subscription_presence(to, Unsubscribe)
}

///|
/// Refuse a `subscribe` request, or revoke a contact's permission to see our
/// presence (RFC 6121 §3.1.3, §3.3). Clients must decide explicitly rather
/// than auto-answering, so inbound requests are surfaced and never answered
/// by the library itself.
pub async fn Connection::send_unsubscribed(
  self : Connection,
  to~ : String,
) -> Unit raise XmppError {
  self.send_subscription_presence(to, Unsubscribed)
}

///|
/// Receive the next inbound subscription stanza. Chat messages, presence
/// broadcasts, and other stanzas encountered first are skipped; use
/// `recv_stanza` to handle all stanza kinds.
pub async fn Connection::recv_subscription(
  self : Connection,
) -> SubscriptionRequest raise XmppError {
  for ;; {
    match self.recv_stanza() {
      Subscription(req) => return req
      _ => continue
    }
  }
}
