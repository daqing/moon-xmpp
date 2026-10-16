# Acceptance Test Guide

This is the acceptance scenario from the project brief: exchange messages
with a third-party client over a real server, and manage the roster and
presence subscriptions with that client.

## Automated interop (completed)

`scripts/interop.sh` runs the interop against
[slixmpp](https://codeberg.org/poezio/slixmpp) — an independent Python XMPP
implementation, i.e. code this project has never talked to before — in a
container:

- alice runs on slixmpp; bob is our CLI.
- bob sends "Hello from MoonBit!"; alice receives it and replies
  "pong from slixmpp"; our CLI prints the reply.

Both directions passed; the transcripts are stored as evidence:
[interop-bob-cli.txt](acceptance/interop-bob-cli.txt) and
[interop-alice-slixmpp.txt](acceptance/interop-alice-slixmpp.txt).

## Automated roster and subscription run (completed)

`scripts/roster.sh` covers the RFC 6121 §2 and §3 half of the acceptance
scenario against the same kind of peer — alice on slixmpp in a container,
bob on our CLI:

- bob asks to see alice's presence and grants alice's own request
  (`--subscribe`, `--approve`).
- alice's inbound request is surfaced by the CLI, never auto-answered.
- a fresh bob session fetches the roster (`--roster`); alice's entry reads
  `subscription=SubBoth`.
- after mutual authorization, presence broadcasts flow both ways: bob sees
  `alice@localhost/… is available`, and slixmpp reports seeing bob.

All four checks passed (2026-10-16). The transcripts are stored as evidence:
[roster-bob-subscribe.txt](acceptance/roster-bob-subscribe.txt),
[roster-bob-fetch.txt](acceptance/roster-bob-fetch.txt), and
[roster-alice-slixmpp.txt](acceptance/roster-alice-slixmpp.txt). Re-run it
with `scripts/roster.sh`.

## GUI run (completed)

The same exchange was verified manually against a local prosody server
(`scripts/prosody.sh`) with Adium on macOS as alice@localhost (2026-10-02):
the CLI's message arrived in the GUI, a reply typed in the GUI was printed
by the running CLI, and the self-signed certificate was accepted via
Adium's trust dialog. Screenshots were skipped by the author's decision.

## 1. Start the server and accounts

```bash
scripts/prosody.sh start
scripts/prosody.sh register alice secret123
scripts/prosody.sh register bob secret123
```

(prosody is the reference server used by the recorded runs above — the
ejabberd image misbehaves under amd64 emulation on Apple Silicon;
`scripts/ejabberd.sh` provides the same start/stop/register interface for
ejabberd on x86 hosts.)

## 2. Configure the third-party client

In Psi, Gajim, or Conversations, add an account:

- JID: `alice@localhost`
- Password: `secret123`
- Host: `localhost`, port `5222`
- Encryption: STARTTLS (required); the certificate is self-signed, so the
  client will ask you to accept it — accept it for this test.

## 3. Run the moon-xmpp side

```bash
moon run cmd/main -- \
  --jid bob@localhost --password secret123 \
  --to alice@localhost \
  --body "Hello from MoonBit!" \
  --ca-file core/testdata/test_cert.pem
```

The CLI prints `message msg_1 sent to alice@localhost`, goes online, and
stays running to print anything it receives.

## 4. Verify

1. **Delivery**: "Hello from MoonBit!" appears in the GUI client within a
   second. Take a screenshot of the GUI showing the message.
2. **Reverse path**: type a reply in the GUI client. The CLI prints
   `[alice@localhost] <your reply>`. Take a screenshot of the terminal.
3. **Presence**: switching the GUI client's status to away/offline prints a
   presence line in the CLI (optional, bonus).

Store the screenshots alongside this file when the run is complete.

## 5. Roster and presence subscriptions (manual)

With the same server and GUI client, run the subscription half of the
scenario as bob:

```bash
moon run cmd/main -- \
  --jid bob@localhost --password secret123 \
  --subscribe alice@localhost \
  --ca-file core/testdata/test_cert.pem
```

Expected results:

1. **Authorization request**: the GUI client shows a request from bob;
   accept it. The CLI prints the stanza it receives in the other direction
   (`--approve` sends the grant from our side).
2. **Roster push**: as soon as the subscription state changes, the running
   CLI prints `* roster: alice@localhost SubTo` (or `SubBoth`) without
   reconnecting — the cached roster follows the server's push. The same push
   is what keeps a second CLI session (`--roster`) consistent.
3. **Roster fetch**: a new session with `--roster` prints
   `roster: 1 item(s)` and one line per contact, e.g.
   `* alice@localhost name="" subscription=SubBoth groups=[]`.
4. **Presence**: while a session is running, switch the GUI client's status
   to away or offline; the CLI prints `* alice@localhost/… is available` and
   `is unavailable` for the transitions. Remove the contact in the GUI
   client to see the subscription revoked on the next `--roster` fetch.

Incoming requests are never answered by the library: an application has to
call `send_subscribed` or `send_unsubscribed`, which is what the CLI's
`--approve` flag does explicitly.

## Known limitations of the test environment

- The server certificate is the self-signed test certificate in
  `core/testdata/`, trusted by the CLI via `--ca-file`. GUI clients use
  their own accept-dialog flow instead.
- The server runs on `localhost` only.
