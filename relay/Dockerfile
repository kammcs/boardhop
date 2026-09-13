# Boardhop relay. Dart 3.13 matches the SDK the app is built with (pubspec
# environment: sdk ^3.13.3), so the relay can share models with it later.
FROM dart:3.13 AS build

WORKDIR /app

# Dependencies first: this layer is cached until the pubspec changes.
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get

COPY . .
RUN dart pub get --offline \
 && dart analyze \
 && dart compile exe bin/relay.dart -o /app/relay

# The AOT binary links against the system libc and libsqlite3, so the runtime
# is a slim Debian rather than scratch. curl is here for the healthcheck.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl libsqlite3-0 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/relay /usr/local/bin/relay

ENV RELAY_DB=/data/relay.sqlite \
    RELAY_CAPTURE_DIR=/data/capture \
    RELAY_PORT=8080

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/relay"]
