# 🏛️ BitDAO Governance Protocol (Built on Stacks)

> **A modular, secure, and quadratic-weighted governance framework leveraging Bitcoin finality via Stacks.**

---

## 📜 Overview

**BitDAO Governance Protocol** is a fully on-chain, decentralized autonomous organization (DAO) framework built in Clarity on the [Stacks blockchain](https://www.stacks.co), inheriting the security guarantees of Bitcoin. This protocol provides a robust, tamper-resistant infrastructure for managing DAO governance, treasury operations, proposal lifecycles, and advanced vote delegation.

BitDAO is optimized for:

* **Community-driven protocol governance**
* **Ecosystem fund management**
* **DeFi protocol parameter tuning**
* **Trust-minimized vote execution with quadratic weighting**

---

## 🧱 System Overview

| Component                        | Description                                                                                  |
| -------------------------------- | -------------------------------------------------------------------------------------------- |
| **Quadratic Voting Engine**      | Weights votes using the square root of token balance to prevent plutocratic control.         |
| **Proposal Lifecycle Manager**   | Supports creation, voting, execution, and time-locked scheduling for sensitive actions.      |
| **Treasury Allocation System**   | Fully autonomous treasury controlled by token holders via governance proposals.              |
| **Advanced Delegation Logic**    | Users may delegate votes with controlled maximum depth, enhancing representative governance. |
| **Emergency & Admin Controls**   | Owner-controlled pause mechanism and governance parameter configuration.                     |
| **SBT Model (Semi-Bound Token)** | Provides voting power without compromising liquidity for genuine participants.               |

---

## 🧩 Contract Architecture

The system is composed of a **monolithic Clarity contract** that encapsulates several interlocking modules:

### 🔐 Access Control & Emergency Pause

* `CONTRACT-OWNER` constant for admin privileges
* Emergency pause toggle for halting vote casting and proposal interactions

### 📑 Proposal Management

Handles the entire lifecycle of a proposal:

* Creation (`create-proposal`)
* Voting (`cast-quadratic-vote`)
* Execution (`execute-proposal`)
* Time-locked execution (`schedule-time-locked-execution`, `execute-time-locked-proposal`)

Supports multiple proposal types:

* `governance`
* `treasury`
* `parameter-update`
* `ecosystem`

### 🗳️ Voting Mechanism

* Quadratic vote weighting (`sqrti`)
* Proposal-specific vote records
* Automatic quorum and approval threshold enforcement

### 🧭 Delegation System

* Delegation with `max-delegation-depth`
* Revocation support
* No infinite delegation loops due to strict depth enforcement

### 💰 Treasury Governance

* DAO-controlled treasury via `deposit-to-treasury`
* Allocation proposals (`create-treasury-proposal`)
* Controlled execution (`execute-treasury-allocation`) with pass/fail verification

### ⚙️ Administrative Functions

* Governance configuration updates (`update-governance-parameters`)
* Emergency pause (`toggle-contract-pause`)
* Upgrade hooks reserved for future use

### 🧾 Token Functions

* Governance token minting & burning (`mint-governance-token`, `burn-governance-tokens`)
* SBT model enforces long-term participation without locking liquidity

---

## 🧬 Data Flow (Simplified)

```plaintext
┌────────────┐
│ Token Mint │◄────────────────────────── Owner or Reward System
└─────┬──────┘
      │
      ▼
┌─────────────┐         Delegate        ┌────────────────┐
│ User Wallet │───────────────────────►│ Delegation Map │
└────┬────────┘                         └─────┬──────────┘
     │Vote                              Vote │Check Depth
     ▼                                   ▼
┌────────────────────┐      Record     ┌──────────────┐
│ cast-quadratic-vote│───────────────►│ Votes Map    │
└─────┬──────────────┘                └────┬──────────┘
      │                                   │
      ▼                                   ▼
┌─────────────┐        Execute        ┌──────────────┐
│ Proposals   │<─────────────────────►│ execute-*    │
└────┬────────┘                       └──────────────┘
     │
     ▼
┌──────────────────────┐
│ Treasury Allocations │─────► Treasury Transfers (on approval)
└──────────────────────┘
```

---

## 📌 Key Constants & Parameters

| Variable                         | Description                          | Default            |
| -------------------------------- | ------------------------------------ | ------------------ |
| `min-proposal-duration`          | Minimum voting period                | `u144` (~1 day)    |
| `max-proposal-duration`          | Maximum voting period                | `u4320` (~30 days) |
| `proposal-submission-min-tokens` | Tokens required to propose           | `u100000`          |
| `treasury-max-per-proposal`      | Max treasury allocation per proposal | `u100000000`       |
| `contract-paused`                | Emergency pause state                | `false`            |

---

## ✅ Feature Summary

| Feature                             | Description                                     |
| ----------------------------------- | ----------------------------------------------- |
| ✅ On-chain quadratic voting         | Vote power grows sublinearly with stake         |
| ✅ Delegation with depth limits      | Prevents centralization via infinite delegation |
| ✅ Treasury with per-proposal limits | Prevents abuse via treasury caps                |
| ✅ Time-locked execution             | Ensures deliberation before critical execution  |
| ✅ Emergency pause                   | Stops voting and execution during crises        |
| ✅ Owner configuration               | Limited to setting thresholds and pauses        |

---

## 🔒 Security Considerations

* **Reentrancy-Proof:** No mutable state changes after external calls.
* **Immutable Records:** Voting and proposals are append-only.
* **Anti-Governance Attack Controls:**

  * Emergency pause switch
  * Depth-limited delegation
  * Quorum + pass threshold enforcement
* **Upgrade-safe:** Reserved upgrade functions for future modularization

---

## 🔍 Read-only Interfaces

| Function                          | Purpose                             |
| --------------------------------- | ----------------------------------- |
| `get-proposal-details`            | Fetch proposal metadata             |
| `get-voting-power`                | Query a user’s current voting power |
| `get-governance-metrics`          | Basic DAO state overview            |
| `get-enhanced-governance-metrics` | Includes treasury and config data   |

---

## ⏳ Future Roadmap

* ✅ Signature-based off-chain voting (`verify-vote-signature`) stubbed
* 🔜 Enhanced delegation analytics (multi-hop resolution)
* 🔜 Proposal batching
* 🔜 Modular upgrade via SIP-010 standards

---

## 🧪 Testing & Simulation

Run tests using the [Clarinet framework](https://docs.hiro.so/clarinet/get-started/install) or deploy locally with a mocked governance token and interact via:

```bash
clarinet console
```

---

## 🏁 Deployment Notes

* The contract assumes a single deployment for both token logic and governance.
* Ownership (`CONTRACT-OWNER`) is set to the deployer by default. You may wish to transfer ownership to a multisig or another DAO module.

---

## 🤝 License

This smart contract is provided under the [MIT License](LICENSE), with no warranty. Use in production at your own risk.

---

## 🧠 Contributing

We welcome issues, PRs, and discussions. To contribute:

1. Fork and clone this repository
2. Write your feature or test
3. Submit a pull request with context and test coverage
