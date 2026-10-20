# Using the moon-xmpp REPL

[中文说明](REPL.zh-CN.md)

`cmd/moon-xmpp` is a small command-line XMPP client. Given only a JID and a
password, it logs in and opens an interactive REPL where you can list your
contacts, add friends, and send chat messages. Incoming messages and
presence broadcasts are printed while the REPL waits for your input.

This guide walks through the four common tasks:

1. [Log in](#1-log-in)
2. [Get your contact list](#2-get-your-contact-list)
3. [Add a friend](#3-add-a-friend)
4. [Send a message](#4-send-a-message)

All commands below are run from the repository root.

## 1. Log in

```bash
moon run cmd/moon-xmpp -- \
  --jid alice@example.com \
  --password 'secret'
```

The client:

1. connects and negotiates STARTTLS (the client refuses to continue when the
   server does not offer it),
2. authenticates with SASL,
3. binds a resource and sends initial presence, so your contacts see you as
   online,
4. fetches your roster into the local cache, and
5. starts the REPL.

You should see:

```
moon-xmpp repl. Type 'help' for commands, 'quit' to exit.
>
```

The host defaults to the domain part of the JID. Override it when the
connection endpoint differs from the domain:

```bash
moon run cmd/moon-xmpp -- --jid alice@example.com --password 'secret' \
  --host xmpp.example.net --port 5222 --resource laptop
```

With a self-signed certificate, pass `--ca-file` with the server's PEM
certificate (or the CA that signed it):

```bash
moon run cmd/moon-xmpp -- --jid alice@localhost --password secret123 \
  --ca-file core/testdata/test_cert.pem
```

To run the login flow locally, see
[ACCEPTANCE.md](ACCEPTANCE.md#1-start-the-server-and-accounts) for starting
Prosody and registering test accounts.

Once connected, `help` lists every command and `quit` (or `exit`, or
Ctrl-D) ends the session. A connection failure is reported and the program
exits; individual command failures are printed and the REPL stays open.

## 2. Get your contact list

```
> roster
roster: 1 item(s)
* bob@example.com name="Bob" subscription=SubBoth groups=[Friends]
```

Each line shows the contact's bare JID, the optional name, the subscription
state, and the groups. Subscription values are `SubNone`, `SubTo` (you see
their presence), `SubFrom` (they see yours), `SubBoth`, or `SubRemove`.

The roster is fetched once at login and served from the local cache. The
server pushes roster changes as they happen, and the CLI applies and prints
them, so `roster` stays current without another round trip:

```
* roster: bob@example.com SubBoth
```

## 3. Add a friend

In XMPP, "adding a friend" is a mutual presence subscription: you ask to see
a contact's presence, and the contact decides whether to grant it. The first
request also creates a roster entry for the contact on most servers.

From your REPL, request the subscription:

```
> subscribe bob@example.com
* subscription request sent to bob@example.com
```

`bob@example.com` now sees an authorization request in their client. The
CLI never answers such requests automatically; the request is printed and
left for the user to decide:

```
* subscription subscribe from alice@example.com
```

Bob can accept it with:

```
> approve alice@example.com
* approved subscription from alice@example.com
```

or refuse it with:

```
> deny alice@example.com
* refused subscription from alice@example.com
```

`approve` sends `subscribed`, `deny` sends `unsubscribed`. Run
`roster` afterwards to confirm the entry was added or updated.

To see each other's presence, the subscription must be mutual: if Bob wants
to see Alice too, Bob sends `subscribe alice@example.com` and Alice answers
`approve bob@example.com`. Once both directions are granted, `roster`
reports `subscription=SubBoth` and both sides receive availability updates
such as:

```
* bob@example.com/phone is available
```

To stop seeing a contact's presence, use:

```
> unsubscribe bob@example.com
* unsubscribed from bob@example.com
```

## 4. Send a message

```
> send bob@example.com Hello from the REPL!
message msg_2 sent to bob@example.com
```

Everything after the JID is the message body; you do not need quotes, and
internal spaces are preserved. The first word after `send` is always the
recipient JID. The printed ID is the stanza ID assigned by the client.

Incoming chat messages appear as they arrive, even while the prompt is
waiting:

```
> [bob@example.com/phone] Hi Alice!
```

Only chat messages, presence broadcasts, roster pushes, and subscription
requests are surfaced; other stanzas are ignored.

## Command reference

| Command | Effect |
| --- | --- |
| `roster` | Print the cached roster |
| `send <jid> <message>` | Send a chat message |
| `subscribe <jid>` | Ask to see a contact's presence |
| `approve <jid>` | Accept a subscription request |
| `unsubscribe <jid>` | Stop receiving a contact's presence |
| `deny <jid>` | Refuse a subscription request |
| `help` | List the commands |
| `quit` | End the session (also `exit`, or EOF) |

Blank lines are ignored, and command names are case-sensitive.

## Running actions without the REPL

The flags `--to`/`--body`, `--roster`, `--subscribe`, and `--approve` perform
one-shot actions instead of opening the REPL. They can be combined with
`--repl` to run the actions first and then enter the REPL:

```bash
moon run cmd/moon-xmpp -- --jid alice@example.com --password 'secret' \
  --to bob@example.com --body 'Hello from MoonBit!'

moon run cmd/moon-xmpp -- --jid alice@example.com --password 'secret' \
  --roster --subscribe bob@example.com --approve bob@example.com --repl
```

Without `--repl`, a one-shot invocation keeps printing incoming stanzas
until the stream ends.

## Troubleshooting

- **`connect ... failed`** — check `--host`/`--port`; if the server uses a
  self-signed certificate, pass `--ca-file`.
- **A new contact does not show up in `roster`** — the roster command reads
  the cache. Wait for the roster push (printed as `* roster: ...`), which
  the server sends after the subscription request is processed.
- **`error: ...` after a command** — the server rejected the command or the
  session is no longer bound. The REPL stays open; `quit` to exit.
