# Red Team Report -- Bounty Escrow Protocol (Pre-Implementation)

> Date: 2026-03-20
> Type: Design-phase adversarial analysis (no code exists yet)
> Target: Bounty Escrow Protocol design spec
> Rounds: 8 categories + combo attacks = 32 attack vectors

---

## Summary

| Category | Vectors | EXPLOITED | SUSPICIOUS | DEFENDED |
|---|---|---|---|---|
| Access Control Bypass | 5 | 0 | 1 | 4 |
| Integer/Arithmetic Abuse | 5 | 1 | 2 | 2 |
| Object Manipulation | 4 | 0 | 1 | 3 |
| Economic Exploits | 6 | 2 | 2 | 2 |
| Input Fuzzing | 4 | 0 | 1 | 3 |
| Ordering Attacks | 3 | 0 | 1 | 2 |
| Type Confusion | 2 | 0 | 0 | 2 |
| DoS Vectors | 3 | 0 | 2 | 1 |

**Totals: 3 EXPLOITED / 10 SUSPICIOUS / 19 DEFENDED**

Confidence: 70% (32 vectors across all 8 categories + combo analysis)

---

## Category 1: Access Control Bypass

### 1.1 Non-creator calls cancel()

- **Attack**: Attacker calls `cancel()` on someone else's Bounty.
- **Expected**: Should abort with `E_NOT_CREATOR`.
- **Spec defense**: `cancel()` checks `caller == creator`. DEFENDED.
- **Recommendation**: None -- straightforward sender check.

### 1.2 Non-verifier calls verify()

- **Attack**: Random address calls `verify()` without a valid `VerifierCap`.
- **Expected**: Should abort. Attacker cannot produce a `VerifierCap` for this bounty.
- **Spec defense**: `verify()` requires `cap: &VerifierCap` as parameter + `validate_cap(cap, bounty.id)`. `VerifierCap` is only minted inside `create()` via `public(package) fun issue_cap()`. DEFENDED.
- **Recommendation**: None.

### 1.3 Forge VerifierCap from another package

- **Attack**: Attacker deploys their own package that creates a struct also named `VerifierCap` and passes it to `verify()`.
- **Expected**: Move type system rejects at transaction level -- different module origin = different type.
- **Spec defense**: Sui Move type identity includes package address. DEFENDED.
- **Recommendation**: None.

### 1.4 Claim with a ClaimTicket from a different bounty

- **Attack**: Hunter has a valid `ClaimTicket` for bounty A, passes it to `verify()` targeting bounty B.
- **Expected**: Should abort with `E_TICKET_BOUNTY_MISMATCH`.
- **Spec defense**: `verify()` checks `ticket.bounty_id == bounty.id`. DEFENDED.
- **Recommendation**: None.

### 1.5 Creator claims own bounty via second address

- **Attack**: Creator uses a different address to claim their own bounty, then colludes with verifier.
- **Expected**: `claim()` blocks `caller == creator`, but not a second address controlled by the same person.
- **Spec defense**: Only blocks exact `creator` address. SUSPICIOUS -- sybil claims are not preventable on-chain.
- **Recommendation**: This is fundamentally unsolvable on-chain. Document as a known limitation. Upper-layer applications can add reputation systems or require identity verification. Consider adding a minimum `required_stake` enforcement at protocol level so sybil claiming at least costs capital.

---

## Category 2: Integer/Arithmetic Abuse

### 2.1 reward_amount * max_claims overflow

- **Attack**: Set `reward_amount = 2^63` and `max_claims = 3`. Product overflows u64.
- **Expected**: Should abort at `create()`.
- **Spec defense**: Spec says "create 時檢查乘法溢出" and Sui Move aborts on overflow. DEFENDED.
- **Recommendation**: Use explicit checked multiplication and abort with a clear error code (e.g., `E_OVERFLOW`). Do NOT rely solely on Move's implicit overflow abort -- the error message is unhelpful for debugging.

### 2.2 cleanup_reward rounding to zero, dust left in escrow

- **Attack**: Set `cleanup_reward_bps = 1` (0.01%) on a small escrow like 99 tokens. `calculate_cleanup_reward(99, 1) = 99 * 1 / 10000 = 0`. Cleanup caller gets 0 reward, no incentive to call `expire()`.
- **Expected**: `expire()` still works, caller just gets 0.
- **Spec defense**: None -- this is a design gap. EXPLOITED (economic, not security).
- **Recommendation**: Add a minimum cleanup reward floor (e.g., 1 unit) when `cleanup_reward_bps > 0` and escrow is non-zero. OR document that tiny bounties may have no cleanup incentive and rely on altruistic expiration.

