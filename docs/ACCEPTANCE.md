# Acceptance Test Guide

This is the acceptance scenario from the project brief: exchange messages
with a third-party client over a real server.

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

## GUI run (completed)

The same exchange was verified manually with Adium as alice@localhost
(2026-10-02): the CLI's message arrived in the GUI, a reply typed in the GUI
was printed by the running CLI, and the self-signed certificate was accepted
via Adium's trust dialog. Screenshots were skipped by the author's decision.

## 1. Start the server and accounts

```bash
scripts/prosody.sh start
scripts/prosody.sh register alice secret123
scripts/prosody.sh register bob secret123
```

(`scripts/ejabberd.sh` provides the same start/stop/register interface for
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

## Known limitations of the test environment

- The server certificate is the self-signed test certificate in
  `core/testdata/`, trusted by the CLI via `--ca-file`. GUI clients use
  their own accept-dialog flow instead.
- The server runs on `localhost` only.
