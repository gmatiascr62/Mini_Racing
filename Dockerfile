# Mini Racing authoritative online server (headless Godot 4.3).
# Build:  docker build -t mini-racing-server .
# Run:    docker run -p 9080:9080 mini-racing-server
FROM ubuntu:24.04

ARG GODOT_VERSION=4.3-stable
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && curl -L --fail --retry 3 -o /tmp/godot.zip \
    "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
 && unzip -q /tmp/godot.zip -d /tmp/godot \
 && mv /tmp/godot/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot /tmp/godot.zip

WORKDIR /app
COPY project.godot icon.png ./
COPY scenes ./scenes
COPY scripts ./scripts

# Import once at build time so the server starts instantly.
RUN godot --headless --editor --path /app --quit || true

# Hosting platforms (Render, Railway, Fly...) pass the port in $PORT.
ENV PORT=9080
EXPOSE 9080
CMD ["godot", "--headless", "--path", "/app", "--", "--server"]
