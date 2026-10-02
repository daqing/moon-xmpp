///|
/// Entry point of the moon-xmpp demo CLI.
async fn main {
  let opts = parse_opts_or_usage(@env.args())
  let host = host_or_usage(opts)
  let port = match opts.port {
    Some(p) => p
    None => 5222
  }
  let conn = run(opts, host~, port~)
  receive_loop(conn, print=println) catch {
    err => println("session ended: \{Repr(err)}")
  }
}

///|
fn parse_opts_or_usage(raw : Array[String]) -> CliOptions raise {
  errdefer println(usage())
  parse_args(program_args(raw))
}

///|
fn host_or_usage(opts : CliOptions) -> String raise {
  errdefer println(usage())
  host_for(opts)
}
