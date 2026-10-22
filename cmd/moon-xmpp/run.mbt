///|
/// Run the full CLI chain: connect, stream negotiation, STARTTLS, SASL,
/// resource binding, initial presence, and sending the chat message.
/// Returns the live connection for the receive loop.
pub async fn run(
  opts : CliOptions,
  host~ : String,
  port~ : Int32,
  verify~ : Bool = true,
) -> @core.Connection raise @core.XmppError {
  let domain = (@jid.Jid::parse(opts.jid) catch {
      err =>
        raise @core.XmppError::ProtocolViolation(
          detail="invalid --jid: \{Repr(err)}",
        )
    }).domainpart
  let conn : @core.Connection = @core.connect(host~, port~)
  ignore(conn.open_stream(domain~))
  ignore(conn.starttls(domain~, verify~, ca_file=opts.ca_file))
  ignore(conn.authenticate(jid=opts.jid, password=opts.password))
  ignore(conn.bind_resource(resource=opts.resource.unwrap_or("")))
  conn.send_initial_presence()
  if opts.roster {
    let items = conn.get_roster()
    println("roster: \{items.length()} item(s)")
    for item in items {
      println(format_roster_item(item))
    }
  }
  match opts.subscribe {
    Some(peer) => conn.send_subscribe(to=peer)
    None => ()
  }
  match opts.approve {
    Some(peer) => conn.send_subscribed(to=peer)
    None => ()
  }
  match (opts.to, opts.body) {
    (Some(to), Some(body)) => {
      let id = conn.send_chat(to~, body~)
      println("message \{id} sent to \{to}")
    }
    _ => ()
  }
  conn
}
