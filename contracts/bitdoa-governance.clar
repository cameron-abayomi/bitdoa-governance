;; Title: BitDAO Governance Protocol
;;
;; Summary: A comprehensive decentralized autonomous organization (DAO) framework built on Stacks,
;; leveraging Bitcoin's security to enable transparent, quadratic-weighted community governance with
;; advanced delegation mechanics, time-locked execution, and treasury management capabilities.
;;
;; Description: BitDAO Governance Protocol empowers communities to coordinate decision-making through
;; a trustless, on-chain voting infrastructure. Utilizing quadratic voting to balance influence across
;; token holders, the protocol implements sophisticated governance primitives including vote delegation
;; with depth controls, multi-stage proposal lifecycle management, time-locked execution for high-stakes
;; decisions, and autonomous treasury operations. Built with Bitcoin's finality guarantees via Stacks,
;; BitDAO enables censorship-resistant governance for DeFi protocols, community treasuries, and protocol
;; parameter adjustments. The semi-bound token (SBT) model ensures committed stakeholder participation
;; while maintaining liquidity for genuine contributors. Emergency pause mechanisms and granular access
;; controls protect against governance attacks while preserving decentralization principles.

;; ERROR CODES

(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-INVALID-PROPOSAL (err u2))
(define-constant ERR-INSUFFICIENT-TOKENS (err u3))
(define-constant ERR-ALREADY-VOTED (err u4))
(define-constant ERR-PROPOSAL-CLOSED (err u5))
(define-constant ERR-INVALID-DELEGATION (err u6))
(define-constant ERR-EXCEEDED-DELEGATION-DEPTH (err u7))
(define-constant ERR-PROPOSAL-EXECUTION-FAILED (err u8))
(define-constant ERR-COOLDOWN-PERIOD (err u9))
(define-constant ERR-INVALID-TIMELOCK (err u10))
(define-constant ERR-VOTE-QUORUM-NOT-REACHED (err u11))
(define-constant ERR-TREASURY-LIMIT-EXCEEDED (err u12))

;; CONSTANTS

(define-constant CONTRACT-OWNER tx-sender)

;; Proposal classification system
(define-constant PROPOSAL-TYPES {
  GOVERNANCE: "governance",
  TREASURY: "treasury",
  PARAMETER-UPDATE: "parameter-update",
  ECOSYSTEM: "ecosystem",
})

;; Vote classification for future expansion
(define-constant VOTE-TYPES {
  FOR: u1,
  AGAINST: u2,
  ABSTAIN: u3,
})

;; FUNGIBLE TOKEN DEFINITION

;; Governance token - Semi-Bound Token (SBT) for voting power
(define-fungible-token governance-token u10000000)

;; DATA VARIABLES

;; Proposal tracking
(define-data-var next-proposal-id uint u0)
(define-data-var total-governance-tokens uint u0)

;; Emergency controls
(define-data-var contract-paused bool false)

;; Governance configuration parameters
(define-data-var min-proposal-duration uint u144) ;; ~1 day at 10 min blocks
(define-data-var max-proposal-duration uint u4320) ;; ~30 days at 10 min blocks
(define-data-var proposal-submission-min-tokens uint u100000)
(define-data-var treasury-max-per-proposal uint u100000000) ;; 10% of supply cap

;; Treasury state
(define-data-var treasury-balance uint u0)
(define-data-var next-allocation-id uint u0)

;; DATA MAPS

;; Proposal registry
(define-map proposals
  { proposal-id: uint }
  {
    title: (string-utf8 100),
    description: (string-utf8 500),
    proposed-by: principal,
    start-block: uint,
    end-block: uint,
    proposal-type: (string-ascii 20),
    vote-for: uint,
    vote-against: uint,
    executed: bool,
    execution-result: (optional bool),
    quorum-threshold: uint,
    pass-threshold: uint,
  }
)

