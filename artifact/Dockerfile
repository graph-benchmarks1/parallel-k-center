# ALENEX artifact-evaluation container for the parallel k-center experiments.
#
# Build from the repository root with:
#   docker build -f artifact/Dockerfile -t kcenter-ae .
#
# Then run the smoke test with:
#   docker run --rm kcenter-ae smoke

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
      python3 \
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

# The .dockerignore file keeps generated files, local datasets, results, and
# repository metadata out of the Docker build context.
COPY . /artifact

# Fail the image build immediately if the repository cannot be compiled in the
# clean container.  This also downloads/caches Bazel dependencies in the image,
# so the reviewer-facing smoke run should only need a fast cached rebuild.
RUN ./artifact/build.sh

# run.sh is the single user-facing entry point.  At this milestone it supports
# build/smoke/smoke-no-build; light/full/custom will be added on top of the same
# interface once the real experiment driver exists.
ENTRYPOINT ["/artifact/artifact/run.sh"]
CMD ["help"]
