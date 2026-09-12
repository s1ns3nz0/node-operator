# How a Hoodi validator works with Nethermind and Prysm

An Ethereum validator is not one program. It is a small system in which different components verify the chain, decide when a validator has work to do, and protect the private key used to sign that work.

This guide explains that mechanism using Hoodi, Nethermind, and Prysm.

## The architecture

```text
Ethereum peer network
        │
        ├── Nethermind ────── execution-layer verification
        │        ▲
        │        │ authenticated Engine API
        │        ▼
        └── Prysm Beacon ──── consensus-layer verification
                  │
                  │ validator duty / signing request
                  ▼
            Prysm Validator
                  │
                  ▼
             Remote signer
                  │
                  ▼
          Slashing database
```

The separation is intentional. A node that follows the chain is not automatically a validator, and a validator client that asks for a signature does not need to possess the key itself.

## 1. Two clients verify two different parts of Ethereum

Ethereum has an execution layer and a consensus layer.

The execution layer processes transactions: account balances, smart-contract calls, and the resulting state. **Nethermind** is the execution client. It receives execution blocks from peers and checks that the transactions and state transitions obey Ethereum rules.

The consensus layer decides which blocks are accepted and finalized. **Prysm Beacon** is the consensus client. It follows beacon-chain blocks, tracks validator duties, and coordinates the consensus protocol.

Neither client is enough by itself. A consensus block refers to an execution payload, and Prysm must ask Nethermind whether that payload is valid. They make this request through the Engine API:

```text
Prysm Beacon: “Is this execution payload valid?”
Nethermind:   “Yes / no, according to execution rules.”
```

In the checked-in Hoodi example, Nethermind uses P2P port `30303` and Engine API port `8551`; Prysm Beacon uses P2P port `13000` and Beacon API port `3500`. The Engine API is authenticated with a JWT, so it is a private client-to-client channel rather than a public RPC endpoint. See the [Nethermind](../../deploy/nethermind/statefulset.yaml) and [Prysm](../../deploy/prysm/statefulset.yaml) examples.

## The Nethermind–Prysm data flow

The clients exchange **validation results and block-building data**, not validator private keys. Their steady-state flow has two directions.

```text
1. Execution gossip                         2. Consensus gossip
Ethereum execution peers                    Ethereum consensus peers
        │                                            │
        ▼                                            ▼
   Nethermind                                  Prysm Beacon
        │                                            │
        └──────── Engine API, authenticated ────────┘
                         JWT
```

### When Prysm verifies an incoming consensus block

1. Prysm Beacon receives a beacon block from consensus peers.
2. The beacon block contains an **execution payload**: the execution-layer block data that belongs at that point in the consensus chain.
3. Prysm sends that payload to Nethermind through the private Engine API.
4. Nethermind checks the payload against its execution state: transactions, receipts, state transition, parent relationship, and execution-block rules.
5. Nethermind returns whether the payload is valid, invalid, or still syncing.
6. Prysm uses that result when deciding whether the consensus block can be accepted.

In short: **Prysm decides whether the consensus block fits the beacon-chain rules; Nethermind decides whether its execution payload obeys execution rules.** A block needs both answers.

### When Prysm asks Nethermind to build the next execution payload

When the local validator is selected to propose a block, the direction reverses:

1. Prysm Beacon knows the slot, parent beacon block, and consensus context for the proposal.
2. Prysm asks Nethermind for a candidate execution payload through the Engine API.
3. Nethermind selects valid pending transactions, executes them on top of the parent state, and produces an execution payload.
4. Prysm includes that payload in the proposed beacon block.
5. The validator client asks the remote signer to sign the resulting proposal only after the beacon node has prepared the duty.
6. Prysm gossips the signed beacon block to consensus peers; Nethermind gossips and serves the corresponding execution data to execution peers.

The important boundary is at step 5: the Engine API helps build and validate blocks, but it never signs validator duties. The signing path is separate.

### What happens after finalization

Consensus finalization flows from Prysm’s view of the beacon chain into Nethermind’s view of canonical execution history. Prysm tells Nethermind which execution payload is now safe to treat as finalized. Nethermind retains the execution chain and state needed to validate future payloads. This is why both clients need persistent storage and why restarting only one half of the pair can leave the node temporarily unable to perform its full role.

### What does *not* flow across the Engine API

- Validator private keys, keystores, passwords, and withdrawal credentials.
- Validator signatures; those flow between Prysm Validator and the remote signer.
- General public JSON-RPC requests; the example explicitly disables ordinary Nethermind JSON-RPC.
- A blanket trust decision. Each client validates the part of the protocol it owns.

## 2. A node becomes a validator only when it can perform duties

A synchronized Nethermind and Prysm Beacon pair is a **node**. It can verify the network and provide the information needed for validator work, but it has no permission to attest or propose a block simply because it is online.

A validator joins the consensus process after its public key is registered through the network’s deposit process and the network activates it. Once active, it is assigned duties such as:

- **Attestation:** voting that the validator observed a particular block and checkpoint.
- **Block proposal:** proposing a block when selected for a slot.
- **Sync-committee participation:** helping lightweight clients follow the chain during an assigned period.

The important distinction is that a duty is an instruction from the protocol, while a signature is an authorization from a private key. The system should keep those two things separate.

## 3. Prysm Validator schedules the work; the signer holds the key

Prysm Validator watches the Beacon node for duties. When it has a valid duty, it builds the message that needs signing. It should not need to read a keystore or a withdrawal credential.

Instead, it sends the message to a **remote signer**. The remote signer owns the sensitive key operation and returns only the signature.

