// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title IVoting — frozen interface for the Blockchain Secure Voting System
/// @notice Anu implements this exactly. Swati's auth service and Garv's frontend
///         are built against these signatures ONLY. Do not change a signature here
///         without a team sync — every change forces rework on both other tracks.

interface IVoting {

    // ---------- STRUCTS (for reference — actual storage lives in the implementation) ----------
    // struct Voter {
    //     bool isRegistered;
    //     bool hasVoted;
    //     uint256 votedCandidateId;
    // }
    // struct Candidate {
    //     uint256 id;
    //     string name;
    //     uint256 voteCount;
    // }

    // ---------- EVENTS ----------
    // Frontend listens to these for live UI updates instead of polling.
    event VoterRegistered(address indexed voter);
    event CandidateAdded(uint256 indexed candidateId, string name);
    event VoteCast(address indexed voter, uint256 indexed candidateId);
    event VotingClosed(uint256 closedAt);

    // ---------- ADMIN FUNCTIONS (onlyOwner) ----------

    /// @notice Registers a wallet address as an eligible voter.
    /// @dev Called by the admin/backend AFTER Swati's auth service verifies the voter
    ///      off-chain (OTP + roll number check). This is the on-chain trust boundary:
    ///      whoever can call this decides who can vote. Decide NOW whether this is
    ///      called by an admin wallet manually, or automatically by a backend service
    ///      holding the owner key after OTP success. That decision changes Swati's
    ///      architecture — get it settled in week 1, not week 4.
    function registerVoter(address _voter) external;

    /// @notice Adds a candidate to the ballot. Must be called before voting opens.
    function addCandidate(string calldata _name) external;

    /// @notice Sets the voting window. Enforced via block.timestamp in vote().
    function setVotingPeriod(uint256 _startTime, uint256 _endTime) external;

    /// @notice Manually closes voting early if needed (in addition to deadline).
    function closeVoting() external;

    // ---------- VOTER FUNCTIONS ----------

    /// @notice Casts a vote for a candidate. Reverts if: not registered, already voted,
    ///         voting not open (before start / after end / manually closed).
    function vote(uint256 _candidateId) external;

    // ---------- READ FUNCTIONS (view — free to call, safe for frontend polling) ----------

    function getCandidate(uint256 _candidateId)
        external
        view
        returns (string memory name, uint256 voteCount);

    function getCandidateCount() external view returns (uint256);

    function getResults()
        external
        view
        returns (string[] memory names, uint256[] memory voteCounts);

    function isRegistered(address _voter) external view returns (bool);

    function hasVoted(address _voter) external view returns (bool);

    function isVotingOpen() external view returns (bool);

    function votingWindow() external view returns (uint256 startTime, uint256 endTime);
}

/*
DECISIONS THIS INTERFACE FORCES YOU TO MAKE BEFORE WEEK 2 ENDS:

1. Who holds the owner key that calls registerVoter?
   - Option A: A single admin wallet, admin manually approves each voter after
     checking OTP verification status in a dashboard. Simple, but doesn't scale
     past your 30-person mock election and is a manual bottleneck.
   - Option B: Swati's backend service holds the owner key and calls registerVoter
     automatically the moment OTP verification succeeds. Faster, but now your
     private key lives in a backend service — say this out loud in your security
     review, it's a real attack surface, not a minor implementation detail.
   Pick one now. This is Swati + You + Anu, not a solo call.

2. Candidate IDs: sequential uint256 starting at 0 or 1? Pick one, document it,
   because an off-by-one between Anu's contract and Garv's frontend is the single
   dumbest bug that will cost you a debugging session if left ambiguous.

3. getResults() returns two parallel arrays. Garv needs to know this now so the
   frontend isn't written expecting an array of structs (which is fine in Solidity
   memory but a different ABI shape — decide before he starts wiring it up).
*/
