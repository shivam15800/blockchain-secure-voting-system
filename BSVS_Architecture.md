# Blockchain-Based Secure Voting System (BSVS)
## System Architecture & Threat Model — Draft v0.1
**Status:** Sample baseline — pending stakeholder interview updates
**Owner:** Sira (Team Lead)
**Last updated:** Week 1

---

> ⚠️ **Draft Notice:** This document contains placeholder decisions for three unresolved issues:
> (1) Admin key ownership, (2) ballot privacy model, (3) candidate ID schema.
> These must be resolved via team consensus before the interface freeze at end of Week 2.

---

## 1. Architecture Overview

BSVS is a four-layer system: a React frontend communicates through MetaMask/Web3.js with Solidity smart contracts deployed on an EVM-compatible network. A separate voter authentication module (off-chain) gates access to the on-chain ballot contract. CI/CD runs via GitHub Actions; local development uses Ganache with deterministic accounts.

The central design principle is **enforce all voting rules on-chain, not in the frontend.** The UI is a convenience layer. The contract is the authority.

---

## 2. System Layers

### Layer 0 — Users & Roles

| Actor | Description | Access Level |
|---|---|---|
| **Voter** | Registered eligible voter | Can call `castVote()` once per election |
| **Admin** | Election organizer | Can call `registerVoter()`, `createElection()`, `closeElection()` |
| **Auditor** | Read-only observer | Can call `getResults()`, `getVoterStatus()` |
| **Contract Deployer** | Runs `hardhat deploy` | One-time setup; owns the contract admin key |

**Unresolved:** Is the Admin role the same account as the Contract Deployer? This directly determines whether admin actions are possible without the deployment private key. **Needs team decision.**

---

### Layer 1 — Frontend (Garv)

**Components:**

| Component | Tech | Responsibility |
|---|---|---|
| `VotingUI` | React | Renders election, candidates, vote confirmation |
| `WalletConnector` | MetaMask / window.ethereum | Connects voter wallet, retrieves address |
| `Web3Client` | Web3.js / ethers.js | Sends transactions, calls view functions |
| `EventSubscriber` | Web3.js event listener | Listens for `VoteCast`, `ElectionClosed` events |
| `AuthGateway` | Axios / Fetch | Calls Auth Module API to validate voter before showing ballot |

**Key interface contracts (frontend → smart contract):**
- `contract.methods.castVote(candidateId).send({ from: voterAddress })`
- `contract.methods.getResults().call()`
- `contract.methods.isRegistered(address).call()`

**Key assumptions (need validation):**
- Voter has MetaMask installed and an Ethereum account
- Frontend runs in browser (no mobile-native build)
- A voter who rejects the MetaMask transaction cannot vote (by design)

---

### Layer 2 — Authentication Module (Swati)

This layer is the only one that crosses the on-chain/off-chain boundary at registration time. It is responsible for verifying that a voter is eligible *before* their address is submitted to the smart contract for registration.

**Components:**

| Component | Responsibility |
|---|---|
| `IdentityVerifier` | Validates voter credentials against an eligibility list (CSV/DB) |
| `CredentialStore` | Holds registered voter → wallet address mappings |
| `SessionManager` | Issues a short-lived auth token after verification |
| `RegistrationBridge` | Calls admin wallet to invoke `registerVoter(address)` on-chain |

**Data flow (registration):**
```
Voter → submits credentials → IdentityVerifier
IdentityVerifier → checks eligibility list → CredentialStore
CredentialStore → voter is eligible → SessionManager issues token
Admin wallet → calls registerVoter(voterAddress) on Ballot contract
```

**Critical gap:** The smart contract has no way to verify that the address registered belongs to the verified voter. Swati's module enforces this off-chain. If Swati's module is compromised or bypassed, any address can be registered. This is a known architectural limitation — must be formally documented in scope.

**API surface (Auth Module → Frontend):**
- `POST /auth/verify` → `{ token, walletAddress, eligible: bool }`
- `GET /auth/status/:address` → `{ registered: bool }`

---

### Layer 3 — Smart Contracts (Anu)

This is the trust anchor of the entire system. All voting rules must be enforced here.

**Contract structure:**

```
IVoting.sol          ← Frozen interface (Week 2 hard deadline)
├── VoterRegistry.sol    ← Manages voter registration
├── Ballot.sol           ← Manages vote casting and storage
└── ElectionManager.sol  ← Manages election lifecycle
```

#### `IVoting.sol` — Interface (already partially defined)

```solidity
interface IVoting {
    // Election management
    function createElection(string calldata name, uint256 startTime, uint256 endTime) external;
    function closeElection() external;

    // Voter management
    function registerVoter(address voter) external;   // ← Admin key owner TBD

    // Voting
    function castVote(uint256 candidateId) external;  // ← candidateId convention TBD

    // Results
    function getResults() external view returns (uint256[] memory);  // ← array shape TBD
    function getVoterStatus(address voter) external view returns (bool registered, bool voted);

    // Events
    event VoterRegistered(address indexed voter);
    event VoteCast(address indexed voter, uint256 indexed candidateId);  // ← PRIVACY RISK
    event ElectionClosed(uint256[] results);
}
```

