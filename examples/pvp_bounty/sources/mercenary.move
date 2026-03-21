/// PvP Bounty — Fleet Command integration example.
///
/// Commander issues kill order → Mercenary accepts (10% stake) →
/// Battle Judge verifies → Mercenary collects reward + stake.
/// Also demonstrates abandon (desertion) and cancel paths.
///
/// TypeScript PTB examples: see docs/integration-guide.md §5
module pvp_bounty::mercenary;

use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;

// ═══════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════

/// Mercenary must stake 10% of reward as commitment
const STAKE_RATIO_BPS: u64 = 1000;         // 10%
const MAX_MERCENARIES: u64 = 3;
const GRACE_PERIOD_MS: u64 = 172_800_000;  // 2 days
const CLEANUP_REWARD_BPS: u16 = 200;        // 2%

// ═══════════════════════════════════════════════
// Commander (creator) functions
// ═══════════════════════════════════════════════

/// Issue a kill order. Auto-calculates required stake = reward × 10%.
/// Returns change coin (composable).
public fun issue_kill_order(
    target_name: String,
    description: String,
    payment: Coin<SUI>,
    reward: u64,
    deadline: u64,
    battle_judge: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    let stake = reward * STAKE_RATIO_BPS / 10000;

    let (change, _bounty_id) = bounty::create_bounty<SUI>(
        target_name,
        description,
        payment,
        reward,
        stake,
        MAX_MERCENARIES,
        deadline,
        GRACE_PERIOD_MS,
        CLEANUP_REWARD_BPS,
        battle_judge,
        clock,
        ctx,
    );
    change
}

/// Commander cancels the kill order.
/// If mercenaries have claimed, triggers withdrawal pattern.
public fun cancel_kill_order(
    bounty: &mut Bounty<SUI>,
    ctx: &mut TxContext,
) {
    bounty::cancel_bounty<SUI>(bounty, ctx)
}

// ═══════════════════════════════════════════════
// Mercenary (hunter) functions
// ═══════════════════════════════════════════════

/// Mercenary accepts the kill order with stake.
/// Returns (ClaimTicket, change coin) — composable variant.
public fun accept_kill_order(
    bounty: &mut Bounty<SUI>,
    stake_coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<SUI>) {
    bounty::claim_bounty<SUI>(bounty, stake_coin, clock, ctx)
}

/// Mercenary accepts the kill order — non-composable (auto-transfers ticket + change).
public fun accept_kill_order_and_keep(
    bounty: &mut Bounty<SUI>,
    stake_coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::claim<SUI>(bounty, stake_coin, clock, ctx)
}

/// Mercenary collects reward after battle judge approval.
public fun collect_bounty(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    bounty::claim_reward_bounty<SUI>(bounty, ticket, ctx)
}

/// Mercenary deserts — forfeits stake to commander.
public fun desert(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::abandon_bounty<SUI>(bounty, ticket, clock, ctx)
}

// ═══════════════════════════════════════════════
// Battle Judge (verifier) functions
// ═══════════════════════════════════════════════

/// Battle Judge verifies a kill.
/// In production, add kill-proof validation here.
public fun verify_kill(
    bounty: &mut Bounty<SUI>,
    mercenary: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::approve_hunter<SUI>(bounty, mercenary, cap, clock, ctx)
}

// ═══════════════════════════════════════════════
// Read-only accessors
// ═══════════════════════════════════════════════

public fun kill_order_status(bounty: &Bounty<SUI>): u8 {
    bounty::status<SUI>(bounty)
}

public fun kill_order_reward(bounty: &Bounty<SUI>): u64 {
    bounty::reward_amount<SUI>(bounty)
}

public fun kill_order_stake(bounty: &Bounty<SUI>): u64 {
    bounty::required_stake<SUI>(bounty)
}
