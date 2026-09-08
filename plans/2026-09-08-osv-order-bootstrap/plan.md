# OSV order bootstrap plan

1. Reproduce and document the OSV v2.4 parsing failure in the current collector.
2. Correct only the OSV subcommand/global-option ordering and its focused contract.
3. Run focused collector, script-quality, and harness checks.
4. Push a feature branch and open a draft PR; do not merge or publish an image.
5. Record the required reviewed merge -> automatic main image build -> digest verification -> pin promotion sequence.
