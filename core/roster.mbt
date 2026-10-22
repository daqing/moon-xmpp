///|
/// The roster namespace (RFC 6121 §2.1.2).
const ROSTER_NS : String = "jabber:iq:roster"

///|
/// Subscription state of a roster item (RFC 6121 §2.1.2.5): `SubTo` means
/// we receive the contact's presence, `SubFrom` means the contact receives
/// ours, `SubBoth` means both. `SubRemove` only ever appears in a roster
/// push announcing that the item left the roster.
pub(all) enum Subscription {
  SubNone
  SubTo
  SubFrom
  SubBoth
  SubRemove
} derive(Eq, Debug)

///|
pub extend Subscription with Eq::{not_equal, equal}

///|
pub extend Subscription with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Parse the wire value of the `subscription` attribute. Unknown values are
/// treated as `SubNone`.
fn parse_subscription(value : String) -> Subscription {
  match value {
    "to" => SubTo
    "from" => SubFrom
    "both" => SubBoth
    "remove" => SubRemove
    _ => SubNone
  }
}

///|
/// A roster item (RFC 6121 §2.1.2): a contact, its authorization state, and
/// the groups it belongs to.
pub(all) struct RosterItem {
  jid : @jid.Jid
  name : String?
  subscription : Subscription
  ask : String?
  groups : Array[String]
} derive(Eq, Debug)

///|
pub extend RosterItem with Eq::{not_equal, equal}

///|
pub extend RosterItem with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Find the `jabber:iq:roster` query child of an iq element.
fn roster_query(el : @xml.XMLElement) -> @xml.XMLElement? {
  match find_child(el, name="query") {
    Some(q) =>
      match q.get_attribute("xmlns") {
        Some(ns) if ns == ROSTER_NS => Some(q)
        _ => None
      }
    None => None
  }
}

///|
/// Parse every `<item/>` of a roster query. Unknown attributes and child
/// elements are ignored (RFC 6121 §2.1.2 permits both).
fn parse_roster_items(
  query : @xml.XMLElement,
) -> Array[RosterItem] raise XmppError {
  let items : Array[RosterItem] = []
  for child in query.get_children() {
    guard child is @xml.XMLChildren::Element(el) else { continue }
    if el.name != "item" {
      continue
    }
    let jid_text = match el.get_attribute("jid") {
      Some(j) => j
      None =>
        raise XmppError::ProtocolViolation(
          detail="roster item without a jid attribute",
        )
    }
    let jid = @jid.Jid::parse(jid_text) catch {
      err =>
        raise XmppError::ProtocolViolation(
          detail="roster item with an invalid jid: \{Repr(err)}",
        )
    }
    let subscription = match el.get_attribute("subscription") {
      Some(s) => parse_subscription(s)
      None => SubNone
    }
    let groups : Array[String] = []
    for group in el.get_children() {
      guard group is @xml.XMLChildren::Element(g) else { continue }
      if g.name is "group" {
        groups.push(element_text(g))
      }
    }
    items.push({
      jid,
      name: el.get_attribute("name"),
      subscription,
      ask: el.get_attribute("ask"),
      groups,
    })
  }
  items
}

///|
/// Replace the cached entry for `item`'s bare JID, or drop it from the cache
/// when the push announced a removal. Roster pushes are authoritative
/// (RFC 6121 §2.1.6).
fn Connection::apply_roster_push(self : Connection, item : RosterItem) -> Unit {
  let bare = item.jid.bare().to_string()
  let updated : Array[RosterItem] = []
  let mut found = false
  for existing in self.roster {
    if existing.jid.bare().to_string() == bare {
      found = true
      if item.subscription != SubRemove {
        updated.push(item)
      }
    } else {
      updated.push(existing)
    }
  }
  if !found && item.subscription != SubRemove {
    updated.push(item)
  }
  self.roster = updated
}

///|
/// Handle an inbound iq. A `type='set'` roster push is acknowledged and
/// applied to the cache; returns the push so callers can observe it. Any
/// other iq returns None and is left to the caller.
async fn Connection::handle_iq(
  self : Connection,
  el : @xml.XMLElement,
) -> IncomingStanza? raise XmppError {
  if el.get_attribute("type") != Some("set") {
    return None
  }
  let query = match roster_query(el) {
    Some(q) => q
    None => return None
  }
  let item = match parse_roster_items(query).get(0) {
    Some(i) => i
    None => return None
  }
  let id = el.get_attribute("id").unwrap_or("")
  self.send_raw("<iq type='result' id='\{@xml.escape_attr(id)}'/>")
  self.apply_roster_push(item)
  Some(RosterPush(item))
}