### 2.3 required_stake = 0 with penalty calculation

- **Attack**: Creator sets `required_stake = 0`. Hunter claims for free. On cancel, penalty = `required_stake` = 0 per hunter. Hunter gets stake(0) + penalty(0) = nothing. Creator gets full escrow back.
- **Expected**: This is "working as designed" but it means zero-stake bounties give hunters zero protection against creator cancellation.
- **Spec defense**: Spec allows `required_stake = 0`. SUSPICIOUS.
- **Recommendation**: Document explicitly that `required_stake = 0` means hunters have no cancellation protection. Consider emitting a warning event or requiring a minimum stake. At minimum, the `abandon()` function should still work (forfeit 0 stake -- confirm no division by zero anywhere).

### 2.4 Penalty exhausts escrow, blocking cancel

- **Attack**: Create bounty with `reward_amount = 100`, `required_stake = 200`, `max_claims = 5`. Escrow = 500 (100*5). After 2 verifies, escrow = 300. Now cancel with 3 active claims needs penalty = 200*3 = 600 > 300. Cancel aborts.
- **Expected**: `E_INSUFFICIENT_ESCROW_FOR_PENALTY`. Creator stuck until expire.
- **Spec defense**: Spec acknowledges this scenario explicitly. DEFENDED (by design).
- **Recommendation**: The spec correctly identifies this. Ensure the error code is clear. Consider adding a `can_cancel()` view function so front-ends can check before attempting.

### 2.5 cleanup_reward_bps precision attack on large escrow

- **Attack**: `cleanup_reward_bps = 1000` (10%) on escrow of `u64::MAX`. `calculate_cleanup_reward(u64::MAX, 1000)` = `u64::MAX * 1000 / 10000`. The multiplication `u64::MAX * 1000` overflows u64.
- **Expected**: Should abort or be handled.
- **Spec defense**: No mention of overflow in `calculate_cleanup_reward`. SUSPICIOUS.
- **Recommendation**: Use `(total as u128) * (bps as u128) / 10000` to avoid intermediate overflow, then cast back to u64. This is a real bug if not handled.

---

## Category 3: Object Manipulation

### 3.1 Reuse consumed ClaimTicket

- **Attack**: After `verify()` consumes a ClaimTicket by value, try to use it again.
- **Expected**: Impossible -- Move's linear type system destroys the object.
- **Spec defense**: `verify()` and `abandon()` take `ticket: ClaimTicket` by value. DEFENDED.
- **Recommendation**: None -- Move enforces this at the language level.

### 3.2 Wrap Bounty object into another struct

- **Attack**: Wrap `Bounty<T>` inside another struct to manipulate access patterns.
- **Expected**: Impossible -- `Bounty` has `key` but no `store`, cannot be wrapped.
- **Spec defense**: Explicit design decision: "無 store ability". DEFENDED.
- **Recommendation**: None.

### 3.3 Use ClaimTicket from bounty A on bounty B for verify

- **Attack**: Pass a valid ticket (for bounty A) to `verify()` called on bounty B.
- **Expected**: Abort with `E_TICKET_BOUNTY_MISMATCH`.
- **Spec defense**: `verify()` checks `ticket.bounty_id == bounty.id`. DEFENDED.
- **Recommendation**: None.

### 3.4 Orphan ClaimTicket resource leak after cancel/expire

- **Attack**: After a bounty is cancelled/expired, hunters still hold their `ClaimTicket` objects. These are dead objects consuming storage.
- **Expected**: `destroy_ticket()` exists for cleanup, but requires hunter to call it.
- **Spec defense**: `destroy_ticket()` function exists. SUSPICIOUS -- relies on hunter cooperation for cleanup.
- **Recommendation**: Consider allowing anyone (not just the ticket owner) to call `destroy_ticket()` when the bounty is in a terminal state. The ticket has no value at that point, so there's no ownership concern. This enables third-party cleanup bots. Also consider whether `destroy_ticket` should give a small storage rebate incentive.

---

## Category 4: Economic Exploits

### 4.1 Creator griefing -- impossible conditions

