# syntax=docker/dockerfile:1.7
# The only thing that ever rasterizes a golden. Build for linux/amd64 only:
#   make -C golden-env
FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

# flutter_tester links fontconfig/FreeType and, historically, libGLU.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates unzip xz-utils \
      fontconfig libfontconfig1 libfreetype6 libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Runs as whatever uid owns the repo: the Mac user under golden-run, the runner
# user on CI. So the SDK, pub cache and HOME are writable by any uid, and git
# must not refuse the SDK checkout for belonging to someone else.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=UTC \
    GOLDEN_ENV=1 CI=true FLUTTER_SUPPRESS_ANALYTICS=true \
    HOME=/home/golden FLUTTER_ROOT=/opt/flutter PUB_CACHE=/opt/pub-cache \
    PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/pub-cache/bin:$PATH
RUN git config --system --add safe.directory '*' \
 && mkdir -m 1777 /opt/flutter /opt/pub-cache /home/golden /work \
 && mkdir -p /etc/golden-env

# Fonts: nothing from the OS. Unbundled glyphs fall back to FlutterTest, which is stable.
RUN rm -rf /usr/share/fonts/* /usr/local/share/fonts/*
COPY fonts/*.ttf /usr/share/fonts/golden/
COPY fonts.conf /etc/fonts/local.conf
RUN fc-cache -f && fc-list | sort > /etc/golden-env/fonts.txt

COPY golden-entry.sh /usr/local/bin/golden-entry.sh

# The commit, not the tag, is what pins the engine: bin/internal/engine.version at
# that commit names the flutter_tester build that precache downloads.
# umask 0000 in the same RUN as the writes, so permissions cost no extra layer.
ARG FLUTTER_VERSION
ARG FLUTTER_COMMIT
RUN umask 0000 \
 && git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_ROOT" \
 && test "$(git -C "$FLUTTER_ROOT" rev-parse HEAD)" = "$FLUTTER_COMMIT" \
 && flutter config --no-analytics --no-cli-animations \
 && dart --disable-analytics \
 && flutter precache --universal --linux

# A throwaway `flutter test` pulls every remaining test-time artifact into the SDK
# cache, so runs never download SDK pieces.
RUN umask 0000 && cd /tmp && flutter create --project-name warmup warmup >/dev/null \
 && cd warmup && flutter test \
 && cd / && rm -rf /tmp/warmup "$PUB_CACHE"/* \
 && sha256sum "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/flutter_tester" \
      > /etc/golden-env/flutter_tester.sha256 \
 && flutter --version --machine > /etc/golden-env/flutter.json \
 && chmod -R a+rwX "$HOME"

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/golden-entry.sh"]
CMD ["flutter", "test", "--tags", "golden"]
