///|
/// Buffers raw bytes from the socket, decodes complete UTF-8 sequences, and
/// feeds them to the XML stream framer.
pub struct ByteStream {
  priv pending : Array[Byte]
  priv framer : @xml.Framer
}

///|
pub fn ByteStream::new() -> ByteStream {
  { pending: [], framer: @xml.Framer::new(), }
}

///|
/// Feed one chunk of raw bytes and return the frames completed by it.
pub fn ByteStream::push_bytes(
  self : ByteStream,
  chunk : Bytes,
) -> Array[@xml.Frame] raise @xml.XmlError {
  for i in 0..<chunk.length() {
    self.pending.push(chunk[i])
  }
  let n = complete_utf8_prefix(self.pending)
  if n == 0 {
    return []
  }
  let text = @utf8.decode(Bytes::from_array(self.pending[:n])) catch {
    _ => raise @xml.XmlError::Malformed(detail="invalid utf-8 in stream")
  }
  let rest : Array[Byte] = []
  for i in n..<self.pending.length() {
    rest.push(self.pending[i])
  }
  self.pending.clear()
  for b in rest {
    self.pending.push(b)
  }
  self.framer.push(text)
}

///|
/// Reset the buffer and the framer, for a stream restart.
pub fn ByteStream::reset(self : ByteStream) -> Unit {
  self.pending.clear()
  self.framer.reset()
}

///|
/// Return the length in bytes of the longest prefix of complete UTF-8
/// sequences. Trailing partial sequences are kept for the next chunk.
fn complete_utf8_prefix(arr : Array[Byte]) -> Int raise @xml.XmlError {
  let len = arr.length()
  let mut i = 0
  while i < len {
    let lead = arr[i].to_int()
    let seq_len = if lead < 0x80 {
      1
    } else if lead >= 0xc0 && lead <= 0xdf {
      2
    } else if lead >= 0xe0 && lead <= 0xef {
      3
    } else if lead >= 0xf0 && lead <= 0xf4 {
      4
    } else {
      raise @xml.XmlError::Malformed(detail="invalid utf-8 byte in stream")
    }
    if i + seq_len > len {
      break
    }
    for j in (i + 1)..<(i + seq_len) {
      let cont = arr[j].to_int()
      if cont < 0x80 || cont > 0xbf {
        raise @xml.XmlError::Malformed(detail="invalid utf-8 continuation byte")
      }
    }
    i += seq_len
  }
  i
}