- **Attack**: Creator sets `required_stake = u64::MAX - 1` (absurdly high) so no one can claim. Bounty sits idle. Creator waits for deadline, calls expire, gets full escrow back (minus cleanup reward to self).
- **Expected**: Creator can self-grief to recover escrow minus cleanup reward.
- **Spec defense**: None -- the protocol allows arbitrary parameters. SUSPICIOUS.
- **Recommendation**: Not a vulnerability per se (creator loses cleanup reward to whoever expires it, or loses nothing if they expire it themselves). But it could be used to spam the bounty board. Consider a minimum bounty creation fee or requiring `required_stake <= reward_amount` as a sanity check.

### 4.2 Creator cancels right before deadline

- **Attack**: Creator creates bounty, waits for hunters to claim and invest time, cancels 1 second before deadline. Hunters get stake + penalty back, but wasted effort.
- **Expected**: Hunters get compensated via penalty. The penalty = `required_stake` per hunter.
- **Spec defense**: Penalty mechanism exists. DEFENDED -- but only economically fair if penalty covers opportunity cost.
- **Recommendation**: The penalty design is sound. Document that `required_stake` should be set high enough to deter frivolous cancellation. Upper-layer apps can enforce minimum penalty ratios.

### 4.3 Hunter slot-squatting -- claim all slots with minimum stake, never complete

- **Attack**: Hunter (or sybil accounts) claims all `max_claims` slots. Never completes work. Holds bounty hostage until deadline.
- **Expected**: Hunters forfeit `required_stake` on expire. Creator gets stakes + remaining escrow.
- **Spec defense**: `required_stake` serves as anti-squatting mechanism. DEFENDED -- IF `required_stake` is set meaningfully.
- **Recommendation**: If `required_stake = 0`, this attack is free. Strongly recommend documenting that creators should set `required_stake > 0` to prevent squatting. Consider enforcing `required_stake > 0` at protocol level, or at least emitting a warning event.

### 4.4 Cleanup reward farming

- **Attack**: Attacker creates a bounty with `cleanup_reward_bps = 1000` (10%), deposits 1000 tokens, sets deadline = now + 1 second. Nobody claims. After 1 second, attacker (from another address) calls `expire()` and collects 100 tokens as cleanup reward. Creator address gets 900 back. Net cost to attacker: 0 (controls both addresses).
- **Expected**: Attacker controls both sides, so they pay themselves. Net economic effect: zero (minus gas).
- **Spec defense**: None explicitly. EXPLOITED -- but only for gas waste / bounty board spam.
- **Recommendation**: This is a self-dealing attack with no profit, but it pollutes the bounty board and wastes chain storage. Consider: (1) minimum bounty duration (e.g., 1 hour), (2) minimum escrow amount, (3) non-refundable creation fee. At minimum, document this as a known spam vector.

### 4.5 Collusion -- creator and verifier verify without work

- **Attack**: Creator sets `verifier = own_address_2`. Creates bounty. Sybil hunter claims. Verifier immediately verifies without checking work. Hunter gets reward + stake back.
- **Expected**: Protocol cannot distinguish legitimate verification from collusion.
- **Spec defense**: None -- this is by design (protocol is agnostic to verification logic). EXPLOITED (at the protocol level).
- **Recommendation**: This is inherent to any system with a single trusted verifier. The spec acknowledges this by making verification pluggable. Mitigations are upper-layer concerns: (1) multi-sig verifier, (2) oracle-based verification, (3) dispute period, (4) reputation system. Document this as an explicit trust assumption: "The protocol trusts that the verifier acts honestly. Collusion between creator and verifier is outside the protocol's threat model."

### 4.6 Abandon timing exploit

- **Attack**: Hunter claims, does the work, then calls `abandon()` instead of waiting for verify. Stake goes to creator. Then hunter submits work through a side channel and demands payment off-chain.
- **Expected**: Hunter loses stake. This is self-harming.
- **Spec defense**: Not really an attack. DEFENDED -- rational actors won't abandon completed work.
- **Recommendation**: None -- this is hunter self-sabotage.

---

## Category 5: Input Fuzzing

### 5.1 Empty title and description

- **Attack**: Call `create()` with `title = ""` and `description = ""`.
- **Expected**: Spec checks length <= MAX, but does not check length > 0.
- **Spec defense**: Only max-length checks exist. SUSPICIOUS.
- **Recommendation**: Add `E_TITLE_EMPTY` check. Empty bounties are likely spam. Enforce `title.length() > 0`.

### 5.2 max_claims = u64::MAX

