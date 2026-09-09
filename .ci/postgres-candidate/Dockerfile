FROM ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517

ARG DEBIAN_FRONTEND=noninteractive

# Prototype only: retain dpkg and apt metadata so vulnerability scanners see
# the complete distro package inventory. This image has no database entrypoint.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    mkdir -p /etc/postgresql-common \
    && printf 'create_main_cluster = false\n' > /etc/postgresql-common/createcluster.conf \
    && apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        locales \
        postgresql-16 \
    && /usr/lib/postgresql/16/bin/postgres --version

ENV PATH="/usr/lib/postgresql/16/bin:${PATH}"

USER 999:999
CMD ["postgres", "--version"]
