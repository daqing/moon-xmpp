# moon-xmpp

An XMPP client library for MoonBit, implementing the client side of
[XMPP Core (RFC 6120)](https://www.rfc-editor.org/rfc/rfc6120) and
[XMPP IM (RFC 6121)](https://www.rfc-editor.org/rfc/rfc6121).

## Status

**Work in progress.** moon-xmpp is being developed as an entry for a MoonBit
hackathon. The repository currently contains the project skeleton; the
protocol implementation is underway — see [Roadmap](#roadmap) for the build
order.

## What it does

moon-xmpp lets MoonBit programs connect to standard XMPP servers such as
ejabberd, log in securely, and exchange one-on-one chat messages that
interoperate with off-the-shelf clients such as Psi, Gajim, or Conversations.

The acceptance scenario for the project:

1. moon-xmpp connects to an ejabberd server, negotiates STARTTLS,
   authenticates with SASL, and binds a resource.
2. It sends a chat message to another account; the message shows up in a
   third-party client in real time.
3. A reply sent from that client is received by moon-xmpp.

## Protocol coverage

| Feature | Standard | Status |
| --- | --- | --- |
| XML streams | [RFC 6120 §4](https://www.rfc-editor.org/rfc/rfc6120#section-4) | planned |
| STARTTLS | [RFC 6120 §5](https://www.rfc-editor.org/rfc/rfc6120#section-5) | planned |
| SASL: PLAIN, SCRAM-SHA-1, SCRAM-SHA-256 | [RFC 4422](https://www.rfc-editor.org/rfc/rfc4422), [RFC 4616](https://www.rfc-editor.org/rfc/rfc4616), [RFC 5802](https://www.rfc-editor.org/rfc/rfc5802), [RFC 7677](https://www.rfc-editor.org/rfc/rfc7677) | planned |
| Resource binding | [RFC 6120 §7](https://www.rfc-editor.org/rfc/rfc6120#section-7) | planned |
| Initial presence | [RFC 6121 §4.2](https://www.rfc-editor.org/rfc/rfc6121#section-4.2) | planned |
| Chat messages | [RFC 6120 §8](https://www.rfc-editor.org/rfc/rfc6120#section-8), [RFC 6121 §5.2](https://www.rfc-editor.org/rfc/rfc6121#section-5.2) | planned |
| JID parsing and normalization | [RFC 8264](https://www.rfc-editor.org/rfc/rfc8264) | planned |

## Non-goals

- Roster and presence subscription management (RFC 6121 §2–3) — out of scope
  for now; may be revisited after the core works end to end.
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

> The API is still taking shape, but the direction is decided: async
> functions built on
> [moonbitlang/async](https://mooncakes.io/docs/moonbitlang/async). MoonBit
> has no `await` keyword — async calls look like ordinary calls, and errors
> propagate implicitly. The example below is illustrative; it will be updated
> as the API lands.

```moonbit
async fn main {
  let conn = @xmpp.connect(host = "example.com", port = 5222)
  conn.starttls()
  conn.authenticate(jid = "alice@example.com", password = "secret")
  conn.bind_resource("laptop")
  conn.send_initial_presence()
  conn.send_chat(to = "bob@example.com", body = "Hello from MoonBit!")
}
```

## Demo

A small CLI lives in `cmd/main`. Once the client is functional, a full
acceptance run will look like this:

```bash
git clone https://github.com/daqing/moon-xmpp
cd moon-xmpp
moon run cmd/main -- \
  --jid alice@example.com \
  --password '…' \
  --to bob@example.com \
  --body 'Hello from MoonBit!'
```

With a standard client (Psi, Gajim, Conversations) logged in as
`bob@example.com`, the message arrives immediately; a reply sent from that
client is delivered to the running CLI. Flag names may still change while the
CLI takes shape.

## Roadmap

1. [ ] XML stream negotiation — RFC 6120 §4
2. [ ] STARTTLS — RFC 6120 §5
3. [ ] SASL authentication: PLAIN, SCRAM-SHA-1, SCRAM-SHA-256
4. [ ] Resource binding — RFC 6120 §7
5. [ ] Initial presence — RFC 6121 §4.2
6. [ ] Chat message send/receive — RFC 6120 §8, RFC 6121 §5.2
7. [ ] CLI demo in `cmd/main`

## Development

Requires the [MoonBit toolchain](https://docs.moonbitlang.com) (`moon`).
Targets the native backend.

```bash
moon build   # build all packages (native target)
moon test    # run the test suite
moon fmt     # format the code
moon info    # regenerate package interfaces
```

Integration testing is planned against a local ejabberd instance.

## License

[MIT](LICENSE)

---

[中文说明](README.zh-CN.md)
