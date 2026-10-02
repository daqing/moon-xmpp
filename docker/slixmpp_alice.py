"""Third-party interop client (T9.4): alice@localhost on slixmpp.

Receives one chat message from bob and replies "pong from slixmpp", then
disconnects. All output is flushed so the driver script can capture it as
evidence.
"""

import asyncio

import slixmpp


class Alice(slixmpp.ClientXMPP):
    def __init__(self, jid: str, password: str) -> None:
        super().__init__(jid, password)
        self.ca_certs = "/certs/test_cert.pem"
        self.received = asyncio.Event()
        self.add_event_handler("session_start", self.on_start)
        self.add_event_handler("message", self.on_message)

    async def on_start(self, _event) -> None:
        print("alice (slixmpp) online", flush=True)
        self.send_presence()
        try:
            await asyncio.wait_for(self.received.wait(), timeout=60)
        finally:
            self.disconnect()

    async def on_message(self, msg) -> None:
        if msg["type"] not in ("chat", "normal") or not msg["body"]:
            return
        print(f"[{msg['from']}] {msg['body']}", flush=True)
        if msg["from"].user == "bob":
            self.send_message(
                mto=msg["from"], mbody="pong from slixmpp", mtype="chat"
            )
            self.received.set()


xmpp = Alice("alice@localhost", "secret123")
xmpp.connect()
asyncio.get_event_loop().run_until_complete(xmpp.disconnected)
