FROM ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517 AS scanner-system
ENV DEBIAN_FRONTEND=noninteractive
# Bootstrap CA trust through Ubuntu-signed APT metadata, then use verified TLS
# for bulk packages. Bound transient failures without accepting stale indexes.
RUN apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o APT::Update::Error-Mode=any update \
 && apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 install -y --no-install-recommends ca-certificates \
 && sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources \
 && apt-get -o Acquire::Retries=3 -o Acquire::https::Timeout=30 -o APT::Update::Error-Mode=any update \
 && apt-get -o Acquire::Retries=3 -o Acquire::https::Timeout=30 install -y --no-install-recommends curl git jq python3 python3-pip unzip shellcheck \
 && rm -rf /var/lib/apt/lists/*

FROM scanner-system
ARG SEMGREP_VERSION=1.159.0
ARG CHECKOV_VERSION=3.2.522
ARG GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG OSV_SCANNER_SHA256=15314940c10d26af9c6649f150b8a47c1262e8fc7e17b1d1029b0e479e8ed8a0
ARG SCANNER_INPUT_SHA
ENV DEBIAN_FRONTEND=noninteractive
LABEL io.node-operator.scanner-input-sha="${SCANNER_INPUT_SHA}"
RUN python3 -m pip install --break-system-packages --no-cache-dir "semgrep==${SEMGREP_VERSION}" "checkov==${CHECKOV_VERSION}" "zizmor==1.12.1"
RUN curl --fail --location --silent --show-error --output /tmp/gitleaks.tar.gz https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
 && echo "${GITLEAKS_SHA256}  /tmp/gitleaks.tar.gz" | sha256sum --check --status \
 && tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks \
 && rm /tmp/gitleaks.tar.gz
RUN curl --fail --location --silent --show-error --output /tmp/osv-scanner https://github.com/google/osv-scanner/releases/download/v2.4.0/osv-scanner_linux_amd64 \
 && echo "${OSV_SCANNER_SHA256}  /tmp/osv-scanner" | sha256sum --check --status \
 && install -m 0755 /tmp/osv-scanner /usr/local/bin/osv-scanner \
 && rm /tmp/osv-scanner
COPY .ci/scanners/run-security-scan.sh /usr/local/bin/run-security-scan
COPY scripts/ci/collect-security-evidence.sh scripts/ci/collect-pr-evidence.sh /opt/node-operator-scanner/scripts/
COPY scripts/ci/lib/common.sh /opt/node-operator-scanner/scripts/lib/common.sh
RUN chmod 0755 /usr/local/bin/run-security-scan /opt/node-operator-scanner/scripts/*.sh
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/run-security-scan"]