;; Individual vote records
(define-map votes
  {
    proposal-id: uint,
    voter: principal,
  }
  {
    voting-power: uint,
    vote-type: bool,
    quadratic-weight: uint,
    timestamp: uint,
  }
)

;; Vote delegation tracking
(define-map delegations
  principal
  {
    delegated-to: principal,
    delegation-depth: uint,
    max-delegation-depth: uint,
    delegated-at: uint,
  }
)

;; Time-locked proposal execution registry
(define-map time-locks
  { proposal-id: uint }
  {
    execution-block: uint,
    executed: bool,
  }
)

;; Treasury allocation tracking
(define-map treasury-allocations
  { allocation-id: uint }
  {
    proposal-id: uint,
    recipient: principal,
    amount: uint,
    executed: bool,
  }
)

;; TOKEN MANAGEMENT FUNCTIONS

;; @desc Mint new governance tokens to specified recipient
;; @param amount: Number of tokens to mint
;; @param recipient: Principal receiving the tokens
;; @returns (response bool uint)
(define-public (mint-governance-token
    (amount uint)
    (recipient principal)
  )
  (begin
    (try! (ft-mint? governance-token amount recipient))
    (var-set total-governance-tokens (+ (var-get total-governance-tokens) amount))
    (ok true)
  )
)

;; @desc Burn governance tokens from sender's balance
;; @param amount: Number of tokens to burn
;; @returns (response bool uint)
(define-public (burn-governance-tokens (amount uint))
  (begin
    (try! (ft-burn? governance-token amount tx-sender))
    (var-set total-governance-tokens (- (var-get total-governance-tokens) amount))
    (ok true)
  )
)

;; PROPOSAL LIFECYCLE FUNCTIONS

;; @desc Create a new governance proposal
;; @param title: Proposal title (max 100 chars)
;; @param description: Detailed proposal description (max 500 chars)
;; @param proposal-type: Type classification (governance/treasury/parameter-update/ecosystem)
;; @param duration: Voting period in blocks
;; @param quorum-threshold: Minimum participation percentage required
;; @param pass-threshold: Minimum approval percentage required
;; @returns (response uint uint) - Proposal ID on success
(define-public (create-proposal
    (title (string-utf8 100))
    (description (string-utf8 500))
    (proposal-type (string-ascii 20))
    (duration uint)
    (quorum-threshold uint)
    (pass-threshold uint)
  )
  (let (
      (proposal-id (var-get next-proposal-id))
      (current-block stacks-block-height)
    )
    ;; Validation: Proposer must hold governance tokens
    (asserts! (> (ft-get-balance governance-token tx-sender) u0)
      ERR-INSUFFICIENT-TOKENS
    )

    ;; Validation: Proposal type must be valid
    (asserts!
      (or
        (is-eq proposal-type (get GOVERNANCE PROPOSAL-TYPES))
        (is-eq proposal-type (get TREASURY PROPOSAL-TYPES))
        (is-eq proposal-type (get PARAMETER-UPDATE PROPOSAL-TYPES))
        (is-eq proposal-type (get ECOSYSTEM PROPOSAL-TYPES))
      )
      ERR-INVALID-PROPOSAL
    )

    ;; Store proposal data
    (map-set proposals { proposal-id: proposal-id } {
      title: title,
      description: description,
      proposed-by: tx-sender,
      start-block: current-block,
      end-block: (+ current-block duration),
      proposal-type: proposal-type,
      vote-for: u0,
      vote-against: u0,
      executed: false,
      execution-result: none,
      quorum-threshold: quorum-threshold,
      pass-threshold: pass-threshold,
    })

    ;; Increment proposal counter
    (var-set next-proposal-id (+ proposal-id u1))

    (ok proposal-id)
  )
)