```text
Prysm Validator → “Please sign this attestation for validator A”
Remote signer  → verifies policy and prior signing history
Remote signer  → returns a signature, or refuses the request
```

This arrangement reduces the impact of a compromised validator client. An attacker who compromises the duty scheduler does not automatically obtain an exportable private key. In this repository, the signer is scoped to a single validator set, while the validator client has no keystore, direct Vault route, or permission to change its signing fence. See the [validator key-operation model](../operations/validator-key-operations.md).

## 4. Why keys, withdrawal credentials, and deposit data are different

Several items are commonly called “the validator key,” but they serve different purposes:

| Asset | Purpose |
| --- | --- |
| Signing key | Signs attestations, proposals, and other consensus messages. |
| Encrypted keystore and password | Protect the signing key at rest. |
| Withdrawal credential | Controls the withdrawal destination; it has a separate custody role. |
| Deposit data | Public information that binds the validator public key and withdrawal path for the network. |
| Slashing history | A record of what has already been signed. |

### Signing key

The signing key is a BLS private key associated with one validator public key. It authorizes consensus actions: an attestation says “this validator observed and voted for this chain state,” while a proposal says “this validator produced this block for this slot.” The network verifies the resulting signature using the public key; it never needs the private key.

This makes the signing key the most immediately dangerous asset to expose. Anyone who can use it may be able to produce validator signatures. That does not mean the key should be copied into every component that needs a signature. In this architecture, the remote signer uses it while Prysm Validator only asks for a specific, protocol-shaped signature.

### Encrypted keystore and password

An encrypted keystore is a file that stores the signing key in encrypted form, commonly using the EIP-2335 format. It is not the same thing as the raw key: without its password, the encrypted contents should not be usable; with its password, it can be decrypted and loaded by authorized signing software.

The keystore and its password are deliberately separate. Storing them beside each other in source control, a container image, an application manifest, or a chat transcript defeats much of the protection encryption provides. A remote-signer design limits their use to the signer’s controlled environment instead of giving them to the Beacon node, validator client, monitoring tools, or CI system.

### Withdrawal credential

The withdrawal credential commits the validator to a withdrawal destination. It is not used to sign routine attestations or block proposals. In the common type-1 form, it is derived from an Ethereum execution address and tells the protocol where eligible withdrawals should go.

Its role is different from the signing key’s role. Losing access to a signing key affects validator duties; mishandling a withdrawal credential can affect the destination of funds. For that reason, it belongs in a separate, higher-custody recovery process and is never an ordinary configuration value for Nethermind, Prysm Beacon, Prysm Validator, or the remote signer.

### Deposit data

Deposit data is the public package used to register a validator with the network. It includes the validator public key, withdrawal credentials, a signature proving the deposit was prepared by the key holder, and the deposit amount. It does not reveal the signing private key or the keystore password.

The important learning point is that deposit data still needs independent verification. An operator should confirm that the public key, amount, and withdrawal path describe the intended validator before submitting a deposit. The repository's Hoodi validator checks exactly one entry and `32,000,000,000` Gwei, then writes public-only evidence; it does not submit a transaction or act as a wallet.

### Slashing history

Slashing history, often called slashing-protection interchange data, records prior validator signatures in a portable form. It lets a replacement signer answer a safety question before signing: “Would this conflict with something this validator already signed?”

It is not secret in the same way as a private key, but it is critical integrity data. If it is lost, a replacement signer may not know that a proposed attestation or block conflicts with an earlier action. If it is copied incompletely, recovery can be just as dangerous. This is why a failover preserves, verifies, and imports the history before enabling a replacement signing path.

That separation is a safety property. The running node does not need a withdrawal credential. Git does not need a keystore. A monitoring system does not need a password. The repository’s [deposit-data validator](../../scripts/ops/validate-hoodi-deposit-data.sh) checks public deposit facts—such as one Hoodi entry and `32,000,000,000` Gwei—without submitting a transaction or using a wallet.

## 5. Slashing protection prevents conflicting signatures

Validators can be penalized for signing conflicting messages. This is called **slashing**. One common danger is failover: an operator starts a replacement system while the old system is still capable of signing.

The remote signer’s slashing database is the final protection against this. Before it signs, the signer checks whether the requested message would conflict with something it already signed. That history must be retained and transferred carefully during recovery.

A Kubernetes Lease can add a second layer called **fencing**. It gives one designated validator-client path authority to reach the signer at a time. But a Lease is not a replacement for slashing history: it cannot undo a signing request already accepted by the signer.

The underlying principle is simple:

```text
Only one active signing path
        +
Durable memory of previous signatures
        =
Safer validator operation
```

The repository’s [fencing model](../../deploy/validator/client-lease-fence-security-model.md) documents this distinction in more detail.

## 6. What failure containment means

If a signer or validator client may be compromised, the goal is first to make signing impossible, then to remove future access, and finally to preserve evidence for safe recovery.

Fencing prevents the active client path from using the signer. Revoking an identity or policy reduces future access, but may not invalidate a token already issued or a key already loaded by a signer. Slashing history and public audit metadata are preserved because they are needed to decide whether recovery is safe.

This is why validator operations are more cautious than ordinary web-service restarts. Availability is important, but avoiding a conflicting signature is more important.

## Summary

Nethermind verifies execution. Prysm Beacon verifies consensus and coordinates with Nethermind through the Engine API. Prysm Validator turns protocol duties into signing requests. A remote signer performs the sensitive key operation, while a slashing database prevents conflicting signatures.

The mechanism is designed around separation: separate layers, separate responsibilities, separate custody assets, and a separate record of signing history. That separation is what lets a validator participate in consensus without making its private key an ordinary application dependency.
