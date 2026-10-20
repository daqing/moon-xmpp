///|
/// A command typed into the REPL. `Empty` is a blank line, and
/// `MissingArgument` carries the usage hint for the offending command.
pub(all) enum ReplCommand {
  Empty
  Help
  Roster
  Send(to~ : String, body~ : String)
  Subscribe(jid~ : String)
  Approve(jid~ : String)
  Unsubscribe(jid~ : String)
  Deny(jid~ : String)
  Quit
  Unknown(name~ : String)
  MissingArgument(usage~ : String)
} derive(Eq, Debug)

///|
pub extend ReplCommand with Eq::{not_equal, equal}

///|
pub extend ReplCommand with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Split the first whitespace-delimited token off `s` and skip the run of
/// whitespace that follows it.
fn repl_split_head(s : StringView) -> (StringView, StringView) {
  let len = s.length()
  let mut i = 0
  while i < len {
    match s.get_char(i) {
      Some(c) if !c.is_whitespace() => i += 1
      _ => break
    }
  }
  let mut j = i
  while j < len {
    match s.get_char(j) {
      Some(c) if c.is_whitespace() => j += 1
      _ => break
    }
  }
  (s.view(start_offset=0, end_offset=i), s.view(start_offset=j))
}

///|
/// Parse one line of REPL input. The command name is case-sensitive; the
/// arguments for `send` keep their internal whitespace.
pub fn parse_repl_command(line : String) -> ReplCommand {
  let s = line.trim()
  if s.is_empty() {
    return Empty
  }
  let (name, rest) = repl_split_head(s)
  let (arg, tail) = repl_split_head(rest)
  let name = name.to_owned()
  match name {
    "help" | "?" => Help
    "roster" => Roster
    "quit" | "exit" => Quit
    "send" =>
      if arg.is_empty() || tail.trim().is_empty() {
        MissingArgument(usage="send <jid> <message>")
      } else {
        Send(to=arg.to_owned(), body=tail.trim().to_owned())
      }
    "subscribe" =>
      if arg.is_empty() {
        MissingArgument(usage="subscribe <jid>")
      } else {
        Subscribe(jid=arg.to_owned())
      }
    "approve" =>
      if arg.is_empty() {
        MissingArgument(usage="approve <jid>")
      } else {
        Approve(jid=arg.to_owned())
      }
    "unsubscribe" =>
      if arg.is_empty() {
        MissingArgument(usage="unsubscribe <jid>")
      } else {
        Unsubscribe(jid=arg.to_owned())
      }
    "deny" =>
      if arg.is_empty() {
        MissingArgument(usage="deny <jid>")
      } else {
        Deny(jid=arg.to_owned())
      }
    _ => Unknown(name~)
  }
}

///|
pub fn repl_help() -> String {
  "commands:\n  roster               list the cached roster\n  send <jid> <message> send a chat message\n  subscribe <jid>      request a contact's presence\n  approve <jid>        accept a subscription request\n  unsubscribe <jid>    stop receiving a contact's presence\n  deny <jid>           refuse a subscription request\n  help                 show this help\n  quit                 leave the repl"
}

///|
async fn execute_repl_command(
  conn : @core.Connection,
  cmd : ReplCommand,
  print_line~ : (String) -> Unit,
) -> Unit raise @core.XmppError {
  match cmd {
    Roster => {
      let items = conn.roster()
      print_line("roster: \{items.length()} item(s)")
      for item in items {
        print_line(format_roster_item(item))
      }
    }
    Send(to~, body~) => {
      let id = conn.send_chat(to~, body~)
      print_line("message \{id} sent to \{to}")
    }
    Subscribe(jid~) => {
      conn.send_subscribe(to=jid)
      print_line("* subscription request sent to \{jid}")
    }
    Approve(jid~) => {
      conn.send_subscribed(to=jid)
      print_line("* approved subscription from \{jid}")
    }
    Unsubscribe(jid~) => {
      conn.send_unsubscribe(to=jid)
      print_line("* unsubscribed from \{jid}")
    }
    Deny(jid~) => {
      conn.send_unsubscribed(to=jid)
      print_line("* refused subscription from \{jid}")
    }
    Empty | Help | Quit | Unknown(_) | MissingArgument(_) => ()
  }
}

///|
/// Read commands from `read_line` and dispatch them on `conn` until the
/// input reaches EOF or the user types `quit`. Command failures are printed
/// and do not end the session. `prompt` writes the input prompt without a
/// trailing newline, so it needs its own writer: `print_line` always ends a
/// line.
///
/// The roster is served from the connection's cache so that only the
/// background receive loop reads from the socket; callers should fetch the
/// roster before starting both loops.
pub async fn repl_loop(
  conn : @core.Connection,
  read_line~ : async () -> String?,
  print_line~ : (String) -> Unit,
  prompt~ : () -> Unit,
) -> Unit {
  print_line("moon-xmpp repl. Type 'help' for commands, 'quit' to exit.")
  for ;; {
    prompt()
    let line = match (read_line() catch { _ => None }) {
      Some(line) => line
      None => break
    }
    match parse_repl_command(line) {
      Empty => ()
      Quit => break
      Help => print_line(repl_help())
      Unknown(name~) =>
        print_line("unknown command: \{name} (type 'help' for help)")
      MissingArgument(usage~) => print_line("usage: \{usage}")
      cmd =>
        execute_repl_command(conn, cmd, print_line~) catch {
          err => print_line("error: \{Repr(err)}")
        }
    }
  }
  print_line("bye")
}