- **Attack**: Set `max_claims = u64::MAX`. Then `reward_amount * max_claims` overflows.
- **Expected**: Overflow check at create catches this (if `reward_amount > 0`).
- **Spec defense**: Spec has `MAX_CLAIMS = 100` constant. DEFENDED.
- **Recommendation**: Ensure `create()` checks `max_claims <= MAX_CLAIMS` and aborts with `E_MAX_CLAIMS_TOO_HIGH`.

### 5.3 deadline = 0

- **Attack**: Set `deadline = 0` (epoch start).
- **Expected**: `deadline > now` check fails since `now` is always > 0.
- **Spec defense**: `create()` checks `deadline > now`. DEFENDED.
- **Recommendation**: None.

### 5.4 All metadata keys/values at max length

- **Attack**: Fill `metadata` VecMap with many entries, each with max-length strings.
- **Expected**: No limit on metadata entries in spec.
- **Spec defense**: None -- metadata is unbounded. DEFENDED at the Sui transaction size limit, but could bloat object storage.
- **Recommendation**: Add `MAX_METADATA_ENTRIES` (e.g., 20) and `MAX_METADATA_KEY_LENGTH` / `MAX_METADATA_VALUE_LENGTH` limits. Without these, a single bounty object could consume excessive storage.

---

## Category 6: Ordering Attacks

### 6.1 claim() and cancel() race on same bounty

- **Attack**: Hunter submits `claim()` tx, creator submits `cancel()` tx simultaneously. Both reference the same shared `Bounty<T>` object.
- **Expected**: Sui's object-based sequencing serializes them. One executes first.
- **Spec defense**: Sui shared object consensus orders transactions. If cancel goes first, claim sees non-Open status and aborts. If claim goes first, cancel handles active claims with penalty. DEFENDED.
- **Recommendation**: None -- Sui's architecture handles this correctly.

### 6.2 verify() and expire() race

- **Attack**: Verifier submits `verify()` at the same time someone submits `expire()` right after deadline.
- **Expected**: Serialized by Sui. If verify goes first, it succeeds (no deadline check on verify per spec). If expire goes first, bounty becomes Expired and verify fails on status check.
- **Spec defense**: SUSPICIOUS -- `verify()` has NO deadline check in the spec's per-function checks table. A verifier can verify after the deadline as long as no one has called `expire()` yet.
- **Recommendation**: This is arguably a feature (late verification should still count if the work was done). But it creates a race: if someone expires first, the hunter loses their stake even though work was completed. Consider adding a grace period: verify is allowed for X seconds after deadline even if expire has been called. OR add a deadline check to verify and force all verification to happen before deadline.

### 6.3 Multiple claims in same transaction (PTB)

- **Attack**: Use a Programmable Transaction Block to call `claim()` multiple times in the same transaction with different sender contexts.
- **Expected**: In a single PTB, the sender is fixed. `claimed_hunters` VecSet would catch the duplicate on the second call.
- **Spec defense**: `claimed_hunters` VecSet + single sender per PTB. DEFENDED.
- **Recommendation**: None.

---

## Category 7: Type Confusion

### 7.1 Wrong Coin<T> type

- **Attack**: Bounty is `Bounty<SUI>`. Attacker tries to call `claim<USDC>(bounty, usdc_coin, ...)`.
- **Expected**: Move type checker rejects -- `bounty: &mut Bounty<T>` and `stake_coin: Coin<T>` must share the same `T`. Passing `Bounty<SUI>` with `Coin<USDC>` is a type mismatch.
- **Spec defense**: Move generics enforce type consistency at compile/runtime. DEFENDED.
- **Recommendation**: None.

### 7.2 Pass ClaimTicket to wrong bounty's destroy_ticket

- **Attack**: Call `destroy_ticket(ticket_for_A, bounty_B)` where bounty_B is in terminal state but bounty_A is not.
- **Expected**: Should check `ticket.bounty_id == bounty.id`.
- **Spec defense**: Spec shows `destroy_ticket(ticket: ClaimTicket, bounty: &Bounty<T>, ...)`. The bounty_id matching check should be enforced. DEFENDED (assuming implementation checks this).
- **Recommendation**: Ensure `destroy_ticket` validates `ticket.bounty_id == bounty.id`. The spec doesn't explicitly list this check -- add it to the per-function checks table.

---

## Category 8: DoS Vectors

### 8.1 Fill VecSet/VecMap to max (100 entries)

