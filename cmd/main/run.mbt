///|
/// Run the full CLI chain: connect, stream negotiation, STARTTLS, SASL,
/// resource binding, initial presence, and sending the chat message.
/// Returns the live connection for the receive loop.
pub async fn run(
  opts : CliOptions,
  host~ : String,
  port~ : Int,
  verify? : Bool = true,
) -> @core.Connection raise @core.XmppError {
  let domain = (@jid.Jid::parse(opts.jid) catch {
      err =>
        raise @core.XmppError::ProtocolViolation(
          detail="invalid --jid: \{Repr(err)}",
        )
    }).domainpart
  let conn : @core.Connection = @core.connect(host~, port~)
  ignore(conn.open_stream(domain~))
  ignore(conn.starttls(domain~, verify~))
  ignore(conn.authenticate(jid=opts.jid, password=opts.password))
  ignore(conn.bind_resource(resource=opts.resource.unwrap_or("")))
  conn.send_initial_presence()
  let id = conn.send_chat(to=opts.to, body=opts.body)
  println("message \{id} sent to \{opts.to}")
  conn
}
