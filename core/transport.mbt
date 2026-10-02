///|
priv enum Transport {
  Tcp(@socket.Tcp)
  Tls(@tls.Tls, @socket.Tcp)
}

///|
/// A client connection to an XMPP server.
pub struct Connection {
  priv mut transport : Transport
  priv byte_stream : ByteStream
  priv mut closed : Bool
  priv mut state : ConnectionState
  priv mut stream_header : StreamHeader?
  priv mut features : Features?
  priv mut domain : String?
  priv mut bound : @jid.Jid?
  priv mut iq_counter : Int
  priv frames : Array[@xml.Frame]
  priv mut frame_pos : Int
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
  {
    transport: Tcp(tcp),
    byte_stream: ByteStream::new(),
    closed: false,
    state: Connecting,
    stream_header: None,
    features: None,
    domain: None,
    bound: None,
    iq_counter: 0,
    frames: [],
    frame_pos: 0,
  }
}

///|
/// Return the current session state.
pub fn Connection::state(self : Connection) -> ConnectionState {
  self.state
}

///|
/// Return the full JID assigned by resource binding, once bound.
pub fn Connection::bound_jid(self : Connection) -> @jid.Jid? {
  self.bound
}

///|
/// Return the stream id assigned by the server, if the stream is open.
pub fn Connection::stream_id(self : Connection) -> String? {
  match self.stream_header {
    Some(header) => Some(header.id)
    None => None
  }
}

///|
/// Return true when the connection is TLS-encrypted.
pub fn Connection::is_encrypted(self : Connection) -> Bool {
  match self.transport {
    Tls(_, _) => true
    Tcp(_) => false
  }
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
    Tls(tls, _) =>
      tls.write(s) catch {
        err => raise XmppError::Io(detail="write failed: \{Repr(err)}")
      }
  }
}

///|
/// Close the connection.
pub fn Connection::close(self : Connection) -> Unit {
  match self.transport {
    Tcp(tcp) => tcp.close()
    Tls(tls, tcp) => {
      tls.close()
      tcp.close()
    }
  }
  self.closed = true
}

///|
pub fn Connection::is_closed(self : Connection) -> Bool {
  self.closed
}

///|
/// Read from the socket until at least one frame completes.
async fn Connection::pump(
  self : Connection,
) -> Array[@xml.Frame] raise XmppError {
  for ;; {
    let chunk = match self.transport {
      Tcp(tcp) =>
        tcp.read_some() catch {
          err => raise XmppError::Io(detail="read failed: \{Repr(err)}")
        }
      Tls(tls, _) =>
        tls.read_some() catch {
          err => raise XmppError::Io(detail="read failed: \{Repr(err)}")
        }
    }
    match chunk {
      None => {
        self.closed = true
        raise XmppError::ConnectionClosed
      }
      Some(data) => {
        let frames = self.byte_stream.push_bytes(data) catch {
          err => raise XmppError::ProtocolViolation(detail="\{Repr(err)}")
        }
        if frames.length() > 0 {
          return frames
        }
      }
    }
  }
}