- **Attack**: 100 different addresses each claim. `claimed_hunters` VecSet has 100 entries. `active_hunter_stakes` VecMap has 100 entries. On `cancel()`, iterating all 100 entries for penalty distribution.
- **Expected**: Gas cost scales linearly. At max_claims=100, this should be within Sui gas limits.
- **Spec defense**: `MAX_CLAIMS = 100` caps the size. SUSPICIOUS -- needs gas benchmarking.
- **Recommendation**: Benchmark `cancel()` with 100 active claims. VecMap iteration is O(n) per lookup too. If gas is borderline, reduce MAX_CLAIMS to 50, or restructure cancel to not iterate (e.g., use a withdrawal pattern where each hunter claims their own penalty). The current design requires a single `cancel()` tx to pay ALL hunters atomically -- this could hit gas limits.

### 8.2 Create thousands of bounties (board spam)

- **Attack**: Spam `create()` to flood the bounty board with garbage bounties.
- **Expected**: Each creation costs gas + locks escrow. But with minimum `reward_amount = 1` and `max_claims = 1`, cost is ~1 token + gas per bounty.
- **Spec defense**: No anti-spam mechanism. SUSPICIOUS.
- **Recommendation**: Protocol level: consider a non-refundable creation fee (even 0.01 SUI). Application level: implement off-chain indexing with filters, reputation scores, and pagination. The protocol itself should remain permissionless, but document the spam risk.

### 8.3 Claim and abandon loop to bloat claimed_hunters

- **Attack**: Hunter A claims, abandons (stake forfeited). Hunter A is permanently in `claimed_hunters` and cannot claim again. But the VecSet entry persists forever.
- **Expected**: Each unique address adds one entry. `claimed_hunters` never shrinks. After `max_claims` unique addresses have claimed (even if all abandoned), no one else can claim.
- **Spec defense**: `claimed_hunters` includes abandoned hunters. `max_claims` limits entries. DEFENDED -- bounded by MAX_CLAIMS.
- **Recommendation**: Wait -- this is actually a subtle issue. `claimed_hunters` prevents re-claiming, and it includes abandoned hunters. So if `max_claims = 5` and 5 different hunters each claim and abandon, the bounty has `active_claims = 0` but `claimed_hunters.size() = 5`. Can a 6th hunter claim? The check is `active_claims < max_claims`, so YES the 6th hunter can claim. But `claimed_hunters` will grow beyond `max_claims`. This is fine for the VecSet (bounded by total unique addresses that ever interacted), but it could grow larger than MAX_CLAIMS. **Clarify in spec**: `claimed_hunters` can exceed `max_claims` size. Ensure no code assumes `claimed_hunters.size() <= max_claims`.

---

## Combo Attacks

### C.1 Economic + Arithmetic: Cleanup reward self-dealing with rounding

- **Attack**: Create bounty with `escrow = 10001`, `cleanup_reward_bps = 999` (9.99%). `calculate_cleanup_reward(10001, 999) = 10001 * 999 / 10000 = 9990`. Creator gets back `10001 - 9990 = 11`. If attacker is both creator and expirer, they get `9990 + 11 = 10001` back minus gas. Net loss = gas only.
- **Status**: Not exploitable for profit. DEFENDED (self-dealing).

### C.2 Access Control + Object: Destroy someone else's ClaimTicket

- **Attack**: After a bounty expires, call `destroy_ticket()` passing someone else's ticket.
- **Expected**: `ClaimTicket` has `key` only (no `store`). Only the owner can pass it as a transaction argument in Sui. An attacker cannot reference someone else's owned object.
- **Status**: DEFENDED by Sui's owned object model.

### C.3 Ordering + Economic: Front-run expire with last-second verify

- **Attack**: Verifier watches mempool. Sees someone about to call `expire()`. Quickly submits `verify()` for a hunter who didn't actually complete work. Hunter gets reward + stake, creator loses funds.
- **Expected**: Sui doesn't have a public mempool in the traditional sense. Shared object transactions go through consensus. But if verifier is already colluding, they don't need to front-run -- they can verify anytime.
- **Status**: Reduces to collusion attack (4.5). DEFENDED by Sui's consensus model against external front-running.

### C.4 DoS + Economic: Grief cancel by filling all slots

- **Attack**: Sybil attacker fills all `max_claims` slots with minimum stake. Creator wants to cancel but must pay `required_stake * max_claims` in penalties from escrow. If `required_stake * max_claims > escrow` (possible after some verifies), creator is trapped.
- **Expected**: Creator cannot cancel, must wait for expire. On expire, sybil attacker loses all stakes.
- **Status**: Attacker loses `required_stake * max_claims` tokens. Only profitable if the goal is to grief the creator. SUSPICIOUS -- griefing attack with a cost.
- **Recommendation**: Document this risk. Creators should set `required_stake` high enough that squatting is expensive, but not so high that penalty exceeds remaining escrow.

