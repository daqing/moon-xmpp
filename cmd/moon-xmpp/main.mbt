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
  if opts.repl {
    repl_session(conn) catch {
      err => println("session ended: \{Repr(err)}")
    }
  } else {
    receive_loop(conn, print=println) catch {
      err => println("session ended: \{Repr(err)}")
    }
  }
}

///|
/// Run the REPL and the receive loop side by side. The roster is fetched
/// before both start so that the REPL reads it from the cache instead of
/// racing the receive loop for the socket.
async fn repl_session(conn : @core.Connection) -> Unit {
  defer conn.close()
  ignore(
    conn.get_roster() catch {
      err => {
        println("warning: could not load roster: \{Repr(err)}")
        []
      }
    },
  )
  @async.any([
    () => {
      repl_loop(
        conn,
        read_line=read_stdin,
        print_line=println,
        prompt=write_prompt,
      )
    },
    () => receive_loop(conn, print=println),
  ])
}

///|
async fn read_stdin() -> String? {
  @stdio.stdin.read_until("\n") catch {
    _ => None
  }
}

///|
/// Write the REPL prompt without a newline and flush it. `println` always
/// terminates the line, so the prompt goes through the same C stdout buffer
/// via a small native stub; that keeps it ordered with the line output.
extern "C" fn write_prompt_ffi() -> Unit = "moon_xmpp_write_prompt"

///|
fn write_prompt() -> Unit {
  write_prompt_ffi()
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
