# M2M TRC-8004 Agent Registry — Smart Contracts

On-chain identity, reputation, validation, and incident reporting for AI agents on TRON. Built on [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) with practical extensions.

## What is TRC-8004?

TRC-8004 is a TRON implementation of the [ERC-8004 agent identity standard](https://eips.ethereum.org/EIPS/eip-8004). It provides four smart contracts that give AI agents a verifiable on-chain identity, a reputation system, a validation workflow, and an incident reporting mechanism.

| Contract | What it does |
|----------|-------------|
| **EnhancedIdentityRegistry** | Register agents as ERC-721 NFTs with metadata, wallet delegation, and lifecycle management |
| **ReputationRegistry** | Collect feedback with sentiment + numeric scores, on-chain text, and response threading |
| **ValidationRegistry** | Submit, complete, reject, or cancel validation requests with deterministic IDs |
| **IncidentRegistry** | Report, respond to, and resolve incidents against agents |

All four contracts are deployed on **TRON mainnet** and **Shasta testnet**. TRC-8004 is fully compatible with ERC-8004 at the interface level, with 10 extensions where the base standard falls short.

## Why TRC-8004 over ERC-8004?

TRC-8004 is a superset — everything in ERC-8004 works, plus:

- **On-chain feedback text** — Feedback content stored permanently on-chain, not just off-chain URIs that can disappear
- **Response threading** — Complete feedback conversations readable in a single contract call
- **Deterministic request IDs** — Generated on-chain with nonces, no collision or replay risk
- **Explicit validation state machine** — `Pending → Completed | Rejected | Cancelled` instead of ambiguous 0-100 values
- **Validation cancellation** — Requesters can cancel their own pending requests
- **Dual feedback model** — Sentiment enum (Positive/Neutral/Negative) alongside ERC-8004 numeric values
- **Per-client tracking** — On-chain Sybil detection signal without restricting permissionless access
- **Agent deactivation** — On-chain lifecycle management (deactivate/reactivate)
- **Incident reporting** — 4th registry contract not present in ERC-8004 ([proposed on Ethereum Magicians](https://ethereum-magicians.org/t/erc-8004-trustless-agents/25098))
- **No admin keys** — Zero admin roles, zero pausability, zero upgradeability

---

## Where TRC-8004 Extends ERC-8004

### 1. On-Chain Feedback Permanence

ERC-8004 stores feedback detail off-chain via `feedbackURI`. If the URI becomes unavailable — IPFS node goes offline, server goes down, content gets deleted — the feedback record is reduced to a hash with no readable content.

TRC-8004 stores `feedbackText` directly on-chain. The feedback content is permanent and always available without external dependencies. TRON's energy model makes this economically viable where Ethereum L1 gas costs would not.

`feedbackURI` and `feedbackHash` are also supported for ERC-8004 compatibility. On-chain text remains as the primary record.

### 2. On-Chain Response Threading

ERC-8004's `appendResponse()` stores responses off-chain via `responseURI` + `responseHash`. Reading a response requires fetching external content and verifying the hash.

TRC-8004 stores response text on-chain with timestamps. The complete feedback conversation — original comment and all responses — is readable in a single contract call via `getFeedbackResponses()`.

`responseURI` and `responseHash` are also supported for compatibility. On-chain text remains.

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

An optional `response` numeric value (0-100) and `tag` field are supported for ERC-8004 compatibility. The status enum remains the primary signal.

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

TRC-8004 supports both:
- **Sentiment** (Positive / Neutral / Negative) — human-readable, resistant to gaming
- **Numeric value + decimals** — ERC-8004 compatible, supports arbitrary metrics

Both are stored per feedback. Consumers use whichever model suits their use case.

### 9. Full Struct Returns for On-Chain Composability

ERC-8004's `getRequest()` returns a limited set of fields. TRC-8004 returns the complete `ValidationRequest` struct, enabling other on-chain contracts to consume validation results directly without relying on event indexing.

### 10. No Admin Keys

TRC-8004 contracts have zero admin roles, zero pausability, and zero upgradeability. All authorization is derived from token ownership, validator assignment, or agent wallet delegation. There is no privileged key that could be compromised or used to censor agents.

---

## ERC-8004 Compatibility

### Identity Registry

| Feature | Purpose |
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

| Feature | Purpose |
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
| Self-feedback prevention | Enforced on-chain for both owner AND agentWallet |

**Existing TRC-8004 features retained as extensions:**
- `feedbackText` — on-chain feedback content
- `responseText` — on-chain response content
- `Sentiment` enum — alongside numeric value
- `feedbackCountByClient` — per-client tracking
- `getFeedbackResponses()` — on-chain conversation threads
- Unfiltered `getSummary(agentId)` — returns both sentiment counts and numeric aggregates

### Validation Registry

| Feature | Purpose |
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

Agent metadata stored at `agentURI` conforms to the ERC-8004 registration file schema:

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

## M2M Token

M2M is a TRC20 token created by the developers of the TRC-8004 Agent Registry. It is a project token associated with the M2M registry platform and is not part of the TRC-8004 standard itself.

| | |
|--|--|
| **Contract** | [`TSH8XLQRMrCTTdCr3rUH2zUiuDZQjfmHaX`](https://tronscan.org/#/contract/TSH8XLQRMrCTTdCr3rUH2zUiuDZQjfmHaX) |
| **Network** | TRON Mainnet |
| **Standard** | TRC20 |

---

## Getting Started

### Option 1: Use the Python SDK (recommended)

```bash
pip install trc8004-m2m
```

```python
from trc8004_m2m import AgentRegistry

# Read-only (no private key needed)
registry = AgentRegistry(network="mainnet")

# Register an agent
registry = AgentRegistry(private_key="your_hex_key", network="mainnet")
agent_id = await registry.register_agent(
    name="My Agent",
    description="An AI agent for ...",
    skills=[{"skill_id": "analysis", "skill_name": "Analysis"}]
)
```

See the [SDK repository](https://github.com/M2M-TRC8004-Registry/trc8004-m2m-sdk) for full documentation.

### Option 2: Call contracts directly

Use the ABI files in `abi/` with any TRON library (tronpy, tronweb, etc.):

```python
from tronpy import Tron

client = Tron(network="mainnet")
identity = client.get_contract("THmfi8uJuUpTfUmYLDX7UD1KaE4P6HKgqA")

# Check if an agent exists
exists = identity.functions.exists(1)

# Get agent metadata URI
uri = identity.functions.tokenURI(1)

# Get reputation summary
reputation = client.get_contract("TV8KWmp8qcj55sjs1NSjVxmRmZP7CYzNxH")
summary = reputation.functions.getSummary(1)  # (total, active, revoked, positive, neutral, negative)
```

---

## Deployed Contracts

### Mainnet

| Contract | Address |
|----------|---------|
| EnhancedIdentityRegistry | [`THmfi8uJuUpTfUmYLDX7UD1KaE4P6HKgqA`](https://tronscan.org/#/contract/THmfi8uJuUpTfUmYLDX7UD1KaE4P6HKgqA) |
| ValidationRegistry | [`TCoJA4BYXWZhp5eanCchMw67VA83tQ83n1`](https://tronscan.org/#/contract/TCoJA4BYXWZhp5eanCchMw67VA83tQ83n1) |
| ReputationRegistry | [`TV8KWmp8qcj55sjs1NSjVxmRmZP7CYzNxH`](https://tronscan.org/#/contract/TV8KWmp8qcj55sjs1NSjVxmRmZP7CYzNxH) |
| IncidentRegistry | [`TJ26Pu24ar7Qdh9Bm6tbBVdtzCJkbxS5eR`](https://tronscan.org/#/contract/TJ26Pu24ar7Qdh9Bm6tbBVdtzCJkbxS5eR) |
| M2M TRC20 Token | [`TSH8XLQRMrCTTdCr3rUH2zUiuDZQjfmHaX`](https://tronscan.org/#/contract/TSH8XLQRMrCTTdCr3rUH2zUiuDZQjfmHaX) |

### Shasta Testnet

| Contract | Address |
|----------|---------|
| EnhancedIdentityRegistry | [`TFKNqk9bjwWp5uRiiGimqfLhVQB8jSxYi7`](https://shasta.tronscan.org/#/contract/TFKNqk9bjwWp5uRiiGimqfLhVQB8jSxYi7) |
| ValidationRegistry | [`TPgGWWyUdxNryUCN49TdT4b3F4WB3Edr16`](https://shasta.tronscan.org/#/contract/TPgGWWyUdxNryUCN49TdT4b3F4WB3Edr16) |
| ReputationRegistry | [`TRaYogyr2qc7WgsmuVF5Js39aCmoG7vZrA`](https://shasta.tronscan.org/#/contract/TRaYogyr2qc7WgsmuVF5Js39aCmoG7vZrA) |
| IncidentRegistry | [`TPB59NFdypBpkJtWH7yE8XenKrdT1Q4g4s`](https://shasta.tronscan.org/#/contract/TPB59NFdypBpkJtWH7yE8XenKrdT1Q4g4s) |

---

## Contracts

### 1. EnhancedIdentityRegistry.sol

**ERC-721 NFT** for agent ownership and identity.

**Features**:
- Each agent is an NFT (token ID = agent ID)
- Stores tokenURI (IPFS/HTTP) pointing to off-chain metadata
- Metadata hash stored on-chain for integrity verification
- Optional on-chain key-value metadata storage (`setMetadata` / `getMetadata`)
- Agent wallet delegation with EIP-712 proof-of-control (`setAgentWalletSigned`)
- Agent lifecycle management (`deactivate` / `reactivate` / `isActive`)
- Auto-clear agent wallet on NFT transfer
- Multiple registration overloads (0-arg, 2-arg with URI + hash)
- Full ERC-721 compliance (transfer, approve, safeTransfer with receiver check)
- ERC-165 interface detection

**Key Functions**:
| Function | Access | Description |
|----------|--------|-------------|
| `register(uri, metadataHash)` | Anyone | Mint a new agent NFT with URI and hash. Returns `agentId`. |
| `register()` | Anyone | Minimal registration (no URI or hash). Returns `agentId`. |
| `setAgentURI(agentId, newURI)` | Owner | Update agent metadata URI post-registration. |
| `setMetadata(agentId, key, value)` | Owner | Set on-chain key-value metadata (bytes). |
| `getMetadata(agentId, key)` | View | Read on-chain metadata by key. |
| `setAgentWallet(agentId, wallet)` | Owner | Legacy wallet delegation (unset-only for security). |
| `setAgentWalletSigned(agentId, wallet, nonce, v, r, s)` | Owner | EIP-712 signed wallet delegation with proof-of-control. |
| `unsetAgentWallet(agentId)` | Owner | Clear delegated wallet. |
| `deactivate(agentId)` | Owner | Mark agent as inactive. |
| `reactivate(agentId)` | Owner | Reactivate a deactivated agent. |
| `isActive(agentId)` | View | Check if agent is active. |
| `ownerOf(agentId)` | View | Get agent owner address. |
| `tokenURI(agentId)` | View | Get metadata URI. |
| `agentWalletOf(agentId)` | View | Get delegated wallet address. |
| `exists(tokenId)` | View | Check if an agent exists. |
| `totalAgents()` | View | Get total registered agent count. |
| `balanceOf(owner)` | View | Get number of agents owned by address. |

Standard ERC-721: `transferFrom`, `safeTransferFrom`, `approve`, `getApproved`, `setApprovalForAll`, `isApprovedForAll`

**Events**: `AgentRegistered`, `AgentWalletUpdated`, `AgentDeactivated`, `AgentReactivated`, `Transfer`, `Approval`, `ApprovalForAll`

---

### 2. ValidationRegistry.sol

**Validation workflow** for agent capabilities.

**Features**:
- Anyone can submit validation requests for a registered agent
- Designated validator can complete or reject the request
- Requester can cancel pending requests
- Nonce-based unique request IDs (no collisions)
- Off-chain data linked via URIs, integrity verified via hashes
- Status-based tracking: Pending, Completed, Rejected, Cancelled
- Optional response value (0-100) and tag on completion/rejection
- Query requests by agent, validator, or requester

**Key Functions**:
| Function | Access | Description |
|----------|--------|-------------|
| `validationRequest(agentId, validator, requestURI, requestDataHash)` | Anyone | Create a validation request. Returns `requestId`. |
| `completeValidation(requestId, resultURI, resultHash)` | Validator only | Mark request as completed with result. |
| `completeValidation(requestId, resultURI, resultHash, responseValue, tag)` | Validator only | Complete with optional numeric value (0-100) and tag. |
| `rejectValidation(requestId, resultURI, reasonHash)` | Validator only | Reject request with reason. |
| `rejectValidation(requestId, resultURI, reasonHash, responseValue, tag)` | Validator only | Reject with optional numeric value and tag. |
| `cancelRequest(requestId)` | Requester only | Cancel a pending request. |
| `requestExists(requestId)` | View | Check if a request exists. |
| `getRequest(requestId)` | View | Get full request details. |
| `getValidationStatus(requestId)` | View | Get request status. |
| `getSummaryForAgent(agentId)` | View | Returns `(total, pending, completed, rejected, cancelled)` counts. |
| `getSummary(agentId, validators[], tag)` | View | Filtered summary by validator addresses and/or tag. |
| `getAgentRequests(agentId)` | View | Get all request IDs for an agent. |
| `getRequesterRequests(address)` | View | Get all request IDs by requester. |
| `getValidatorRequests(address)` | View | Get all request IDs by validator. |

**Events**: `ValidationRequested`, `ValidationCompleted`, `ValidationRejected`, `ValidationCancelled`, `ValidationResponse`

---

### 3. ReputationRegistry.sol

**Feedback and reputation** system.

**Features**:
- Any address can submit feedback with text and sentiment (Positive / Neutral / Negative)
- Dual model: sentiment enum + optional numeric value with decimals (ERC-8004 compatible)
- Optional tags, endpoint, feedbackURI, and feedbackHash per feedback
- Clients can revoke their own feedback
- Agent owners (or delegated wallets) can respond to feedback in a thread
- Self-feedback prevention (enforced on-chain for both owner and agentWallet)
- Per-client feedback tracking (`getClients`, `feedbackCountByClient`)
- Summary statistics: total, active, revoked, positive, neutral, negative counts
- Filtered summaries by client addresses, tags

**Sentiment Enum**: `Neutral = 0`, `Positive = 1`, `Negative = 2`

**Key Functions**:
| Function | Access | Description |
|----------|--------|-------------|
| `giveFeedback(agentId, feedbackText, sentiment)` | Anyone (not self) | Submit basic feedback. Returns `feedbackIndex`. |
| `giveFeedback(FeedbackInput)` | Anyone (not self) | Full feedback with value, tags, endpoint, URI, hash. |
| `revokeFeedback(agentId, feedbackIndex)` | Feedback author | Revoke previously submitted feedback. |
| `appendResponse(agentId, feedbackIndex, responseText)` | Agent owner / wallet | Respond to feedback (thread-based). |
| `appendResponse(agentId, feedbackIndex, responseText, responseURI, responseHash, value)` | Agent owner / wallet | Full response with URI, hash, and value. |
| `getFeedbackCount(agentId)` | View | Get total feedback count for agent. |
| `getFeedback(agentId, feedbackIndex)` | View | Returns core fields: `(client, feedbackText, sentiment, timestamp, revoked, responseCount)`. |
| `getFeedbackExtended(agentId, feedbackIndex)` | View | Returns extended fields: `(value, valueDecimals, tag1, tag2, endpoint, feedbackURI)`. |
| `getFeedbackResponses(agentId, feedbackIndex)` | View | Returns `(responses[], responseTimestamps[])`. |
| `getSummary(agentId)` | View | Returns `(total, active, revoked, positive, neutral, negative)` counts. |
| `getSummary(agentId, clients[], tag1, tag2)` | View | Filtered summary scoped to specific clients and/or tags. |
| `getClients(agentId)` | View | List all addresses that have given feedback. |

**Events**: `NewFeedback`, `NewFeedbackDetail`, `FeedbackRevoked`, `ResponseAppended`

---

### 4. IncidentRegistry.sol

**On-chain incident reporting** for agent failures, disputes, or malicious behavior.

Proposed by SumeetChougule on [Ethereum Magicians](https://ethereum-magicians.org/t/erc-8004-trustless-agents/25098) — TRC-8004 is the first implementation.

**Features**:
- Anyone can report an incident against a registered agent
- Agent owner (or delegated wallet) can respond
- Reporter can mark as resolved with a resolution type
- Lifecycle: Open → Responded → Resolved
- Category-based classification (failure, security, performance, bug, etc.)
- Summary statistics per agent

**Status Enum**: `Open = 0`, `Responded = 1`, `Resolved = 2`

**Resolution Enum**: `None = 0`, `Acknowledged = 1`, `Disputed = 2`, `Fixed = 3`, `NotABug = 4`, `Duplicate = 5`

**Key Functions**:
| Function | Access | Description |
|----------|--------|-------------|
| `reportIncident(agentId, incidentURI, incidentHash, category)` | Anyone | Report an incident. Returns `incidentId`. |
| `respondToIncident(incidentId, responseURI, responseHash)` | Agent owner / wallet | Respond to an open incident. |
| `resolveIncident(incidentId, resolution)` | Reporter only | Resolve a responded incident. |
| `getIncident(incidentId)` | View | Get full incident details. |
| `getIncidents(agentId)` | View | Get all incident IDs for an agent. |
| `getIncidentCount(agentId)` | View | Get total incident count for agent. |
| `getReporterIncidents(address)` | View | Get all incidents reported by address. |
| `getSummary(agentId)` | View | Returns `(total, open, responded, resolved)` counts. |

**Events**: `IncidentReported`, `IncidentResponded`, `IncidentResolved`

---

## ABIs

Minimal ABI files (interface-only, no bytecode) are provided in the `abi/` directory for integration:

- `abi/EnhancedIdentityRegistry.json`
- `abi/ValidationRegistry.json`
- `abi/ReputationRegistry.json`
- `abi/IncidentRegistry.json`

## Technical Details

- **Solidity**: 0.8.20
- **EVM version**: Paris
- **Compiler optimization**: Enabled, 200 runs, `viaIR: true`
- **Toolchain**: TronBox
- **Token standard**: ERC-721 (EnhancedIdentityRegistry)

## Project Structure

```
smart-contracts/
├── abi/
│   ├── EnhancedIdentityRegistry.json    # Minimal ABI (interface only)
│   ├── ValidationRegistry.json          # Minimal ABI (interface only)
│   ├── ReputationRegistry.json          # Minimal ABI (interface only)
│   └── IncidentRegistry.json            # Minimal ABI (interface only)
├── contracts/
│   ├── EnhancedIdentityRegistry.sol     # Agent NFTs (ERC-721)
│   ├── ValidationRegistry.sol           # Validation workflow
│   ├── ReputationRegistry.sol           # Feedback & reputation
│   └── IncidentRegistry.sol             # Incident reporting
├── migrations/
│   ├── 2_deploy_contracts.js            # Deploy Identity + Validation + Reputation
│   ├── 3_deploy_remaining.js            # Deploy against existing Identity
│   └── 4_deploy_incident.js             # Deploy IncidentRegistry
├── .env.example                         # Environment template
├── .gitignore
├── LICENSE
├── package.json
├── README.md
└── tronbox.js.example                   # TronBox config template
```

## Security

**Core protections**:
- No reentrancy vulnerabilities
- Access control on all state-changing functions
- Input validation on all parameters
- Safe math (Solidity 0.8+ built-in overflow checks)
- Event emission for all state changes
- Safe ERC-721 transfers with receiver check
- Agent existence validated across all registries
- No admin keys, no pausability, no upgradeability

**v2 hardening**:
- EIP-2 signature malleability protection (`v` must be 27 or 28, `s` in lower half)
- EIP-712 nonce replay protection for wallet delegation
- `ecrecover` zero-address defense
- Legacy `setAgentWallet` restricted to unset-only (proof-of-control via `setAgentWalletSigned` required for non-zero)
- Self-feedback prevention checks both owner AND agentWallet
- `abi.encode` (not `abi.encodePacked`) for request ID generation
- `resolveIncident` requires `Responded` status first (no skip to Resolved)
- String length limits: URIs 2048, text 2048, tags 128, endpoint 512, category 128, metadata keys 128
- Response thread cap: 30 per feedback

---

## ERC-8004 vs TRC-8004 Summary

| | ERC-8004 | TRC-8004 |
|--|---------|---------|
| **Identity** | Standard ERC-721 agent registry | ERC-721 + on-chain metadata hash + batch metadata + agent deactivation + EIP-712 wallet delegation |
| **Reputation** | Numeric value + off-chain URI | Numeric value + sentiment + on-chain text + response threading + per-client tracking + self-feedback prevention |
| **Validation** | Ambiguous 0-100 response, caller-supplied hashes | State machine + numeric response + deterministic IDs + cancel flow + requester queries + filtered summaries |
| **Incident Reporting** | Not in spec | 4th registry (deployed) — report, respond, resolve lifecycle |
| **Admin Keys** | Reference implementation uses ownership patterns | None |
| **ERC-8004 Compatible** | — | Yes, at every interface |

TRC-8004 is a superset of ERC-8004. Fully compatible at the interface level, with practical extensions for the problems the base standard does not yet solve.

## Resources

- [Python SDK](https://github.com/M2M-TRC8004-Registry/trc8004-m2m-sdk) — `pip install trc8004-m2m`
- [ERC-8004 Specification](https://eips.ethereum.org/EIPS/eip-8004)
- [ERC-8004 Discussion (Ethereum Magicians)](https://ethereum-magicians.org/t/erc-8004-trustless-agents/25098)
- [ERC-8004 Reference Implementation](https://github.com/ChaosChain/trustless-agents-erc-ri)
- [TRON Developer Docs](https://developers.tron.network/)
- [TronScan Explorer](https://tronscan.org)

## License

MIT License — see [LICENSE](LICENSE) file.
