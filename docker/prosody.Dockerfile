FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends prosody \
  && rm -rf /var/lib/apt/lists/*

EXPOSE 5222

CMD ["prosody"]
