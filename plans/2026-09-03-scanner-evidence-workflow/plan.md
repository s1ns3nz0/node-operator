# Scanner evidence workflow

1. Establish the task contract and execution graph.
2. Package the security-evidence collector and its shared shell library in the scanner image with a fixed entrypoint.
3. Reduce `CI Security` to image retrieval, one isolated scanner-runner invocation, and evidence-artifact upload; retain compatibility with the already-pinned tools-only image while widening the image-release trigger to all packaged inputs.
4. Run structural and policy-adapter validation, record results, and obtain a clean-room debrief.

No model fallback was used. The change does not authorize image publication, deployment, secret changes, or production access.
