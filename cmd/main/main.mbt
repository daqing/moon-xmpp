///|
/// Entry point of the moon-xmpp demo CLI.
async fn main {
  let opts = parse_opts_or_usage()
  let host = host_or_usage(opts)
  let port = match opts.port {
    Some(p) => p
    None => 5222
  }
  let conn = run(opts, host~, port~)
  conn.close()
}

///|
fn parse_opts_or_usage() -> CliOptions raise {
  errdefer println(usage())
  parse_args(@env.args())
}

///|
fn host_or_usage(opts : CliOptions) -> String raise {
  errdefer println(usage())
  host_for(opts)
}
