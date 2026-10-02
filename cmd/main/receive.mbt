///|
/// Receive stanzas until the connection closes, printing each chat message
/// and presence broadcast through `print`. Connection closure propagates
/// as XmppError.
pub async fn receive_loop(
  conn : @core.Connection,
  print~ : (String) -> Unit,
) -> Unit raise @core.XmppError {
  for ;; {
    match conn.recv_stanza() {
      Chat(msg) => print(format_chat(msg))
      Presence(p) => print(format_presence(p))
      Other => ()
    }
  }
}

///|
fn format_chat(msg : @core.ChatMessage) -> String {
  let from = match msg.from {
    Some(f) => f.to_string()
    None => "(unknown)"
  }
  "[\{from}] \{msg.body.unwrap_or("")}"
}

///|
fn format_presence(p : @core.Presence) -> String {
  let from = match p.from {
    Some(f) => f.to_string()
    None => "(unknown)"
  }
  let what = match p.presence_type {
    Some(t) => t
    None => "available"
  }
  match p.status {
    Some(s) => "* \{from} is \{what}: \{s}"
    None => "* \{from} is \{what}"
  }
}
