loglevel = "debug"

-- Prosody configuration for the moon-xmpp integration tests (T9.3).

modules_enabled = {
  "roster";
  "saslauth";
  "tls";
  "dialback";
  "disco";
  "carbons";
  "pep";
  "private";
  "blocklist";
  "vcard";
  "version";
  "uptime";
  "time";
  "ping";
  "register";
  "offline";
}

allow_registration = false

authentication = "internal_hashed"

c2s_require_encryption = true

pidfile = "/var/run/prosody/prosody.pid"

certificates = "/etc/prosody/certs"

VirtualHost "localhost"
  certificate = "/etc/prosody/certs/server.pem"
