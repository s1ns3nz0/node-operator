#!/usr/bin/env python3
"""Render a proposed catalog row from a verified Kyverno CLI record.

This never edits the approved catalog.  A reviewer must add the returned row
after checking the publication artifact and its release authorization.
"""
from __future__ import annotations
import argparse, json
from pathlib import Path
from kyverno_cli_publication_record import KyvernoPublicationRecordError, create_record

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("--source-root",type=Path,required=True); parser.add_argument("--record",type=Path,required=True); args=parser.parse_args()
    try:
        value=json.loads(args.record.read_text()); target=value["target"]
        expected=create_record(args.source_root, release_revision=value["release_revision"], image_ref=target["image_ref"], manifest_digest=target["manifest_digest"], run_id=str(value["publication"]["run_id"]))
        if value != expected: raise KyvernoPublicationRecordError("record does not pass the local source binding")
        print(json.dumps({"source":target["image_ref"],"destination":"nodes","ecrTag":target["manifest_digest"].removeprefix("sha256:"),"purpose":"Reviewed Kyverno CLI "+value["source"]["tag"]+" built from "+value["source"]["commit"]},sort_keys=True))
    except (OSError, KeyError, TypeError, json.JSONDecodeError, KyvernoPublicationRecordError) as error: parser.error(str(error))
    return 0
if __name__ == "__main__": raise SystemExit(main())