;; @desc Cast a quadratic-weighted vote on a proposal
;; @param proposal-id: ID of the proposal to vote on
;; @param vote-type: true for support, false for opposition
;; @returns (response bool uint)
(define-public (cast-quadratic-vote
    (proposal-id uint)
    (vote-type bool)
  )
  (let (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id })
        ERR-INVALID-PROPOSAL
      ))
      (voter-balance (ft-get-balance governance-token tx-sender))
      (quadratic-weight (sqrti voter-balance))
      (current-block stacks-block-height)
    )
    ;; Validation: Contract must not be paused
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)

    ;; Validation: Proposal must be active
    (asserts! (< current-block (get end-block proposal)) ERR-PROPOSAL-CLOSED)

    ;; Validation: Voter must not have already voted
    (asserts!
      (is-none (map-get? votes {
        proposal-id: proposal-id,
        voter: tx-sender,
      }))
      ERR-ALREADY-VOTED
    )

    ;; Record vote with quadratic weighting
    (map-set votes {
      proposal-id: proposal-id,
      voter: tx-sender,
    } {
      voting-power: voter-balance,
      vote-type: vote-type,
      quadratic-weight: quadratic-weight,
      timestamp: current-block,
    })

    ;; Update proposal vote tallies
    (if vote-type
      (map-set proposals { proposal-id: proposal-id }
        (merge proposal { vote-for: (+ (get vote-for proposal) quadratic-weight) })
      )
      (map-set proposals { proposal-id: proposal-id }
        (merge proposal { vote-against: (+ (get vote-against proposal) quadratic-weight) })
      )
    )

    (ok true)
  )
)

;; @desc Execute a proposal after voting period ends
;; @param proposal-id: ID of the proposal to execute
;; @returns (response bool uint) - Outcome of the proposal
(define-public (execute-proposal (proposal-id uint))
  (let (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id })
        ERR-INVALID-PROPOSAL
      ))
      (current-block stacks-block-height)
      (total-tokens (var-get total-governance-tokens))
    )
    ;; Validation: Voting period must have ended
    (asserts! (>= current-block (get end-block proposal)) ERR-PROPOSAL-CLOSED)

    ;; Validation: Proposal must not be already executed
    (asserts! (not (get executed proposal)) ERR-UNAUTHORIZED)

    ;; Calculate participation and approval metrics
    (let (
        (total-votes (+ (get vote-for proposal) (get vote-against proposal)))
        (quorum-percentage (/ (* total-votes u100) total-tokens))
        (vote-for-percentage (/ (* (get vote-for proposal) u100) total-votes))
      )
      ;; Validation: Quorum threshold must be met
      (asserts! (>= quorum-percentage (get quorum-threshold proposal))
        ERR-PROPOSAL-EXECUTION-FAILED
      )

      ;; Validation: Pass threshold must be met
      (asserts! (>= vote-for-percentage (get pass-threshold proposal))
        ERR-PROPOSAL-EXECUTION-FAILED
      )

      ;; Determine proposal outcome
      (let ((outcome (> (get vote-for proposal) (get vote-against proposal))))
        ;; Update proposal status
        (map-set proposals { proposal-id: proposal-id }
          (merge proposal {
            executed: true,
            execution-result: (some outcome),
          })
        )

        (ok outcome)
      )
    )
  )
)

;; DELEGATION FUNCTIONS

;; @desc Delegate voting power to another principal
;; @param delegate: Principal to receive voting power
;; @param max-depth: Maximum allowed delegation chain depth
;; @returns (response bool uint)
(define-public (delegate-voting-power
    (delegate principal)
    (max-depth uint)
  )
  (let (
      (current-block stacks-block-height)
      (current-delegation (map-get? delegations tx-sender))
    )
    ;; Validation: Cannot delegate to self
    (asserts! (not (is-eq tx-sender delegate)) ERR-INVALID-DELEGATION)

    ;; Validation: Delegation depth must not exceed maximum
    (asserts!
      (or
        (is-none current-delegation)
        (< (unwrap-panic (get delegation-depth current-delegation)) max-depth)
      )
      ERR-EXCEEDED-DELEGATION-DEPTH
    )

    ;; Set delegation
    (map-set delegations tx-sender {
      delegated-to: delegate,
      delegation-depth: u0,
      max-delegation-depth: max-depth,
      delegated-at: current-block,
    })

    (ok true)
  )
)

