# Release input retry debrief

An immutable signer input object was created before a transient signer-source
network failure. A workflow retry correctly could not overwrite that object.
The workflow now reuses it only after checking the exact archive file set and
comparing the bundle checksum, provenance, and buildspec with the current run.
The signer VPC security group also permits TCP 443 only to the S3 managed
prefix list, preserving private gateway access without broad Internet egress.
