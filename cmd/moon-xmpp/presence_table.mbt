///|
/// Availability of contacts as observed from presence broadcasts, keyed by
/// bare JID. A contact is online while at least one of its resources has
/// announced availability.
pub(all) struct PresenceTable {
  mut online : Map[String, Set[String]]
}

///|
pub fn PresenceTable::new() -> PresenceTable {
  { online: Map([]), }
}

///|
/// Apply an inbound presence broadcast. Only available (no `type`) and
/// `unavailable` presences change the table; other types, such as `error`,
/// do not describe availability. An `unavailable` from a bare JID takes the
/// whole account offline.
pub fn PresenceTable::apply(
  self : PresenceTable,
  presence : @core.Presence,
) -> Unit {
  let from = match presence.from {
    Some(jid) => jid
    None => return
  }
  let bare = from.bare().to_string()
  match presence.presence_type {
    None => {
      let resources : Set[String] = self.online.get_or_init(bare, () => Set([]))
      resources.add(from.to_string())
    }
    Some("unavailable") =>
      if from.to_string() == bare {
        self.online.remove(bare)
      } else {
        match self.online.get(bare) {
          Some(resources) => {
            resources.remove(from.to_string())
            if resources.is_empty() {
              self.online.remove(bare)
            }
          }
          None => ()
        }
      }
    Some(_) => ()
  }
}

///|
pub fn PresenceTable::is_online(self : PresenceTable, bare : String) -> Bool {
  match self.online.get(bare) {
    Some(resources) => !resources.is_empty()
    None => false
  }
}

///|
/// The full JIDs currently available for `bare`, in the order they were
/// first seen.
pub fn PresenceTable::resources(
  self : PresenceTable,
  bare : String,
) -> Array[String] {
  match self.online.get(bare) {
    Some(resources) => resources.to_array()
    None => []
  }
}
