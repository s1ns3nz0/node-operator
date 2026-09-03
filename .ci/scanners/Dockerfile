FROM ubuntu:24.04
ARG SEMGREP_VERSION=1.159.0
ARG CHECKOV_VERSION=3.2.522
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git jq python3 python3-pip unzip shellcheck && rm -rf /var/lib/apt/lists/*
RUN python3 -m pip install --break-system-packages --no-cache-dir "semgrep==${SEMGREP_VERSION}" "checkov==${CHECKOV_VERSION}" "zizmor==1.12.1"
RUN curl -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz | tar -xz -C /usr/local/bin gitleaks
RUN curl -fsSL https://github.com/google/osv-scanner/releases/download/v2.4.0/osv-scanner_linux_amd64 | install -m 0755 /dev/stdin /usr/local/bin/osv-scanner
COPY .ci/scanners/run-security-scan.sh /usr/local/bin/run-security-scan
COPY scripts/ci/collect-security-evidence.sh scripts/ci/collect-pr-evidence.sh /opt/node-operator-scanner/scripts/
COPY scripts/ci/lib/common.sh /opt/node-operator-scanner/scripts/lib/common.sh
RUN chmod 0755 /usr/local/bin/run-security-scan /opt/node-operator-scanner/scripts/*.sh
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/run-security-scan"]
