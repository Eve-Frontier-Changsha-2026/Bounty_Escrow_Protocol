/// Logistics Bounty — Tribal Governance DAO integration example.
///
/// DAO posts logistics task → Runner accepts (security deposit) →
/// DAO Council verifies → Runner collects payment.
/// Also demonstrates cancel → withdrawal pattern (cancel + withdraw_penalty
/// + withdraw_remaining).
///
/// TypeScript PTB examples: see docs/integration-guide.md §6
module logistics_bounty::logistics;

use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;

// ═══════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════

const MAX_RUNNERS: u64 = 1;                // single runner per task
const GRACE_PERIOD_MS: u64 = 259_200_000;  // 3 days
const CLEANUP_REWARD_BPS: u16 = 50;         // 0.5%

// ═══════════════════════════════════════════════
// DAO (creator) functions
// ═══════════════════════════════════════════════

/// DAO posts a logistics task.
/// `security_deposit`: runner must stake this amount as guarantee.
/// `dao_multisig`: the multi-sig address that also acts as verifier.
/// Returns change coin (composable).
public fun post_logistics_task(
    title: String,
    description: String,
    treasury_coin: Coin<SUI>,
    reward: u64,
    security_deposit: u64,
    deadline: u64,
    dao_multisig: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    let (change, _bounty_id) = bounty::create_bounty<SUI>(
        title,
        description,
        treasury_coin,
        reward,
        security_deposit,
        MAX_RUNNERS,
        deadline,
        GRACE_PERIOD_MS,
        CLEANUP_REWARD_BPS,
        dao_multisig,
        clock,
        ctx,
    );
    change
}

/// DAO cancels the task. If a runner has claimed, triggers withdrawal pattern.
public fun cancel_task(
    bounty: &mut Bounty<SUI>,
    ctx: &mut TxContext,
) {
    bounty::cancel_bounty<SUI>(bounty, ctx)
}

/// After all runners have withdrawn penalties, DAO takes remaining funds.
public fun dao_withdraw_remaining(
    bounty: &mut Bounty<SUI>,
    ctx: &mut TxContext,
) {
    bounty::withdraw_remaining_bounty<SUI>(bounty, ctx)
}

// ═══════════════════════════════════════════════
// Runner (hunter) functions
// ═══════════════════════════════════════════════

/// Runner accepts the logistics task with security deposit.
/// ClaimTicket is auto-transferred to caller; excess deposit change is
/// auto-transferred if non-zero.
///
/// NOTE: `ClaimTicket` has only `key` (no `store`), so it cannot be
/// transferred outside the defining module. We use `bounty::claim` which
/// handles the internal `transfer::transfer` for us.
public fun accept_logistics_task(
    bounty: &mut Bounty<SUI>,
    deposit_coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::claim<SUI>(bounty, deposit_coin, clock, ctx)
}

/// Runner collects payment after DAO council approval.
public fun collect_payment(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    bounty::claim_reward_bounty<SUI>(bounty, ticket, ctx)
}

/// After DAO cancels, runner withdraws deposit + penalty compensation.
public fun runner_withdraw(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    bounty::withdraw_penalty_bounty<SUI>(bounty, ticket, ctx)
}

// ═══════════════════════════════════════════════
// DAO Council (verifier) functions
// ═══════════════════════════════════════════════

/// DAO Council approves delivery.
/// In production, verify delivery proof before approving.
public fun approve_delivery(
    bounty: &mut Bounty<SUI>,
    runner: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::approve_hunter<SUI>(bounty, runner, cap, clock, ctx)
}

// ═══════════════════════════════════════════════
// Read-only accessors
// ═══════════════════════════════════════════════

public fun task_status(bounty: &Bounty<SUI>): u8 {
    bounty::status<SUI>(bounty)
}

public fun task_reward(bounty: &Bounty<SUI>): u64 {
    bounty::reward_amount<SUI>(bounty)
}