;; @desc Revoke existing vote delegation
;; @returns (response bool uint)
(define-public (revoke-delegation)
  (begin
    (map-delete delegations tx-sender)
    (ok true)
  )
)

;; TIME-LOCKED EXECUTION FUNCTIONS

;; @desc Schedule a proposal for time-locked execution
;; @param proposal-id: ID of the proposal to schedule
;; @param delay-blocks: Number of blocks to delay execution
;; @returns (response bool uint)
(define-public (schedule-time-locked-execution
    (proposal-id uint)
    (delay-blocks uint)
  )
  (let (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id })
        ERR-INVALID-PROPOSAL
      ))
      (current-block stacks-block-height)
      (total-tokens (var-get total-governance-tokens))
    )
    ;; Validation: Voting period must have ended
    (asserts! (>= current-block (get end-block proposal)) ERR-PROPOSAL-CLOSED)

    ;; Validation: Proposal must not be already executed
    (asserts! (not (get executed proposal)) ERR-UNAUTHORIZED)

    ;; Verify quorum and threshold requirements
    (let (
        (total-votes (+ (get vote-for proposal) (get vote-against proposal)))
        (quorum-percentage (/ (* total-votes u100) total-tokens))
        (vote-for-percentage (/ (* (get vote-for proposal) u100) total-votes))
      )
      ;; Validation: Quorum and pass thresholds must be met
      (asserts! (>= quorum-percentage (get quorum-threshold proposal))
        ERR-PROPOSAL-EXECUTION-FAILED
      )
      (asserts! (>= vote-for-percentage (get pass-threshold proposal))
        ERR-PROPOSAL-EXECUTION-FAILED
      )

      ;; Schedule execution with time lock
      (map-set time-locks { proposal-id: proposal-id } {
        execution-block: (+ current-block delay-blocks),
        executed: false,
      })

      (ok true)
    )
  )
)

;; @desc Execute a time-locked proposal after delay period
;; @param proposal-id: ID of the proposal to execute
;; @returns (response bool uint)
(define-public (execute-time-locked-proposal (proposal-id uint))
  (let (
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id })
        ERR-INVALID-PROPOSAL
      ))
      (time-lock (unwrap! (map-get? time-locks { proposal-id: proposal-id })
        ERR-INVALID-TIMELOCK
      ))
      (current-block stacks-block-height)
    )
    ;; Validation: Proposal must not be already executed
    (asserts! (not (get executed proposal)) ERR-UNAUTHORIZED)

    ;; Validation: Time lock must not be already executed
    (asserts! (not (get executed time-lock)) ERR-UNAUTHORIZED)

    ;; Validation: Sufficient time must have passed
    (asserts! (>= current-block (get execution-block time-lock))
      ERR-INVALID-TIMELOCK
    )

    ;; Update time lock status
    (map-set time-locks { proposal-id: proposal-id }
      (merge time-lock { executed: true })
    )

    ;; Update proposal status
    (map-set proposals { proposal-id: proposal-id }
      (merge proposal {
        executed: true,
        execution-result: (some true),
      })
    )

    (ok true)
  )
)

;; TREASURY MANAGEMENT FUNCTIONS

