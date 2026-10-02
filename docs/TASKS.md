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
> - As of 2026-10-01: T1 through T8 completed; T9.1 through T9.3 and T9.5 completed; T9.4 awaits a manual GUI run (docs/ACCEPTANCE.md).

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

- [x] T2.1 TCP connection layer: connect, read/write loop, close (native
      target) — moonbitlang/async@0.22.4 pinned; `ByteStream` decodes
      complete UTF-8 prefixes from raw socket reads (chunk-boundary safe)
      and feeds the framer; loopback tests cover connect/send/close
- [x] T2.2 Stream header round-trip: send the client header (`to`, `version`,
      etc.), parse the server response header; support stream restarts (one
      after TLS, one after SASL) — `Connection::open_stream` /
      `restart_stream`; the response header is validated (stream namespace,
      version 1.0, id); frames from one socket read are buffered so none are
      dropped between reads
- [x] T2.3 Stream features parsing: recognize at least `starttls`,
      `mechanisms`, and `bind` — `open_stream` / `restart_stream` return a
      `Features` summary; local-name matching, unknown features ignored.
      Also fixed a framer bug surfaced by the loopback test: `/` in a tag's
      attribute region now correctly marks the tag self-closing
- [x] T2.4 Stream error handling (RFC 6120 §4.9): parse, report upstream,
      disconnect — all §4.9.3 conditions mapped to a structured
      `StreamErrorCondition` (incl. see-other-host); a `stream:error` stanza
      read from the stream raises `XmppError::StreamError` with the optional
      `<text/>`
- [x] T2.5 Stanza error parsing (RFC 6120 §8.3): type and condition of
      `<error/>` children — `StanzaError::parse` maps all §8.3.3 conditions
      (incl. redirect) plus the error type, optional text, and unknown
      application conditions

## T3 STARTTLS (RFC 6120 §5)

Goal: upgrade the plaintext stream to TLS; algorithms and certificate
validation follow RFC 7590.

- [x] T3.1 TLS choice made: moonbitlang/async/tls@0.22.4 (OpenSSL-backed,
      version pinned together with moonbitlang/async). Verified with a
      loopback TLS test that `Tls::client` upgrades an established TCP
      connection; self-signed test cert lives in core/testdata and is only
      used with trust=NoVerification in tests
- [x] T3.2 `<starttls/>` negotiation: `Connection::starttls` verifies the
      feature was advertised, sends the request, reads `proceed` /
      `failure` byte-by-byte from the raw socket (so TLS handshake bytes
      coalesced into the same segment are not lost), upgrades the transport
      with `Tls::client` (default `trust=SystemRoot` + hostname), and
      restarts the stream over TLS
- [x] T3.3 Server certificate validation: `starttls(verify=true)` (the
      default) validates the server certificate against `SystemRoot` with
      hostname matching via `host~`; verified by a loopback test that a
      self-signed certificate is rejected with a catchable error.
      `Connection::is_encrypted` exposes the encryption state — T4.2 must
      refuse plaintext mechanisms when it is false

## T4 SASL (RFC 6120 §6, framework in RFC 4422)

Goal: log in. Implement the mechanisms in order; later ones reuse the
negotiation framework.

- [x] T4.1 SASL negotiation framework: mechanism selection (SCRAM-SHA-256 >
      SCRAM-SHA-1 > PLAIN, PLAIN gated on encryption), `sasl_auth` /
      `sasl_respond` (also public API for custom mechanisms), and byte-wise
      reading of challenge/success/failure so server bytes coalesced after
      `</success>` survive the stream restart; §6.5 failure conditions
      surface as `XmppError::Auth`
- [x] T4.2 PLAIN (RFC 4616): `Connection::authenticate` auto-selects or takes
      an explicit mechanism; PLAIN is refused on unencrypted streams, and the
      happy path is tested end-to-end over a real TLS loopback upgrade
- [x] T4.3 SCRAM-SHA-1 (RFC 5802): full client state machine in the sasl
      package (HMAC per RFC 2104, PBKDF2/Hi, saslname escaping, server
      signature verification) built on moonbitlang/x/crypto; validated
      against the RFC 5802 §5.1 test vector and a loopback wire test with a
      real proof-verifying fake server. SASL challenge/success payloads are
      base64-decoded before parsing per RFC 6120 §6.4.2
- [x] T4.4 SCRAM-SHA-256 (RFC 7677): reuses the T4.3 framework with the
      SHA-256 algorithm; validated against the RFC 7677 §3 test vector and a
      loopback wire test (both algorithms share one parametrized scenario)
