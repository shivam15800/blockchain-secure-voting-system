
## 4. Threat Model (STRIDE)

### Scope

In scope: Smart contract, auth module API, frontend, Ganache/Sepolia deployment.
Out of scope: Physical security of admin machine, nation-state attacks on Ethereum itself.

### 4.1 Spoofing

| Threat | Description | Impact | Mitigation |
|---|---|---|---|
| **S1 — Voter identity spoofing** | Attacker submits false credentials to Auth Module to get registered | Illegitimate voter gains ballot access | IdentityVerifier must validate against authoritative list; credential format must be hard to guess/forge |
| **S2 — Admin impersonation** | Attacker calls registerVoter() pretending to be admin | Unauthorized voter registrations | `onlyAdmin` modifier enforces msg.sender == _admin; admin private key must be secured |
| **S3 — Wallet impersonation** | Attacker uses a stolen private key to vote on victim's behalf | Victim's vote stolen; attacker votes | Ethereum's ECDSA signature ensures only the private key owner can sign transactions; no additional mitigation possible at contract level |
| **S4 — Auth token spoofing** | Attacker forges or replays a Swati-issued session token | Bypass identity verification | Auth module must use signed JWTs with expiry; token must not be reusable |

### 4.2 Tampering

| Threat | Description | Impact | Mitigation |
|---|---|---|---|
| **T1 — Vote count manipulation** | Attacker modifies _voteCounts in storage | Election result altered | Impossible post-deployment on Ethereum (immutable storage); only contract code can write to it |
| **T2 — Frontend vote manipulation** | Attacker modifies frontend JS to call castVote with different candidateId than selected | Voter's intent overridden | Contract enforces candidateId range validity; voter should verify tx in MetaMask before signing |
| **T3 — Eligibility list tampering** | Attacker modifies the off-chain voter eligibility CSV/DB | Unauthorized voters registered or legitimate voters blocked | Eligibility list must be checksummed and version-controlled; access restricted to admin only |
| **T4 — Contract upgrade tampering** | If upgradeable proxies used: attacker points proxy to malicious implementation | Complete compromise | For capstone: use immutable fixed-deploy contracts. No upgradeability = no this attack vector |
| **T5 — Replay attack** | Attacker rebroadcasts a signed castVote transaction | Double-voting | Ethereum nonces prevent transaction replay; hasNotVoted mapping provides application-level guard |

### 4.3 Repudiation

| Threat | Description | Impact | Mitigation |
|---|---|---|---|
| **R1 — Admin denies registering a voter** | Admin claims they did not call registerVoter(address) | Dispute over voter eligibility | All registerVoter() calls emit VoterRegistered event; logged immutably on-chain with tx hash and block number |
| **R2 — Voter denies casting a vote** | Voter claims they did not vote | Dispute over results | VoteCast event with voter address is on-chain (note: this is also a privacy risk — see I2) |
| **R3 — Admin denies closing election** | Admin claims election was not officially closed | Results dispute | ElectionClosed event with timestamp and result snapshot is emitted on-chain |

### 4.4 Information Disclosure

| Threat | Description | Impact | Mitigation |
|---|---|---|---|
| **I1 — Private key exposure** | Admin/deployer private key leaked from .env file committed to git | Complete system compromise | .env must be in .gitignore from day 1; never commit keys; use environment secrets in GitHub Actions |
| **I2 — Ballot linkage (HIGH)** | VoteCast(msg.sender, candidateId) event allows anyone to see how Alice voted | Violates ballot secrecy | **Option A:** Remove candidateId from VoteCast event (emit only address, no candidate). **Option B:** Use commit-reveal scheme. **Option C:** Document ballot secrecy is out of scope. Must be a team decision before Week 2. |
| **I3 — Voter enumeration** | Anyone can call isRegistered(address) to enumerate registered voters | Privacy breach | Low risk for capstone; note as known limitation |
| **I4 — Auth token interception** | Session token transmitted in plaintext | Token reuse by attacker | Auth module API must run over HTTPS; never transmit tokens in URLs |
| **I5 — Mnemonic in ganache config** | Deterministic mnemonic committed to repo | Anyone can derive all test accounts | Acceptable for local Ganache testing; must never use real mnemonics; clearly comment "TEST ONLY" |

### 4.5 Denial of Service

| Threat | Description | Impact | Mitigation |
|---|---|---|---|
| **D1 — Gas griefing** | Attacker spams the network with transactions during election window | Legitimate voters can't get transactions mined | On private Ganache: not applicable. On Sepolia: low risk (public testnet). Document as known risk for production |
| **D2 — Admin key lost** | Admin private key is lost or forgotten | Cannot register voters or close election | Admin key must be backed up securely; ideally multi-sig in production (out of scope for capstone, document it) |
| **D3 — Auth module downtime** | Swati's auth API goes down during election | Voters cannot register | Auth module should have retry logic; note single point of failure |
| **D4 — Block gas limit** | getResults() iterates over a large candidate/voter array and hits gas limit | Results cannot be retrieved | Keep candidate count small (under 100 for capstone); document this limit |
| **D5 — Ganache restart** | Local Ganache restarted without persistent state | All test state lost | Use `--db` flag to persist Ganache state to disk; document in README |

