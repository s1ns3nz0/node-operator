#!/usr/bin/env python3
"""Synthetic-only tests for fixed UC5 CloudWatch audit reader."""
import importlib.util, json, pathlib, unittest

PATH = pathlib.Path(__file__).resolve().parents[2] / "scripts/ops/lib/uc5-audit-reader.py"
SPEC = importlib.util.spec_from_file_location("reader", PATH)
M = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(M)
START, END = "2026-09-11T00:00:00Z", "2026-09-11T00:01:00Z"

def row(kind="request"):
    return {"type": kind, "time": START, "request": {"id": "00000000-0000-4000-8000-000000000001"}}

class ReaderTests(unittest.TestCase):
    def test_fixed_cli_scope_nested_cri_dedup_and_memory_only(self):
        calls = []
        first = json.dumps({"log": "2026-09-11T00:00:01Z stdout F " + json.dumps(row())})
        pages = [json.dumps({"events": [{"message": first}], "nextToken": "next"}), json.dumps({"events": [{"message": json.dumps(row())}]})]
        def runner(args): calls.append(args); return pages.pop(0)
        records = M.read_records(START, END, runner)
        self.assertEqual(records, [row()])
        self.assertEqual(calls[0][:8], ("aws", "logs", "filter-log-events", "--region", M.REGION, "--log-group-name", M.GROUP, "--start-time"))
        self.assertIn("--next-token", calls[1])
        self.assertIn("--no-paginate", calls[0])
        self.assertIn("--filter-pattern", calls[0])

    def test_nested_cri_without_plain_duplicate_is_not_discarded(self):
        wrapped = json.dumps({"log": "2026-09-11T00:00:01Z stdout F " + json.dumps(row())})
        self.assertEqual(M.read_records(START, END, lambda _: json.dumps({"events": [{"message": wrapped}]})), [row()])

    def test_windows_and_pagination_budgets_fail_closed(self):
        with self.assertRaises(M.AuditReaderError): M.read_records(END, START, lambda _: "{}")
        with self.assertRaises(M.AuditReaderError): M.read_records(START, "2026-09-11T00:16:00Z", lambda _: "{}")
        with self.assertRaises(M.AuditReaderError): M.read_records(START, END, lambda _: json.dumps({"events": [], "nextToken": "same"}))
        def looping(_): return json.dumps({"events": [], "nextToken": "different"})
        with self.assertRaises(M.AuditReaderError): M.read_records(START, END, looping)

    def test_malformed_or_oversized_events_are_refused_without_log_output(self):
        with self.assertRaises(M.AuditReaderError): M.read_records(START, END, lambda _: json.dumps({"events": [{"message": "x" * (M.MAX_EVENT_BYTES + 1)}]}))
        with self.assertRaises(M.AuditReaderError): M.read_records(START, END, lambda _: json.dumps({"events": [{}]}))

if __name__ == "__main__": unittest.main()
