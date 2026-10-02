///|
pub(all) suberror CliError {
  MissingArg(name~ : String)
  BadPort(value~ : String)
  UnknownArg(arg~ : String)
} derive(Eq, Debug)

///|
pub extend CliError with Eq::{not_equal, equal}

///|
pub extend CliError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub struct CliOptions {
  jid : String
  password : String
  to : String
  body : String
  host : String?
  port : Int?
  resource : String?
  ca_file : String?
} derive(Eq, Debug)

///|
pub extend CliOptions with Eq::{not_equal, equal}

///|
pub extend CliOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn usage() -> String {
  "usage: moon run cmd/main -- --jid user@example.com --password secret --to peer@example.com --body \"hello\" [--host host] [--port 5222] [--resource name] [--ca-file pem]"
}

///|
/// Parse command line arguments in `--name value` or `--name=value` form.
pub fn parse_args(args : Array[String]) -> CliOptions raise CliError {
  let mut jid : String? = None
  let mut password : String? = None
  let mut to : String? = None
  let mut body : String? = None
  let mut host : String? = None
  let mut port : Int? = None
  let mut resource : String? = None
  let mut ca_file : String? = None
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    let (name, inline_value) = match arg.find("=") {
      Some(eq) if arg.has_prefix("--") =>
        (arg[:eq].to_owned(), Some(arg[eq + 1:].to_owned()))
      _ => (arg, None)
    }
    let take_value = fn() -> String raise CliError {
      match inline_value {
        Some(v) => v
        None => {
          i += 1
          if i >= args.length() {
            raise CliError::MissingArg(name~)
          }
          args[i]
        }
      }
    }
    match name {
      "--jid" => jid = Some(take_value())
      "--password" => password = Some(take_value())
      "--to" => to = Some(take_value())
      "--body" => body = Some(take_value())
      "--host" => host = Some(take_value())
      "--port" => {
        let v = take_value()
        port = Some(
          @string.parse_int(v) catch {
            _ => raise CliError::BadPort(value=v)
          },
        )
      }
      "--resource" => resource = Some(take_value())
      "--ca-file" => ca_file = Some(take_value())
      _ => raise CliError::UnknownArg(arg~)
    }
    i += 1
  }
  let jid = match jid {
    Some(j) => j
    None => raise CliError::MissingArg(name="--jid")
  }
  let password = match password {
    Some(p) => p
    None => raise CliError::MissingArg(name="--password")
  }
  let to = match to {
    Some(t) => t
    None => raise CliError::MissingArg(name="--to")
  }
  let body = match body {
    Some(b) => b
    None => raise CliError::MissingArg(name="--body")
  }
  { jid, password, to, body, host, port, resource, ca_file, }
}

///|
/// The host to connect to: the --host override, or the domainpart of the
/// JID.
pub fn host_for(opts : CliOptions) -> String raise CliError {
  match opts.host {
    Some(h) => h
    None =>
      match
        (@jid.Jid::parse(opts.jid) catch {
          _ => raise CliError::MissingArg(name="--jid (invalid jid)")
        }) {
        j => j.domainpart
      }
  }
}

///|
/// The runtime passes the program name as the first argument; the CLI
/// options start at the first `--`-prefixed argument.
pub fn program_args(args : Array[String]) -> Array[String] {
  let mut start = 0
  while start < args.length() {
    if args[start].has_prefix("--") {
      break
    }
    start += 1
  }
  args[start:].to_owned()
}
