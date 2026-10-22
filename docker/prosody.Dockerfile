FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends prosody \
  && rm -rf /var/lib/apt/lists/*

EXPOSE 5222

# mod_posix shuts the server down when it runs as root, so run as the
# package-provided prosody user. Its own pid/config paths must be writable.
RUN mkdir -p /var/run/prosody \
  && chown prosody:prosody /var/run/prosody

USER prosody

CMD ["prosody"]