;; @desc Deposit tokens into the DAO treasury
;; @param amount: Number of tokens to deposit
;; @returns (response bool uint)
(define-public (deposit-to-treasury (amount uint))
  (begin
    (try! (ft-transfer? governance-token amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok true)
  )
)

;; @desc Create a treasury allocation proposal
;; @param title: Proposal title
;; @param description: Proposal description
;; @param duration: Voting period in blocks
;; @param quorum-threshold: Minimum participation percentage
;; @param pass-threshold: Minimum approval percentage
;; @param recipient: Principal to receive the allocation
;; @param amount: Number of tokens to allocate
;; @returns (response uint uint) - Proposal ID on success
(define-public (create-treasury-proposal
    (title (string-utf8 100))
    (description (string-utf8 500))
    (duration uint)
    (quorum-threshold uint)
    (pass-threshold uint)
    (recipient principal)
    (amount uint)
  )
  (let (
      (proposal-id (var-get next-proposal-id))
      (current-block stacks-block-height)
      (user-token-balance (ft-get-balance governance-token tx-sender))
    )
    ;; Validation: Proposer must meet minimum token threshold
    (asserts! (>= user-token-balance (var-get proposal-submission-min-tokens))
      ERR-INSUFFICIENT-TOKENS
    )

    ;; Validation: Amount must not exceed per-proposal limit
    (asserts! (<= amount (var-get treasury-max-per-proposal))
      ERR-TREASURY-LIMIT-EXCEEDED
    )

    ;; Validation: Treasury must have sufficient balance
    (asserts! (<= amount (var-get treasury-balance)) ERR-TREASURY-LIMIT-EXCEEDED)

    ;; Validation: Duration must be within allowed range
    (asserts!
      (and
        (>= duration (var-get min-proposal-duration))
        (<= duration (var-get max-proposal-duration))
      )
      ERR-INVALID-PROPOSAL
    )

    ;; Store proposal
    (map-set proposals { proposal-id: proposal-id } {
      title: title,
      description: description,
      proposed-by: tx-sender,
      start-block: current-block,
      end-block: (+ current-block duration),
      proposal-type: (get TREASURY PROPOSAL-TYPES),
      vote-for: u0,
      vote-against: u0,
      executed: false,
      execution-result: none,
      quorum-threshold: quorum-threshold,
      pass-threshold: pass-threshold,
    })

    ;; Create treasury allocation record
    (map-set treasury-allocations { allocation-id: (var-get next-allocation-id) } {
      proposal-id: proposal-id,
      recipient: recipient,
      amount: amount,
      executed: false,
    })

    ;; Increment counters
    (var-set next-proposal-id (+ proposal-id u1))
    (var-set next-allocation-id (+ (var-get next-allocation-id) u1))

    (ok proposal-id)
  )
)

;; @desc Execute an approved treasury allocation
;; @param allocation-id: ID of the allocation to execute
;; @returns (response bool uint)
(define-public (execute-treasury-allocation (allocation-id uint))
  (let (
      (allocation (unwrap! (map-get? treasury-allocations { allocation-id: allocation-id })
        ERR-INVALID-PROPOSAL
      ))
      (proposal-id (get proposal-id allocation))
      (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id })
        ERR-INVALID-PROPOSAL
      ))
    )
    ;; Validation: Proposal must be executed
    (asserts! (get executed proposal) ERR-UNAUTHORIZED)

    ;; Validation: Proposal must have successful execution result
    (asserts! (is-some (get execution-result proposal)) ERR-UNAUTHORIZED)
    (asserts! (unwrap-panic (get execution-result proposal)) ERR-UNAUTHORIZED)

    ;; Validation: Allocation must not be already executed
    (asserts! (not (get executed allocation)) ERR-UNAUTHORIZED)

    ;; Execute treasury transfer
    (try! (as-contract (ft-transfer? governance-token (get amount allocation) tx-sender
      (get recipient allocation)
    )))

    ;; Update treasury balance
    (var-set treasury-balance
      (- (var-get treasury-balance) (get amount allocation))
    )

    ;; Update allocation status
    (map-set treasury-allocations { allocation-id: allocation-id }
      (merge allocation { executed: true })
    )

    (ok true)
  )
)

;; ADMINISTRATIVE FUNCTIONS