- [x] T4.5 SCRAM channel binding (`-PLUS` variants): `authenticate`
      accepts `channel_binding~` — selection prefers -PLUS, the gs2 header
      names tls-server-end-point, and the binding data is the SHA-256 of
      the server certificate DER (RFC 5929). Covered by an offline c=
      structural test, mechanism-preference tests, and a full TLS wire test
      where the fake server asserts the bound c= value

## T5 Resource Binding (RFC 6120 §7)

Goal: obtain the full JID and produce a usable online session object.

- [x] T5.1 Bind iq: `bind_resource` sends the bind iq (self-closing bind
      element without a resource, `<resource/>` with one), parses the
      server-assigned full JID, stores it (`bound_jid`), and surfaces iq
      errors with their stanza conditions
- [x] T5.2 Session object and state machine: connecting → negotiating-tls →
      authenticating → bound (→ online in T6) exposed via `state()`, with
      ordering guards on starttls/authenticate/bind; the full TLS session
      is covered by state assertions, and the bind mechanics are whitebox
      tests that fast-forward to Authenticating

## T6 Presence (RFC 6121 §4)

Goal: become visible online and receive other parties' presence
notifications.

- [x] T6.1 Send initial presence (RFC 6121 §4.2) — `send_initial_presence`
      requires a bound session and moves it to Online
- [x] T6.2 Receive presence broadcasts and expose them to the caller (other
      parties becoming available / unavailable) — `recv_presence` parses
      from/type/status; non-presence stanzas are skipped until chat support
      lands in T7
- [x] T6.3 Send unavailable presence before disconnecting (graceful
      sign-off) — `signoff` sends the unavailable presence, closes the XML
      stream, and disconnects in one call

## T7 Chat Messages (RFC 6120 §8, RFC 6121 §5.2)

Goal: two-way chat — the core of the acceptance scenario.

- [x] T7.1 Sending a chat message: `send_chat` emits `type='chat'` with a
      generated stanza id and an escaped body, guarded to bound sessions
- [x] T7.2 Receiving a chat message: `recv_stanza` dispatches Chat /
      Presence / Other; `ChatMessage` carries from, id, and body;
      `recv_presence` is now a thin filter over the dispatch
- [x] T7.3 Robustness to unknown content: unknown top-level elements
      surface as Other, unknown stanza children are skipped, and body text
      is composed with full entity decoding (the XML parser keeps entity
      references as separate children, which get_text dropped — caught by
      these tests)

## T8 CLI Demo (cmd/main)

Goal: reproduce the acceptance scenario with one command.

- [x] T8.1 Argument parsing: `--jid` / `--password` / `--to` / `--body`,
      plus optional `--host` / `--port` / `--resource` overrides, in both
      `--name value` and `--name=value` forms with a typed CliError
- [x] T8.2 Wire up the full chain: connect → starttls → sasl → bind →
      presence → send — `run` covered end-to-end by a TLS loopback test
      that walks the whole session and inspects the sent message
- [x] T8.3 Receive loop: prints chat messages and presence broadcasts
      until the stream ends; covered by the TLS loopback test with a
      collecting printer

## T9 Testing and Acceptance

Goal: pass the acceptance scenario and wrap up.

- [x] T9.1 Local server test environment: docker/ejabberd.yml +
      scripts/ejabberd.sh (start/stop/register; works on x86 hosts) and
      scripts/prosody.sh + docker/prosody.Dockerfile as the native-arm64
      alternative, since the ejabberd image crashes its c2s acceptor under
      amd64 emulation on Apple Silicon; both accounts registered and
      STARTTLS verified against the project test certificate
- [x] T9.2 Unit test coverage: JID edge cases, XML escaping and malformed
      input, and the SCRAM RFC vectors were covered as each task landed;
      coverage analysis then filled the remaining offline gaps (SCRAM
      challenge error branches, CLI argument errors, authenticate guards)
- [x] T9.3 Integration test: scripts/e2e.sh verifies both directions
      against the real local server — online delivery (alice→bob) and
      offline storage+delivery (bob→alice) — and it exposed two real SASL
      bugs (payload base64, SCRAM username) that are fixed
- [ ] T9.4 End-to-end acceptance: run the acceptance scenario with Psi /
      Gajim / Conversations, exchange messages both ways, keep screenshots
      as evidence — guide and commands are ready in docs/ACCEPTANCE.md;
      requires a human with a GUI client, pending manual run
- [x] T9.5 Wrap-up: READMEs updated (protocol table, roadmap, status,
      demo); demo material is the CLI + scripts/e2e.sh +
      docs/ACCEPTANCE.md

---

[中文](TASKS.zh-CN.md)
