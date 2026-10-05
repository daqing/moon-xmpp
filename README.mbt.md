# moon-xmpp

An XMPP client library for MoonBit, implementing the client side of
[XMPP Core (RFC 6120)](https://www.rfc-editor.org/rfc/rfc6120) and
[XMPP IM (RFC 6121)](https://www.rfc-editor.org/rfc/rfc6121).

## Status

moon-xmpp is an entry for a MoonBit hackathon. The core session lifecycle
(streams, STARTTLS, SASL, resource binding, presence, chat) is implemented,
covered by 100+ tests, and verified end to end: against a real local XMPP
server (prosody), a chat message sent from moon-xmpp arrives in the Adium
GUI client on macOS, and Adium's reply is received back by moon-xmpp. Interop was also
verified automatically against [slixmpp](https://codeberg.org/poezio/slixmpp),
an independent Python XMPP implementation. See
[docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) for the runs and transcripts.

## What it does

moon-xmpp lets MoonBit programs connect to standard XMPP servers such as
ejabberd, log in securely, and exchange one-on-one chat messages that
interoperate with off-the-shelf clients such as Psi, Gajim, or Conversations.

The project's acceptance scenario — verified end to end (see
[Status](#status)):

1. moon-xmpp connects to an ejabberd server, negotiates STARTTLS,
   authenticates with SASL, and binds a resource.
2. It sends a chat message to another account; the message shows up in a
   third-party client in real time.
3. A reply sent from that client is received by moon-xmpp.

## Protocol coverage

| Feature | Standard | Status |
| --- | --- | --- |
| XML streams | [RFC 6120 §4](https://www.rfc-editor.org/rfc/rfc6120#section-4) | done |
| STARTTLS | [RFC 6120 §5](https://www.rfc-editor.org/rfc/rfc6120#section-5) | done |
| SASL: PLAIN, SCRAM-SHA-1, SCRAM-SHA-256 | [RFC 4422](https://www.rfc-editor.org/rfc/rfc4422), [RFC 4616](https://www.rfc-editor.org/rfc/rfc4616), [RFC 5802](https://www.rfc-editor.org/rfc/rfc5802), [RFC 7677](https://www.rfc-editor.org/rfc/rfc7677) | done |
| Resource binding | [RFC 6120 §7](https://www.rfc-editor.org/rfc/rfc6120#section-7) | done |
| Initial presence | [RFC 6121 §4.2](https://www.rfc-editor.org/rfc/rfc6121#section-4.2) | done |
| Chat messages | [RFC 6120 §8](https://www.rfc-editor.org/rfc/rfc6120#section-8), [RFC 6121 §5.2](https://www.rfc-editor.org/rfc/rfc6121#section-5.2) | done |
| JID parsing and normalization | [RFC 8264](https://www.rfc-editor.org/rfc/rfc8264) | done |

## Non-goals

- Roster and presence subscription management (RFC 6121 §2–3) — out of scope
  for now; may be revisited in a later version.
- XMPP extensions (XEPs), such as SASL2 (XEP-0388), Stream Management
  (XEP-0198), Message Carbons (XEP-0280), or MAM (XEP-0313).
- Server-to-server (s2s) federation and any server-side functionality — this
  is a client library only.

## Installation

```
moon add daqing/moon-xmpp
```

Then import it in the `moon.pkg` of your package:

```
import {
  "daqing/moon-xmpp" @xmpp,
}
```

## Usage

> The API is built on
> [moonbitlang/async](https://mooncakes.io/docs/moonbitlang/async). MoonBit
> has no `await` keyword — async calls look like ordinary calls, and errors
> propagate implicitly (functions raising `XmppError` must be called from a
> raising context).

```moonbit nocheck
///|
async fn main {
  let conn = @xmpp.connect(host="example.com", port=5222)
  conn.open_stream(domain="example.com")
  ignore(conn.starttls(domain="example.com"))
  ignore(conn.authenticate(jid="alice@example.com", password="secret"))
  ignore(conn.bind_resource(resource="laptop"))
  conn.send_initial_presence()
  let id = conn.send_chat(to="bob@example.com", body="Hello from MoonBit!")
  let stanza = conn.recv_stanza() // Chat / Presence / Other
}
```

## Demo

A small CLI lives in `cmd/main`:

```bash
git clone https://github.com/daqing/moon-xmpp
cd moon-xmpp
moon run cmd/main -- \
  --jid alice@example.com \
  --password '…' \
  --to bob@example.com \
  --body 'Hello from MoonBit!'
```

It connects (STARTTLS by default, `--host`/`--port` to override), logs in,
binds a resource, goes online, sends the message, and then prints incoming
messages and presence broadcasts until the stream ends. With a standard
client (Adium, Psi, Gajim, Conversations) logged in as `bob@example.com`,
the message arrives immediately; a reply sent from that client is printed
by the running CLI.

## Roadmap

1. [x] XML stream negotiation — RFC 6120 §4
2. [x] STARTTLS — RFC 6120 §5
3. [x] SASL authentication: PLAIN, SCRAM-SHA-1, SCRAM-SHA-256
4. [x] Resource binding — RFC 6120 §7
5. [x] Initial presence — RFC 6121 §4.2
6. [x] Chat message send/receive — RFC 6120 §8, RFC 6121 §5.2
7. [x] CLI demo in `cmd/main`

## Development

Requires the [MoonBit toolchain](https://docs.moonbitlang.com) (`moon`).
Targets the native backend.

```bash
moon build   # build all packages (native target)
moon test    # run the test suite
moon fmt     # format the code
moon info    # regenerate package interfaces
```

Integration testing runs against a local XMPP server:

```bash
scripts/prosody.sh start                    # or scripts/ejabberd.sh on x86
scripts/prosody.sh register alice secret123
scripts/prosody.sh register bob secret123
scripts/e2e.sh                              # two-direction delivery test
```

## License

[MIT](LICENSE)

---

[中文说明](README.zh-CN.md)