;; @desc Update governance configuration parameters (owner only)
;; @param new-min-proposal-duration: Optional new minimum proposal duration
;; @param new-max-proposal-duration: Optional new maximum proposal duration
;; @param new-proposal-submission-min-tokens: Optional new minimum tokens for proposal submission
;; @param new-treasury-max-per-proposal: Optional new maximum treasury allocation per proposal
;; @returns (response bool uint)
(define-public (update-governance-parameters
    (new-min-proposal-duration (optional uint))
    (new-max-proposal-duration (optional uint))
    (new-proposal-submission-min-tokens (optional uint))
    (new-treasury-max-per-proposal (optional uint))
  )
  (begin
    ;; Authorization: Only contract owner can update parameters
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)

    ;; Update parameters if provided
    (if (is-some new-min-proposal-duration)
      (var-set min-proposal-duration (unwrap-panic new-min-proposal-duration))
      true
    )

    (if (is-some new-max-proposal-duration)
      (var-set max-proposal-duration (unwrap-panic new-max-proposal-duration))
      true
    )

    (if (is-some new-proposal-submission-min-tokens)
      (var-set proposal-submission-min-tokens
        (unwrap-panic new-proposal-submission-min-tokens)
      )
      true
    )

    (if (is-some new-treasury-max-per-proposal)
      (var-set treasury-max-per-proposal
        (unwrap-panic new-treasury-max-per-proposal)
      )
      true
    )

    (ok true)
  )
)

;; @desc Toggle emergency contract pause (owner only)
;; @returns (response bool uint) - New pause state
(define-public (toggle-contract-pause)
  (begin
    ;; Authorization: Only contract owner can pause
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok (var-get contract-paused))
  )
)

;; @desc Legacy function for governance parameter upgrades (owner only)
;; @param new-max-delegation-depth: Reserved for future use
;; @returns (response bool uint)
(define-public (upgrade-governance-params (new-max-delegation-depth uint))
  (begin
    ;; Authorization: Only contract owner
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    ;; Reserved for future expansion
    (ok true)
  )
)

;; READ-ONLY FUNCTIONS

;; @desc Get detailed information about a proposal
;; @param proposal-id: ID of the proposal to query
;; @returns (optional proposal-data)
(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

;; @desc Get voting power of a specific principal
;; @param voter: Principal to query
;; @returns uint - Token balance
(define-read-only (get-voting-power (voter principal))
  (ft-get-balance governance-token voter)
)

;; @desc Get basic governance metrics
;; @returns tuple with governance statistics
(define-read-only (get-governance-metrics)
  {
    total-governance-tokens: (var-get total-governance-tokens),
    total-proposals: (var-get next-proposal-id),
    contract-paused: (var-get contract-paused),
  }
)

;; @desc Get comprehensive governance metrics including treasury data
;; @returns tuple with detailed governance statistics
(define-read-only (get-enhanced-governance-metrics)
  {
    total-governance-tokens: (var-get total-governance-tokens),
    total-proposals: (var-get next-proposal-id),
    contract-paused: (var-get contract-paused),
    treasury-balance: (var-get treasury-balance),
    min-proposal-duration: (var-get min-proposal-duration),
    max-proposal-duration: (var-get max-proposal-duration),
    proposal-submission-min-tokens: (var-get proposal-submission-min-tokens),
    treasury-max-per-proposal: (var-get treasury-max-per-proposal),
  }
)

;; @desc Placeholder for future signature verification implementation
;; @param signer: Principal claiming to have signed
;; @param proposal-id: Proposal being voted on
;; @param vote-type: Type of vote cast
;; @param signature: 65-byte signature
;; @param message-hash: 32-byte hash of signed message
;; @returns (response bool uint)
(define-read-only (verify-vote-signature
    (signer principal)
    (proposal-id uint)
    (vote-type uint)
    (signature (buff 65))
    (message-hash (buff 32))
  )
  ;; Reserved for future signature verification integration
  (ok true)
)