### 4.6 Elevation of Privilege

| Threat | Description | Impact | Mitigation |
|---|---|---|---|
| **E1 — Voter calls admin function** | Voter address calls registerVoter() or closeElection() | Unauthorized election manipulation | `onlyAdmin` modifier on all admin functions; enforced at EVM level |
| **E2 — Unregistered address votes** | Unregistered address calls castVote() | Invalid vote counted | `onlyRegistered` modifier checks _registered[msg.sender] before executing |
| **E3 — Double vote** | Registered voter calls castVote() twice | Vote counted twice | `hasNotVoted` modifier checks _hasVoted[msg.sender]; reverts on second call |
| **E4 — Vote outside election window** | castVote() called before election opens or after it closes | Invalid timing of votes | `require(_electionOpen)` check; additionally check block.timestamp against startTime/endTime |
| **E5 — Reentrancy** | Malicious contract calls back into castVote() during execution | Double-vote via reentrancy | castVote() must follow Checks-Effects-Interactions pattern; set _hasVoted = true BEFORE any external calls or event emissions |
| **E6 — Constructor privilege escalation** | Wrong address passed as admin in constructor | Wrong entity has admin control | Validate msg.sender == expected admin address in constructor; log it |

---

## 5. Security Controls Summary

| Control | Implemented By | Covers |
|---|---|---|
| `onlyAdmin` modifier | Anu (contract) | E1, S2 |
| `onlyRegistered` modifier | Anu (contract) | E2 |
| `hasNotVoted` modifier | Anu (contract) | E3, T5 |
| Election window check (`_electionOpen`) | Anu (contract) | E4 |
| Checks-Effects-Interactions pattern | Anu (contract) | E5 |
| JWT with expiry | Swati (auth module) | S4, I4 |
| Eligibility list integrity check | Swati (auth module) | T3 |
| HTTPS for auth API | Swati / deployment | I4 |
| `.env` in `.gitignore` | Sira (repo setup) | I1 |
| Deterministic test accounts only | Sira (repo setup) | I5 |
| GitHub branch protection | Sira (repo setup) | T3, T4 |
| Immutable fixed-deploy contracts | Team decision | T4 |
| Ballot privacy (event structure) | **UNRESOLVED — team decision** | I2 |
| Admin key backup strategy | **UNRESOLVED — team decision** | D2 |

---

## 6. Known Limitations (Capstone Scope)

These are explicit out-of-scope items that must be documented in your final report — not hidden.

1. **No real identity verification.** Voter credential checking uses a simulated eligibility list, not a government ID system. A production system would require integration with a verified identity provider.

2. **Ballot secrecy not guaranteed.** On a public Ethereum ledger, all transactions are visible. True ballot secrecy requires cryptographic techniques (zk-SNARKs, commit-reveal schemes) that are beyond this project's scope. This must be stated clearly in the system design section.

3. **Single admin key.** Production voting systems use multi-signature admin controls and time-locks. This system has a single admin private key, which is a single point of failure.

4. **No mobile support.** The frontend assumes a desktop browser with MetaMask extension. Mobile MetaMask (app) integration is not in scope.

5. **Gas costs are simulated.** Ganache tests do not reflect real-world Sepolia gas prices, which can vary significantly.

6. **No voter anonymization.** Voter wallet addresses are linked to registration records in Swati's module. A sophisticated attacker with access to both the off-chain database and on-chain events can potentially de-anonymize voters.

---

## 7. Open Decisions (Requires Team Resolution Before Week 2)

| # | Decision | Options | Owner | Deadline |
|---|---|---|---|---|
| 1 | Who holds the admin key? | (a) Deployer = admin, (b) Separate admin address passed at deploy | Team | Week 2, Day 1 |
| 2 | Candidate ID convention | (a) 0-indexed uint, (b) 1-indexed uint, (c) string names | Team | Week 2, Day 1 |
| 3 | getResults() return shape | (a) `uint256[]` counts only, (b) `(string, uint256)[]` tuples | Team | Week 2, Day 1 |
| 4 | Ballot privacy model | (a) Remove candidateId from VoteCast event, (b) Commit-reveal, (c) Explicit out-of-scope | Team | Week 2, Day 1 |

---

## 8. Dependency Map (Who Blocks Whom)

```
IVoting.sol interface (Sira/Anu, due end Week 2)
    ↓ blocks
    Anu: VoterRegistry.sol, Ballot.sol, ElectionManager.sol
    Swati: RegistrationBridge (needs registerVoter signature)
    Garv: Web3Client calls (needs ABI)

Swati's auth API contract (due Week 3)
    ↓ blocks
    Garv: AuthGateway component

Ganache deterministic accounts (Sira, already done)
    ↓ enables
    Anu: Local unit testing
    Swati: Auth module integration testing
```

**Any change to `IVoting.sol` after Week 2 requires explicit notification to all three team members and a team review meeting.**

---

*Document version: 0.1 — baseline draft. Update after stakeholder interviews.*
*Next review: End of Week 2, before interface freeze.*
