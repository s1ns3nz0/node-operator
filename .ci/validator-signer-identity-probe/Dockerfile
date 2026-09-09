FROM golang:1.26.6-alpine@sha256:3889b425f035be855a72fb4755265311293b6d414521f0a519d819df32222d83 AS build
ENV GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=linux GOARCH=amd64
WORKDIR /src
COPY go.mod ./
COPY cmd/validator-signer-identity-probe/main.go cmd/validator-signer-identity-probe/main.go
COPY cmd/validator-signer-identity-probe/main_test.go cmd/validator-signer-identity-probe/main_test.go
RUN --mount=type=cache,target=/root/.cache/go-build go test ./cmd/validator-signer-identity-probe
RUN --mount=type=cache,target=/root/.cache/go-build go build -trimpath -buildvcs=false -ldflags='-s -w' -o /out/validator-signer-identity-probe ./cmd/validator-signer-identity-probe

FROM scratch
COPY --from=build /out/validator-signer-identity-probe /validator-signer-identity-probe
USER 65532:65532
ENTRYPOINT ["/validator-signer-identity-probe"]
