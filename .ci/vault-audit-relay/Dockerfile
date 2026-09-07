FROM golang:1.24.6-alpine@sha256:c8c5f95d64aa79b6547f3b626eb84b16a7ce18a139e3e9ca19a8c078b85ba80d AS build

ARG RELAY_INPUT_SHA
WORKDIR /src
COPY go.mod ./
COPY cmd/vault-audit-relay/main.go ./cmd/vault-audit-relay/main.go
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -ldflags='-s -w' -o /out/vault-audit-relay ./cmd/vault-audit-relay

FROM scratch
ARG RELAY_INPUT_SHA
LABEL io.node-operator.vault-audit-relay-input-sha="${RELAY_INPUT_SHA}"
COPY --from=build /out/vault-audit-relay /vault-audit-relay
USER 100:1000
ENTRYPOINT ["/vault-audit-relay"]
