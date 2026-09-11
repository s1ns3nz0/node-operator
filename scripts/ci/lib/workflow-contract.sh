#!/usr/bin/env bash
# Static contracts inspect only implementation scripts explicitly called by the workflow.
workflow_source() {
  python3 "${BASH_SOURCE[0]%/*}/workflow-source.py" "$1"
}