#### `VoterRegistry.sol`

```solidity
mapping(address => bool) private _registered;
mapping(address => bool) private _hasVoted;
address private _admin;

modifier onlyAdmin() { require(msg.sender == _admin, "Not admin"); _; }
modifier onlyRegistered() { require(_registered[msg.sender], "Not registered"); _; }
modifier hasNotVoted() { require(!_hasVoted[msg.sender], "Already voted"); _; }
```

#### `Ballot.sol`

```solidity
mapping(uint256 => uint256) private _voteCounts;  // candidateId → count
uint256 private _candidateCount;
bool private _electionOpen;

function castVote(uint256 candidateId) external onlyRegistered hasNotVoted {
    require(_electionOpen, "Election not open");
    require(candidateId < _candidateCount, "Invalid candidate");
    _voteCounts[candidateId]++;
    _hasVoted[msg.sender] = true;
    emit VoteCast(msg.sender, candidateId);   // ← PRIVACY: links address to candidateId on-chain
}
```

#### `ElectionManager.sol`

```solidity
struct Election {
    string name;
    uint256 startTime;
    uint256 endTime;
    bool isOpen;
    string[] candidates;   // ← candidate schema TBD: string names or uint IDs?
}
```

**Unresolved contract decisions:**
1. **Admin key:** Is `_admin` set at deploy time (deployer = admin), or passed as constructor arg?
2. **Candidate IDs:** 0-indexed uint? 1-indexed? Does the frontend control naming?
3. **Results array:** Does `getResults()` return `[count0, count1, ...]` or `[(id, count), ...]`?
4. **Privacy:** `VoteCast(msg.sender, candidateId)` exposes voter-ballot linkage on a public ledger. Mitigation options: (a) remove candidateId from event (audit only confirms vote counted, not how), (b) use commitment scheme, (c) explicitly scope ballot secrecy as out of scope with documentation.

---

### Layer 4 — Blockchain Infrastructure

| Environment | Purpose | Network |
|---|---|---|
| **Ganache (local)** | Development & unit testing | Private, deterministic accounts |
| **Sepolia testnet** | Integration testing & demo | Public testnet, faucet ETH |
| ~~Ropsten/Rinkeby~~ | ~~Deprecated~~ | Do not use |

**Ganache configuration (from repo):**
```json
{
  "deterministic": true,
  "mnemonic": "[repo mnemonic]",
  "accounts": 10,
  "gasLimit": 6721975
}
```

**Account roles (Ganache deterministic):**
- Account 0: Contract deployer / Admin
- Accounts 1–7: Test voters
- Account 8: Test auditor
- Account 9: Reserve

**Important:** Ganache and Sepolia differ in block time (~0ms vs ~12s), gas behavior, and account management. Test timing-sensitive logic (election start/end windows) on Sepolia before demo day.

---

### Layer 5 — DevOps / CI/CD

```
GitHub (main, dev, feature/*, hotfix/*)
├── GitHub Actions (CI)
│   ├── hardhat test         (on every push/PR)
│   ├── hardhat compile      (validate Solidity)
│   └── coverage report      (Istanbul/solidity-coverage)
├── Hardhat / Truffle
│   ├── compile              (Solidity → ABI + bytecode)
│   ├── test                 (Mocha + Chai)
│   └── deploy               (scripts/deploy.js → Ganache/Sepolia)
└── Branch protection rule: No merge of interface changes without full team notification
```

---

## 3. Data Flows

### Flow 1 — Voter Registration

```
1. Voter visits app → clicks "Register"
2. Voter submits identity credentials (name, ID number) to Auth Module API
3. IdentityVerifier checks credentials against eligibility list
4. If eligible: Voter submits wallet address → stored in CredentialStore
5. Admin (or automated bridge) calls registerVoter(voterAddress) on-chain
6. VoterRegistry.sol sets _registered[voterAddress] = true
7. Event VoterRegistered(voterAddress) emitted
8. Voter receives confirmation; session token issued
```

### Flow 2 — Vote Casting

```
1. Voter opens app → WalletConnector detects MetaMask → requests account
2. AuthGateway checks isRegistered(address) via contract call
3. If registered: Frontend renders ballot (candidate list)
4. Voter selects candidate → clicks "Cast Vote"
5. Web3Client calls castVote(candidateId) → MetaMask popup
6. Voter confirms transaction → tx signed and broadcast
7. Ballot.sol: runs onlyRegistered + hasNotVoted checks
8. _voteCounts[candidateId]++ and _hasVoted[msg.sender] = true
9. Event VoteCast emitted → EventSubscriber picks it up → UI shows confirmation
10. If voter has already voted: require() reverts tx, MetaMask shows error
```

### Flow 3 — Result Tallying

```
1. Admin calls closeElection() → _electionOpen = false
2. Event ElectionClosed([counts]) emitted
3. Any user calls getResults() → returns _voteCounts array
4. Frontend renders results table/chart
5. Auditor can independently verify by reading events from block explorer
```

---
