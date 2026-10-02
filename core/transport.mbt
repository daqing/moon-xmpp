///|
priv enum Transport {
  Tcp(@socket.Tcp)
}

///|
/// A client connection to an XMPP server.
pub struct Connection {
  priv transport : Transport
  priv mut closed : Bool
}

///|
/// Connect to an XMPP server over TCP.
pub async fn connect(host~ : String, port~ : Int) -> Connection raise XmppError {
  let tcp = @socket.Tcp::connect_to_host(host, port~) catch {
    err =>
      raise XmppError::Io(
        detail="connect to \{host}:\{port} failed: \{Repr(err)}",
      )
  }
  { transport: Tcp(tcp), closed: false, }
}

///|
/// Send raw text on the stream.
pub async fn Connection::send_raw(
  self : Connection,
  s : String,
) -> Unit raise XmppError {
  match self.transport {
    Tcp(tcp) =>
      tcp.write(s) catch {
        err => raise XmppError::Io(detail="write failed: \{Repr(err)}")
      }
  }
}

///|
/// Close the connection.
pub fn Connection::close(self : Connection) -> Unit {
  match self.transport {
    Tcp(tcp) => tcp.close()
  }
  self.closed = true
}

///|
pub fn Connection::is_closed(self : Connection) -> Bool {
  self.closed
}
