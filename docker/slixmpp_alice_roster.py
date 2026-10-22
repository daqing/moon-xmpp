"""Third-party peer for the roster/subscription acceptance run (T10).

alice@localhost on slixmpp: publishes her presence, asks to see bob's
presence, approves bob's subscription request, and reports the presence
stanzas she receives. All output is flushed so the driver script can
capture it as evidence.
"""

import asyncio

import slixmpp


class Alice(slixmpp.ClientXMPP):
    def __init__(self, jid: str, password: str) -> None:
        super().__init__(jid, password)
        self.ca_certs = "/certs/test_cert.pem"
        self.add_event_handler("session_start", self.on_start)
        self.add_event_handler("presence_subscribe", self.on_subscribe)
        self.add_event_handler("presence_available", self.on_available)

    async def on_start(self, _event) -> None:
        print("alice (slixmpp) online", flush=True)
        self.send_presence()
        self.send_presence(pto="bob@localhost", ptype="subscribe")
        print("alice asked to see bob's presence", flush=True)
        await asyncio.sleep(60)
        self.disconnect()

    async def on_subscribe(self, presence) -> None:
        print(
            f"alice got a subscribe request from {presence['from']}", flush=True
        )
        self.send_presence(pto=presence["from"].bare, ptype="subscribed")

    async def on_available(self, presence) -> None:
        print(f"alice sees {presence['from']} available", flush=True)


xmpp = Alice("alice@localhost", "secret123")
xmpp.connect()
asyncio.get_event_loop().run_until_complete(xmpp.disconnected)
