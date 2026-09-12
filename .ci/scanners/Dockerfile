FROM ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517
ARG SEMGREP_VERSION=1.159.0
ARG CHECKOV_VERSION=3.2.522
ARG GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG OSV_SCANNER_SHA256=15314940c10d26af9c6649f150b8a47c1262e8fc7e17b1d1029b0e479e8ed8a0
ARG SCANNER_INPUT_SHA
ENV DEBIAN_FRONTEND=noninteractive
LABEL io.node-operator.scanner-input-sha="${SCANNER_INPUT_SHA}"
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git jq python3 python3-pip unzip shellcheck && rm -rf /var/lib/apt/lists/*
# Install immutable PyPI artifacts.  The URLs and SHA-256 fragments are part of
# the release input contract; dependency resolution remains bounded by the
# versioned scanner image build.
RUN python3 -m pip install --break-system-packages --no-cache-dir \
  "https://files.pythonhosted.org/packages/51/db/a42b7f6ed4442056fcfcb0d18a383850e1c3335f0ad7a44802c82799eaa8/semgrep-${SEMGREP_VERSION}-cp310.cp311.cp312.cp313.cp314.py310.py311.py312.py313.py314-none-manylinux_2_35_x86_64.whl#sha256=818fa01b5f64a08f90730c392db3638daaae558066f555ffc44759c535d3d1e5" \
  "https://files.pythonhosted.org/packages/64/2f/479916d48843eb868788f8e8a1e1f762dbbed09758af3662379941834c69/checkov-${CHECKOV_VERSION}-py3-none-any.whl#sha256=02fd527ca7072ccce18966fa9e2fe82b7739941f8b2c0309b9f7a2dd845eed68" \
  "https://files.pythonhosted.org/packages/91/be/ecb5df56d8ff09f86ad0d5ca4e6d4ec644e1d539be096d6719eac941e571/zizmor-1.12.1-py3-none-manylinux_2_28_x86_64.whl#sha256=92db1a97697db58137f0e4479bb63b1236608ed7bcc0bb23dea107436df6fd2e"
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
