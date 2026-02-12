# M2M TRC-8004 Agent Registry - Smart Contracts

Solidity smart contracts for the M2M TRC-8004 Machine-to-Machine Agent Registry on TRON blockchain.

This repository contains the source code and ABIs for the deployed contracts. It is intended as a **reference** for developers integrating with the M2M registry via the API or SDK.

## TRC-8004 Roadmap (2026-02-12)

TRC-8004 is becoming a full superset of ERC-8004 — compatible at every interface, with extensions where the base standard falls short. See the **[TRC-8004 Roadmap](TRC-8004-Roadmap.md)** for the full specification and planned changes.

---

## Deployed Contracts

### Mainnet

| Contract | Address |
|----------|---------|
| EnhancedIdentityRegistry | [`TYmmnmgkxteBvH8u8LAfb8sCcs1Eph2tk2`](https://tronscan.org/#/contract/TYmmnmgkxteBvH8u8LAfb8sCcs1Eph2tk2) |
| ValidationRegistry | [`TY9sqKiWBhZP6aMdjarcViyD2cudMAGfGn`](https://tronscan.org/#/contract/TY9sqKiWBhZP6aMdjarcViyD2cudMAGfGn) |
| ReputationRegistry | [`TU8PmqF3mZoEGE97Se5oSgNo6bUs4VrswB`](https://tronscan.org/#/contract/TU8PmqF3mZoEGE97Se5oSgNo6bUs4VrswB) |
| M2M TRC20 Token | [`TSH8XLQRMrCTTdCr3rUH2zUiuDZQjfmHaX`](https://tronscan.org/#/contract/TSH8XLQRMrCTTdCr3rUH2zUiuDZQjfmHaX) |

### Shasta Testnet

| Contract | Address |
|----------|---------|
| EnhancedIdentityRegistry | [`TUf5fAgpLrR6YM3P9oX9GNG1tGV3VcyPE3`](https://shasta.tronscan.org/#/contract/TUf5fAgpLrR6YM3P9oX9GNG1tGV3VcyPE3) |
| ValidationRegistry | [`TJXVDV7hpsTSSz3QBCJdw99eFvTWUjxph6`](https://shasta.tronscan.org/#/contract/TJXVDV7hpsTSSz3QBCJdw99eFvTWUjxph6) |
| ReputationRegistry | [`TN5FBfXASyxrjUa9V73Hfme2pY9yWh6Rsh`](https://shasta.tronscan.org/#/contract/TN5FBfXASyxrjUa9V73Hfme2pY9yWh6Rsh) |

---

## Contracts

### 1. EnhancedIdentityRegistry.sol

**ERC-721 NFT** for agent ownership and identity.

**Features**:
- Each agent is an NFT (token ID = agent ID)
- Stores tokenURI (IPFS/HTTP) pointing to off-chain metadata
- Metadata hash stored on-chain for integrity verification
- Optional on-chain key-value metadata storage
- Agent wallet delegation for operational separation
- Full ERC-721 compliance (transfer, approve, safeTransfer with receiver check)
- ERC-165 interface detection

**Key Functions**:
| Function | Access | Description |
|----------|--------|-------------|
| `register(uri, metadataHash)` | Anyone | Mint a new agent NFT. Returns `agentId`. |
| `registerWithOnChainMetadata(uri, metadataHash, keys[], values[])` | Anyone | Register with additional on-chain KV metadata. |
| `setAgentWallet(agentId, wallet)` | Owner / Approved | Delegate an operational wallet for the agent. |
| `getMetadataValue(agentId, key)` | View | Read on-chain metadata by key. |
| `ownerOf(agentId)` | View | Get agent owner address. |
| `tokenURI(agentId)` | View | Get metadata URI. |
| `agentWalletOf(agentId)` | View | Get delegated wallet address. |
| `metadataHashOf(agentId)` | View | Get stored metadata hash. |
| `exists(tokenId)` | View | Check if an agent exists. |
| `totalAgents()` | View | Get total registered agent count. |
| `balanceOf(owner)` | View | Get number of agents owned by address. |

Standard ERC-721: `transferFrom`, `safeTransferFrom`, `approve`, `getApproved`, `setApprovalForAll`, `isApprovedForAll`

**Events**: `AgentRegistered`, `AgentWalletUpdated`, `Transfer`, `Approval`, `ApprovalForAll`

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
- Query requests by agent, validator, or requester

**Key Functions**:
| Function | Access | Description |
|----------|--------|-------------|
| `validationRequest(agentId, validator, requestURI, requestDataHash)` | Anyone | Create a validation request. Returns `requestId`. |
| `completeValidation(requestId, resultURI, resultHash)` | Validator only | Mark request as completed with result. |
| `rejectValidation(requestId, resultURI, reasonHash)` | Validator only | Reject request with reason. |
| `cancelRequest(requestId)` | Requester only | Cancel a pending request. |
| `getRequest(requestId)` | View | Get full request details. |
| `getSummaryForAgent(agentId)` | View | Returns `(total, pending, completed, rejected, cancelled)` counts. |
| `getAgentRequests(agentId)` | View | Get all request IDs for an agent. |
| `getRequesterRequests(address)` | View | Get all request IDs by requester. |
| `getValidatorRequests(address)` | View | Get all request IDs by validator. |

**Events**: `ValidationRequested`, `ValidationCompleted`, `ValidationRejected`, `ValidationCancelled`

---

### 3. ReputationRegistry.sol

**Feedback and reputation** system.

**Features**:
- Any address can submit feedback with text and sentiment (Positive / Neutral / Negative)
- Clients can revoke their own feedback
- Agent owners (or delegated wallets) can respond to feedback in a thread
- Summary statistics: total, active, revoked, positive, neutral, negative counts

**Sentiment Enum**: `Neutral = 0`, `Positive = 1`, `Negative = 2`

**Key Functions**:
| Function | Access | Description |
|----------|--------|-------------|
| `giveFeedback(agentId, feedbackText, sentiment)` | Anyone | Submit feedback. Returns `feedbackIndex`. |
| `revokeFeedback(agentId, feedbackIndex)` | Feedback author | Revoke previously submitted feedback. |
| `appendResponse(agentId, feedbackIndex, responseText)` | Agent owner / wallet | Respond to feedback (thread-based). |
| `getFeedbackCount(agentId)` | View | Get total feedback count for agent. |
| `getFeedback(agentId, feedbackIndex)` | View | Returns `(client, feedbackText, sentiment, timestamp, revoked, responseCount)`. |
| `getFeedbackResponses(agentId, feedbackIndex)` | View | Returns `(responses[], responseTimestamps[])`. |
| `getSummary(agentId)` | View | Returns `(total, active, revoked, positive, neutral, negative)` counts. |

**Events**: `FeedbackGiven`, `FeedbackRevoked`, `ResponseAppended`

---

## ABIs

Minimal ABI files (interface-only, no bytecode) are provided in the `abi/` directory for integration:

- `abi/EnhancedIdentityRegistry.json`
- `abi/ValidationRegistry.json`
- `abi/ReputationRegistry.json`

## Technical Details

- **Solidity**: 0.8.20
- **EVM version**: Paris
- **Compiler optimization**: Enabled, 200 runs
- **Toolchain**: TronBox
- **Token standard**: ERC-721 (EnhancedIdentityRegistry)

## Project Structure

```
smart-contracts/
├── abi/
│   ├── EnhancedIdentityRegistry.json    # Minimal ABI (interface only)
│   ├── ValidationRegistry.json          # Minimal ABI (interface only)
│   └── ReputationRegistry.json          # Minimal ABI (interface only)
├── contracts/
│   ├── EnhancedIdentityRegistry.sol     # Agent NFTs (ERC-721)
│   ├── ValidationRegistry.sol           # Validation workflow
│   └── ReputationRegistry.sol           # Feedback & reputation
├── migrations/
│   └── 2_deploy_contracts.js            # Deployment script
├── .env.example                         # Environment template
├── .gitignore
├── LICENSE
├── package.json
├── README.md
└── tronbox.js.example                   # TronBox config template
```

## Security

- No reentrancy vulnerabilities
- Access control on all state-changing functions
- Input validation on all parameters
- Safe math (Solidity 0.8+ built-in overflow checks)
- Event emission for all state changes
- Safe ERC-721 transfers with receiver check
- Agent existence validated across all registries

## Resources

- [TRON Developer Docs](https://developers.tron.network/)
- [TronBox Documentation](https://developers.tron.network/docs/tronbox)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [TronScan Explorer](https://tronscan.org)
- [Shasta Testnet Explorer](https://shasta.tronscan.org)

## License

MIT License — see [LICENSE](LICENSE) file.