///|
/// Await the `result` iq with the given id. Roster pushes arriving in the
/// meantime are acknowledged and applied; other stanzas are queued so the
/// streaming API keeps them (RFC 6121 §2.1.1 the reply may interleave with
/// arbitrary traffic).
async fn Connection::await_iq(
  self : Connection,
  id : String,
) -> @xml.XMLElement raise XmppError {
  for ;; {
    let el = match self.read_incoming() {
      Element(el) => el
      Header(_) =>
        raise XmppError::ProtocolViolation(
          detail="unexpected stream header while awaiting an iq reply",
        )
    }
    if el.name is "iq" {
      let matching = match el.get_attribute("id") {
        Some(rid) => rid == id
        None => false
      }
      if matching {
        if el.get_attribute("type") != Some("result") {
          self.raise_iq_error(el)
        }
        return el
      }
      ignore(self.handle_iq(el))
      continue
    }
    self.pending.push(classify_stanza(el))
  }
}

///|
/// Fetch the full roster (RFC 6121 §2.1.1) and replace the local cache.
/// Requires a bound session; the server answers with one `<item/>` per
/// contact.
pub async fn Connection::get_roster(
  self : Connection,
) -> Array[RosterItem] raise XmppError {
  if !(self.state is (Bound | Online)) {
    raise XmppError::ProtocolViolation(
      detail="roster management requires a bound session",
    )
  }
  self.iq_counter += 1
  let id = "roster_\{self.iq_counter}"
  self.send_raw(
    "<iq type='get' id='\{id}' xmlns='jabber:client'><query xmlns='\{ROSTER_NS}'/></iq>",
  )
  let el = self.await_iq(id)
  let query = match roster_query(el) {
    Some(q) => q
    None =>
      raise XmppError::ProtocolViolation(
        detail="roster result without a roster query",
      )
  }
  let items = parse_roster_items(query)
  self.roster = items
  items
}

///|
/// The roster as last fetched or pushed. Empty until `get_roster` runs.
pub fn Connection::roster(self : Connection) -> Array[RosterItem] {
  self.roster
}

///|
/// Compose a roster `<item/>` for a set request.
fn build_roster_item(
  jid : String,
  name : String?,
  groups : Array[String],
  remove : Bool,
) -> String {
  let buf = StringBuilder()
  buf.write_string("<item jid='")
  buf.write_string(@xml.escape_attr(jid))
  buf.write_string("'")
  match name {
    Some(n) => {
      buf.write_string(" name='")
      buf.write_string(@xml.escape_attr(n))
      buf.write_string("'")
    }
    None => ()
  }
  if remove {
    buf.write_string(" subscription='remove'")
  }
  if groups.length() == 0 {
    buf.write_string("/>")
  } else {
    buf.write_string(">")
    for group in groups {
      buf.write_string("<group>")
      buf.write_string(@xml.escape_text(group))
      buf.write_string("</group>")
    }
    buf.write_string("</item>")
  }
  buf.to_string()
}

///|
/// Send a roster set request for one item and update the cache from the
/// server's push (RFC 6121 §2.1.3, §2.1.4).
async fn Connection::send_roster_set(
  self : Connection,
  item_xml : String,
  cache : RosterItem,
) -> Unit raise XmppError {
  if !(self.state is (Bound | Online)) {
    raise XmppError::ProtocolViolation(
      detail="roster management requires a bound session",
    )
  }
  self.iq_counter += 1
  let id = "roster_set_\{self.iq_counter}"
  self.send_raw(
    "<iq type='set' id='\{id}' xmlns='jabber:client'><query xmlns='\{ROSTER_NS}'>\{item_xml}</query></iq>",
  )
  ignore(self.await_iq(id))
  self.apply_roster_push(cache)
}

///|
/// Add a contact or update its name and groups (RFC 6121 §2.1.3, §2.1.4).
/// An empty `name` clears the stored name.
pub async fn Connection::set_roster_item(
  self : Connection,
  jid~ : String,
  name~ : String = "",
  groups~ : Array[String] = [],
) -> Unit raise XmppError {
  let bare = parse_bare_jid(jid, kind="roster item")
  let item_name = if name is "" { None } else { Some(name) }
  self.send_roster_set(build_roster_item(jid, item_name, groups, false), {
    jid: bare,
    name: item_name,
    subscription: SubNone,
    ask: None,
    groups,
  })
}

///|
/// Remove a contact from the roster (RFC 6121 §2.1.5). The other party keeps
/// its own roster entry; cancel the subscriptions separately (§3.3).
pub async fn Connection::remove_roster_item(
  self : Connection,
  jid~ : String,
) -> Unit raise XmppError {
  let bare = parse_bare_jid(jid, kind="roster item")
  self.send_roster_set(build_roster_item(jid, None, [], true), {
    jid: bare,
    name: None,
    subscription: SubRemove,
    ask: None,
    groups: [],
  })
}

///|
/// Parse a JID for a roster request, reporting errors with context.
fn parse_bare_jid(jid : String, kind~ : String) -> @jid.Jid raise XmppError {
  @jid.Jid::parse(jid) catch {
    err =>
      raise XmppError::ProtocolViolation(
        detail="invalid jid for \{kind}: \{Repr(err)}",
      )
  }
}
