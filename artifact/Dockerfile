# Build from the repository root with:
#   docker build -f artifact/Dockerfile -t kcenter-ae .

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG BAZEL_VERSION=8.4.0

# Keep the image environment deterministic and non-interactive.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      g++ \
      gcc \
      git \
      make \
      lbzip2 \
      python3 \
      python3-matplotlib \
      python3-pip \
      unzip \
      zip \
    && rm -rf /var/lib/apt/lists/*

# Install the exact Bazel version pinned by this repository.  The official
# Bazel binary includes the embedded JDK needed to run Bazel itself.
RUN curl -fsSL \
      "https://releases.bazel.build/${BAZEL_VERSION}/release/bazel-${BAZEL_VERSION}-linux-x86_64" \
      -o /usr/local/bin/bazel \
    && chmod 0755 /usr/local/bin/bazel \
    && bazel --version

WORKDIR /artifact

COPY . /artifact

RUN ./artifact/build.sh

ENTRYPOINT ["/artifact/artifact/run.sh"]
CMD ["help"]
