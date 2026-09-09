package main

import (
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestValidatePaths(t *testing.T) {
	for _, test := range []struct {
		file, socket string
		valid        bool
	}{
		{"/vault/audit/audit.json", "/vault/audit/audit.sock", true},
		{"relative/audit.json", "/vault/audit/audit.sock", false},
		{"/vault/audit/audit.json", "/other/audit.sock", false},
	} {
		if got := validatePaths(test.file, test.socket) == nil; got != test.valid {
			t.Fatalf("validatePaths(%q, %q) valid=%v, want %v", test.file, test.socket, got, test.valid)
		}
	}
}

func TestRemoveStaleSocketAndRejectRegularFile(t *testing.T) {
	directory, err := os.MkdirTemp("/tmp", "audit-relay-")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(directory)
	socketPath := filepath.Join(directory, "audit.sock")
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}
	if err := removeStaleSocket(socketPath); err != nil {
		t.Fatalf("remove stale socket: %v", err)
	}
	if _, err := os.Lstat(socketPath); !os.IsNotExist(err) {
		t.Fatalf("stale socket still exists or cannot be checked: %v", err)
	}
	if err := os.WriteFile(socketPath, []byte("not a socket"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := removeStaleSocket(socketPath); err == nil {
		t.Fatal("removeStaleSocket accepted a regular file")
	}
}

func TestEmitRecordRejectsNonJSONAndCopiesValidJSON(t *testing.T) {
	records := make(chan []byte, 1)
	emitRecord([]byte("not-json"), records)
	select {
	case record := <-records:
		t.Fatalf("non-JSON record emitted: %q", record)
	default:
	}
	input := []byte(`{"type":"audit","request":{"id":"safe"}}`)
	emitRecord(input, records)
	for index := range input {
		input[index] = 'x'
	}
	select {
	case record := <-records:
		if string(record) != `{"type":"audit","request":{"id":"safe"}}` {
			t.Fatalf("valid JSON was not copied before enqueue: %q", record)
		}
	case <-time.After(time.Second):
		t.Fatal("valid JSON was not emitted")
	}
}