---

## Critical Findings (Ordered by Severity)

### HIGH -- Must fix before implementation

1. **[2.5] Overflow in `calculate_cleanup_reward`**: `total * bps` can overflow u64 for large escrow values. Use u128 intermediate arithmetic.

2. **[8.1] Gas limit on `cancel()` with max active claims**: Cancel iterates all active hunters to distribute penalties. At 100 hunters, this may exceed gas limits. Benchmark required; consider reducing MAX_CLAIMS or switching to withdrawal pattern.

### MEDIUM -- Should fix

3. **[2.2] Zero cleanup reward for small bounties**: Rounding to zero removes economic incentive for expiration. Add minimum floor or document limitation.

4. **[6.2] Verify/expire race condition**: No deadline check on verify means late verification races with expiration. Define explicit policy.

5. **[5.1] Empty title allowed**: Enables low-effort spam bounties. Add minimum length check.

6. **[5.4] Unbounded metadata**: No limit on metadata entries. Add `MAX_METADATA_ENTRIES`.

7. **[8.3] `claimed_hunters` can exceed `max_claims`**: Spec should clarify this is intentional and implementation should not assume bounded size.

### LOW -- Document as known limitations

8. **[1.5] Sybil resistance**: Creator can claim own bounty via second address. Unsolvable on-chain.

9. **[4.4] Cleanup reward farming / spam**: Self-dealing has no profit but pollutes state.

10. **[4.5] Creator-verifier collusion**: Inherent trust assumption. Document explicitly.

11. **[4.1] Impossible conditions griefing**: Creator can set absurd parameters. Application-layer concern.

---

## Recommended Spec Amendments

```
1. calculate_cleanup_reward():
   - Use u128 intermediate: (total as u128) * (bps as u128) / 10000
   - Add minimum reward floor: max(calculated, 1) when bps > 0 and total > 0

2. create() additional checks:
   - title.length() > 0                     → E_TITLE_EMPTY
   - metadata.size() <= MAX_METADATA_ENTRIES → E_TOO_MANY_METADATA
   - Consider: deadline >= now + MIN_DURATION → E_DEADLINE_TOO_SOON

3. cancel() gas safety:
   - Benchmark with MAX_CLAIMS active hunters
   - If gas exceeds limit, implement withdrawal pattern:
     cancel() only marks state as Cancelled
     withdraw_penalty() lets each hunter pull their own funds

4. verify() deadline policy (choose one):
   - Option A: Add deadline check (verify must happen before deadline)
   - Option B: No deadline check (current design), document the race risk
   - Option C: Grace period (verify allowed up to X seconds after deadline)

5. destroy_ticket() per-function checks:
   - Add explicit check: ticket.bounty_id == bounty.id

6. Security Model section:
   - Document: "Protocol trusts the designated verifier. Collusion is outside threat model."
   - Document: "Sybil resistance is not provided. Applications should add reputation layers."
   - Document: "required_stake = 0 provides no hunter protection against cancellation."

7. claimed_hunters clarification:
   - Explicitly state: claimed_hunters may grow beyond max_claims due to abandon cycles
   - Ensure no invariant assumes claimed_hunters.size() <= max_claims
```

---

## Test Recommendations for Implementation Phase

When code exists, re-run red team with executable attack tests. Priority tests:

| Priority | Test | Validates |
|---|---|---|
| P0 | `cancel()` with 100 active claims -- measure gas | Finding 8.1 |
| P0 | `calculate_cleanup_reward(u64::MAX, 1000)` | Finding 2.5 |
| P0 | `expire()` with escrow=99, bps=1 -- verify cleanup_reward | Finding 2.2 |
| P1 | `create()` with title="" | Finding 5.1 |
| P1 | `verify()` after deadline but before expire | Finding 6.2 |
| P1 | `destroy_ticket()` with mismatched bounty_id | Finding 7.2 |
| P1 | 5 claim + 5 abandon + 5 new claim -- check claimed_hunters size | Finding 8.3 |
| P2 | Full lifecycle with `required_stake = 0` | Finding 2.3 |
| P2 | `create()` with 50 metadata entries | Finding 5.4 |
