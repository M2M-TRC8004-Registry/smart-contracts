# TRC-8004: ERC-8004 Superset Specification & Roadmap

**Status:** In Development
**Chain:** TRON
**Base Standard:** [ERC-8004 (Trustless Agents)](https://eips.ethereum.org/EIPS/eip-8004)
**Date:** February 2026

---

## What is TRC-8004?

TRC-8004 is a TRON implementation of the ERC-8004 agent identity standard. It implements the same three on-chain registries — Identity, Reputation, and Validation — but extends each with features that address known gaps in the base specification.

The goal is full interface-level compatibility with ERC-8004 while providing practical improvements where the standard falls short.

---

## Current State

TRC-8004 is currently deployed on TRON mainnet and Shasta testnet with three contracts:

- **EnhancedIdentityRegistry** — ERC-721 based agent identity with on-chain metadata
- **ReputationRegistry** — Sentiment-based feedback with on-chain text storage and response threading
- **ValidationRegistry** — Deterministic request ID generation with explicit state machine

These contracts were built independently from ERC-8004 and diverge from the spec in several areas. Some of these divergences are gaps to close. Others are deliberate improvements we intend to keep.

---

## Where TRC-8004 Extends ERC-8004

### 1. On-Chain Feedback Permanence

ERC-8004 stores feedback detail off-chain via `feedbackURI`. If the URI becomes unavailable — IPFS node goes offline, server goes down, content gets deleted — the feedback record is reduced to a hash with no readable content.

TRC-8004 stores `feedbackText` directly on-chain. The feedback content is permanent and always available without external dependencies. TRON's energy model makes this economically viable where Ethereum L1 gas costs would not.

We will add `feedbackURI` and `feedbackHash` for ERC-8004 compatibility. On-chain text remains as the primary record.

### 2. On-Chain Response Threading

ERC-8004's `appendResponse()` stores responses off-chain via `responseURI` + `responseHash`. Reading a response requires fetching external content and verifying the hash.

TRC-8004 stores response text on-chain with timestamps. The complete feedback conversation — original comment and all responses — is readable in a single contract call via `getFeedbackResponses()`.

We will add `responseURI` and `responseHash` for compatibility. On-chain text remains.

### 3. Deterministic Collision-Free Request IDs

ERC-8004 requires callers to supply their own `bytes32 requestHash` when creating validation requests. This places the burden of uniqueness on the caller and introduces collision and replay risks.

TRC-8004 generates request IDs deterministically on-chain:

```
requestId = keccak256(sender, validator, agentId, dataHash, nonce, chainId)
```

The per-requester nonce is auto-incremented. Collisions are impossible by construction. The `chainId` component prevents cross-chain replay.

### 4. Explicit Validation State Machine

ERC-8004's Validation Registry (marked **EXPERIMENTAL** in the spec) uses a `uint8 response` value from 0 to 100 with no defined semantics. The standard does not specify what constitutes a pass or fail, leaving every consumer to define their own thresholds.

TRC-8004 uses an explicit state machine:

```
Pending → Completed | Rejected | Cancelled
```

There is no ambiguity. Consumers can branch on status directly.

We will add an optional `response` numeric value and `tag` field for ERC-8004 compatibility. The status enum remains the primary signal.

### 5. Validation Cancellation

ERC-8004 has no mechanism to cancel a pending validation request. Once submitted, requests persist in storage indefinitely.

TRC-8004 provides `cancelRequest(bytes32 requestId)` — only callable by the original requester, only when the request is still pending.

### 6. Requester-Indexed Validation Queries

ERC-8004 indexes validation requests by agent and by validator, but not by requester. There is no on-chain way for a requester to retrieve their own pending requests.

TRC-8004 maintains a `_requestsByRequester` mapping and exposes `getRequesterRequests(address)`.

### 7. Per-Client Feedback Tracking

ERC-8004 removed `feedbackAuth` (pre-authorization signatures) in the v1.0 update, making feedback fully permissionless. The specification provides no on-chain Sybil resistance mechanism.

TRC-8004 tracks `feedbackCountByClient` — a per-agent mapping of how many feedbacks each address has submitted. This provides an on-chain signal for detecting spam patterns without restricting permissionless access.

### 8. Sentiment + Numeric Value (Dual Model)

ERC-8004 uses a signed fixed-point value (`int128 value` + `uint8 valueDecimals`) for feedback. This is flexible but opaque — consumers need context to interpret what a given value means, and numeric averages are susceptible to manipulation.

TRC-8004 will support both:
- **Sentiment** (Positive / Neutral / Negative) — human-readable, resistant to gaming
- **Numeric value + decimals** — ERC-8004 compatible, supports arbitrary metrics

Both are stored per feedback. Consumers use whichever model suits their use case.

### 9. Full Struct Returns for On-Chain Composability

ERC-8004's `getRequest()` returns a limited set of fields. TRC-8004 returns the complete `ValidationRequest` struct, enabling other on-chain contracts to consume validation results directly without relying on event indexing.

### 10. No Admin Keys

TRC-8004 contracts have zero admin roles, zero pausability, and zero upgradeability. All authorization is derived from token ownership, validator assignment, or agent wallet delegation. There is no privileged key that could be compromised or used to censor agents.

---

## ERC-8004 Compatibility: What We're Adding

### Identity Registry

| Addition | Purpose |
|----------|---------|
| `register()` (no args) | Minimal registration — matches spec overload |
| `register(string agentURI)` | URI-only registration — matches spec overload |
| `register(string agentURI, MetadataEntry[] metadata)` | Structured metadata at registration — matches spec |
| `setAgentURI(uint256 agentId, string newURI)` | Update agent metadata URI post-registration |
| `setMetadata(uint256 agentId, string key, bytes value)` | Per-key on-chain metadata updates |
| `setAgentWallet()` with EIP-712 signature verification | Proof-of-control for wallet delegation |
| `unsetAgentWallet(uint256 agentId)` | Clear agent wallet |
| Auto-clear `agentWallet` on NFT transfer | Security: wallet should not persist through ownership changes |
| `agentExists()` / `getAgentWallet()` | Spec-compatible function names (existing names retained as aliases) |
| Aligned event signatures | `Registered`, `URIUpdated`, `MetadataSet`, `AgentWalletSet` |

**Existing TRC-8004 features retained as extensions:**
- `metadataHashOf(uint256)` — on-chain integrity verification for metadata
- `registerWithOnChainMetadata()` — batch key-value metadata at registration time

### Reputation Registry

| Addition | Purpose |
|----------|---------|
| `int128 value` + `uint8 valueDecimals` per feedback | ERC-8004 numeric value support |
| `string tag1`, `string tag2`, `string endpoint` | Feedback categorization and endpoint linking |
| `feedbackURI` + `feedbackHash` per feedback | Off-chain detail reference |
| `responseURI` + `responseHash` per response | Off-chain response reference |
| `getClients(uint256 agentId)` | List all addresses that have given feedback |
| `getLastIndex(uint256 agentId, address client)` | Per-client feedback index |
| `getSummary(agentId, clientAddresses[], tag1, tag2)` | Filtered summary with Sybil-resistant client scoping |
| `readAllFeedback()` | Bulk filtered query |
| `getIdentityRegistry()` | Getter for linked Identity Registry |
| Aligned event signatures | `NewFeedback`, `FeedbackRevoked`, `ResponseAppended` with all spec fields |

**Existing TRC-8004 features retained as extensions:**
- `feedbackText` — on-chain feedback content
- `responseText` — on-chain response content
- `Sentiment` enum — alongside numeric value
- `feedbackCountByClient` — per-client tracking
- `getFeedbackResponses()` — on-chain conversation threads
- Unfiltered `getSummary(agentId)` — returns both sentiment counts and numeric aggregates

### Validation Registry

| Addition | Purpose |
|----------|---------|
| `string tag` on responses | Categorization of validation results |
| `uint8 response` value on responses | ERC-8004 numeric response (0-100) alongside status |
| `requestExists(bytes32 requestId)` | Convenience check |
| `getValidationStatus(bytes32 requestId)` | Spec-compatible view |
| `getSummary(agentId, validatorAddresses[], tag)` | Filtered summary |
| `getIdentityRegistry()` | Getter for linked Identity Registry |
| Spec-compatible param order alias for `validationRequest()` | `(validator, agentId, ...)` ordering |
| Spec-compatible events alongside existing events | `ValidationResponse` emitted in addition to `ValidationCompleted` / `Rejected` / `Cancelled` |

**Existing TRC-8004 features retained as extensions:**
- Deterministic on-chain `requestId` generation
- `cancelRequest()` — validation lifecycle management
- `getRequesterRequests()` — requester-indexed queries
- Full `ValidationRequest` struct returns
- `getSummaryForAgent()` — unfiltered, returns status counts

### Off-Chain Metadata Schema

Agent metadata stored at `agentURI` will conform to the ERC-8004 registration file schema:

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
  "name": "Agent Name",
  "description": "...",
  "image": "https://...",
  "services": [
    {
      "name": "Service Name",
      "endpoint": "https://agent.example.com/a2a",
      "version": "1.0.0",
      "skills": [],
      "domains": []
    }
  ],
  "active": true,
  "registrations": [
    { "agentId": 42, "agentRegistry": "trc8004:728126428:TXXX..." }
  ],
  "supportedTrust": ["reputation"]
}
```

---

## Planned Extensions (Beyond ERC-8004)

### Agent Deactivation

ERC-8004 has no on-chain mechanism to mark agents as inactive, compromised, or deprecated. The `active` flag exists only in the off-chain JSON metadata, which can become stale or unavailable.

TRC-8004 will add on-chain lifecycle management to the Identity Registry:

- `deactivate(uint256 agentId)` — owner-only
- `reactivate(uint256 agentId)` — owner-only
- `isActive(uint256 agentId)` — view

### Incident Reporting

An on-chain mechanism for reporting agent failures, disputes, or malicious behavior. This has been [proposed on Ethereum Magicians](https://ethereum-magicians.org/t/erc-8004-trustless-agents/25098) but is not part of the ERC-8004 specification.

TRC-8004 plans a fourth registry contract:

- `reportIncident(uint256 agentId, string incidentURI, bytes32 incidentHash, string category)`
- `respondToIncident(uint256 incidentId, string responseURI, bytes32 responseHash)`
- `resolveIncident(uint256 incidentId, uint8 resolution)`
- `getIncidents(uint256 agentId)`

### Self-Feedback Prevention (Enforced)

ERC-8004 states that agent owners MUST NOT give self-feedback, but enforcement in the reference implementation is not clearly documented. TRC-8004 enforces this check on-chain — `giveFeedback()` reverts if the caller is the agent owner.

---

## Summary

| | ERC-8004 | TRC-8004 |
|--|---------|---------|
| **Identity** | Standard ERC-721 agent registry | ERC-721 + on-chain metadata hash + batch metadata + agent deactivation |
| **Reputation** | Numeric value + off-chain URI | Numeric value + sentiment + on-chain text + response threading + per-client tracking |
| **Validation** | Ambiguous 0-100 response, caller-supplied hashes | State machine + numeric response + deterministic IDs + cancel flow + requester queries |
| **Incident Reporting** | Not in spec | Planned 4th registry |
| **Admin Keys** | Reference implementation uses ownership patterns | None |
| **ERC-8004 Compatible** | — | Yes, at every interface |

TRC-8004 is a superset of ERC-8004. Fully compatible at the interface level, with practical extensions for the problems the base standard does not yet solve.

---

## Links

- [ERC-8004 Specification](https://eips.ethereum.org/EIPS/eip-8004)
- [ERC-8004 Discussion (Ethereum Magicians)](https://ethereum-magicians.org/t/erc-8004-trustless-agents/25098)
- [ERC-8004 Reference Implementation](https://github.com/ChaosChain/trustless-agents-erc-ri)
