# moon-xmpp Task List

> Broken down from the protocol coverage table and the Roadmap in the
> [README](../README.mbt.md).
>
> - Numbering: `T<phase>.<index>`; the order within a phase is the suggested
>   implementation order.
> - Progress rule: check off each item when done. After finishing a task that
>   concerns protocol capabilities, also update the protocol coverage table
>   and the Roadmap checkboxes in both READMEs.
> - Dependencies: T1 → T2 → … → T8 depend in sequence. **T9.1 (local ejabberd
>   environment) should be completed before starting T2**, since stream
>   negotiation and everything after it needs a real server to test against.
>   Pure computation tasks (JID, XML, SCRAM) don't need a server and can be
>   interleaved at any time.
> - As of 2026-10-01: T1 completed (T1.1 through T1.5).

## T1 Design and Foundations

Goal: settle the programming model and lay the JID and XML groundwork.

- [x] T1.1 API programming model decided (2026-10-01): async functions built
      on moonbitlang/async (version pinned in moon.mod), with the library
      written as a sequential protocol state machine. Refreshing the
      illustrative README example is deferred to T7.2, when the API lands
- [x] T1.2 Package layout created: jid / xml / sasl / core, each owning one
      public suberror type (JidError, XmlError, SaslError, XmppError);
      the root package stays the facade and will re-export them via
      `pub using`
- [x] T1.3 JID parsing: splitting and validating
      `localpart@domainpart/resourcepart` (RFC 8264) — `Jid::parse` in the
      jid package checks forbidden characters and the 1023-byte-per-part
      limit
- [x] T1.4 JID normalization: width map, case map, and NFKC (RFC 8264) —
      case mapping and NFKC come from moonbit-community/unicode@0.5.2
      (pinned); the width map is local; resourcepart is width-mapped only,
      preserving case
- [x] T1.5 XML layer done: `Framer` splits the stream into Root / Stanza /
      StreamEnd frames (tag-stack matching, quote/comment/CDATA aware,
      reusable after StreamEnd for stream restarts); `parse_element` feeds
      complete stanzas to XMLParser@0.2.6; serialization uses `escape_text`
      / `escape_attr`. The parser emits empty text nodes around child
      elements, so walk children by name rather than by index

## T2 XML Streams (RFC 6120 §4)

Goal: complete the stream handshake with the server, parse features, and
handle stream-level errors.

- [ ] T2.1 TCP connection layer: connect, read/write loop, close (native
      target)
- [ ] T2.2 Stream header round-trip: send the client header (`to`, `version`,
      etc.), parse the server response header; support stream restarts (one
      after TLS, one after SASL)
- [ ] T2.3 Stream features parsing: recognize at least `starttls`,
      `mechanisms`, and `bind`
- [ ] T2.4 Stream error handling (RFC 6120 §4.9): parse, report upstream,
      disconnect
- [ ] T2.5 Stanza error parsing (RFC 6120 §8.3): type and condition of
      `<error/>` children

## T3 STARTTLS (RFC 6120 §5)

Goal: upgrade the plaintext stream to TLS; algorithms and certificate
validation follow RFC 7590.

- [ ] T3.1 TLS choice made: moonbitlang/async/tls (OpenSSL-backed).
      Remaining work: pin the version, and verify that `Tls::client_from_pair`
      can upgrade the already-established TCP connection, as STARTTLS
      requires
- [ ] T3.2 `<starttls/>` negotiation: honor the `required` flag, send the
      request, handle `proceeded` / `failure`, restart the stream after the
      TLS handshake
- [ ] T3.3 Server certificate validation: hostname matching and expiry via
      Tls's `host~` + `TrustedRoot::SystemRoot`; disallow plaintext
      mechanisms on unencrypted streams (pairs with T4.2)

## T4 SASL (RFC 6120 §6, framework in RFC 4422)

Goal: log in. Implement the mechanisms in order; later ones reuse the
negotiation framework.

- [ ] T4.1 SASL negotiation framework: mechanism selection, parsing
      `challenge` / `response` / `success` / `failure`, stream restart on
      success
- [ ] T4.2 PLAIN (RFC 4616): only over an encrypted stream
- [ ] T4.3 SCRAM-SHA-1 (RFC 5802): build the client-first and client-final
      messages, verify the server-signature (needs HMAC, PBKDF2, and SHA-1
      primitives; validate with the RFC 5802 test vectors)
- [ ] T4.4 SCRAM-SHA-256 (RFC 7677): reuse the T4.3 framework with a
      different hash
- [ ] T4.5 (optional stretch) SCRAM channel binding (`-PLUS` variants) —
      async/tls already exposes tls-unique and tls-server-end-point bindings
      (RFC 5929), so the primitives exist

## T5 Resource Binding (RFC 6120 §7)

Goal: obtain the full JID and produce a usable online session object.

- [ ] T5.1 Bind iq: send the bind request (with or without a resource), parse
      the returned full JID
- [ ] T5.2 Session object and state machine: connecting → negotiating-tls →
      authenticating → bound → online, exposing the bound JID and current
      state

## T6 Presence (RFC 6121 §4)

Goal: become visible online and receive other parties' presence
notifications.

- [ ] T6.1 Send initial presence (RFC 6121 §4.2)
- [ ] T6.2 Receive presence broadcasts and expose them to the caller (other
      parties becoming available / unavailable)
- [ ] T6.3 Send unavailable presence before disconnecting (graceful
      sign-off)

## T7 Chat Messages (RFC 6120 §8, RFC 6121 §5.2)

Goal: two-way chat — the core of the acceptance scenario.

- [ ] T7.1 Sending a chat message: `type='chat'` + `<body/>` + `to`,
      generate a stanza id
- [ ] T7.2 Receiving a chat message: parse `from` / `body` and expose it to
      the caller in the API shape settled in T1.1
- [ ] T7.3 Robustness to unknown content: ignore unrecognized stanzas and
      child elements per RFC 6120's ignoring rules; never crash

## T8 CLI Demo (cmd/main)

Goal: reproduce the acceptance scenario with one command.

- [ ] T8.1 Argument parsing: `--jid` / `--password` / `--to` / `--body`,
      plus optional `--host` / `--port` overrides
- [ ] T8.2 Wire up the full chain: connect → starttls → sasl → bind →
      presence → send
- [ ] T8.3 Receive loop: print incoming messages, proving the reverse path
      works

## T9 Testing and Acceptance

Goal: pass the acceptance scenario and wrap up.

- [ ] T9.1 Local ejabberd test environment: run ejabberd in Docker, register
      two test accounts, one-command start/stop script (**do this before
      T2**)
- [ ] T9.2 Unit test coverage: JID edge cases, XML escaping and malformed
      input, SCRAM against the RFC 5802 test vectors
- [ ] T9.3 Integration test: exchange messages over the full chain (CLI to
      CLI, or library-level)
- [ ] T9.4 End-to-end acceptance: run the acceptance scenario with Psi /
      Gajim / Conversations, exchange messages both ways, keep screenshots
      as evidence
- [ ] T9.5 Wrap-up: update the READMEs (protocol table status, Roadmap
      checkboxes, Status section), prepare demo material

---

[中文](TASKS.zh-CN.md)
