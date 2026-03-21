/// Intel Bounty — Frontier Explorer Hub integration example.
///
/// Corporation posts intel bounty (zero stake) → Explorer claims →
/// Verifier approves → Explorer collects reward.
/// Also demonstrates the expire (cleanup) path.
///
/// TypeScript PTB examples: see docs/integration-guide.md §4
module intel_bounty::intel_bounty;

use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;

// ═══════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════

const GRACE_PERIOD_MS: u64 = 86_400_000;   // 1 day
const CLEANUP_REWARD_BPS: u16 = 100;        // 1%

// ═══════════════════════════════════════════════
// Creator functions
// ═══════════════════════════════════════════════

/// Create an intel bounty. Zero stake required — explorers risk nothing.
/// `max_reporters`: how many explorers can claim (multi-reporter).
/// Returns change coin (composable).
public fun create_intel_bounty(
    title: String,
    description: String,
    payment: Coin<SUI>,
    reward_per_report: u64,
    max_reporters: u64,
    deadline: u64,
    verifier_addr: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    let (change, _bounty_id) = bounty::create_bounty<SUI>(
        title,
        description,
        payment,
        reward_per_report,
        0,                    // required_stake = 0 (intel tasks)
        max_reporters,
        deadline,
        GRACE_PERIOD_MS,
        CLEANUP_REWARD_BPS,
        verifier_addr,
        clock,
        ctx,
    );
    change
}

// ═══════════════════════════════════════════════
// Explorer (hunter) functions
// ═══════════════════════════════════════════════

/// Explorer accepts the bounty. Pass a zero-value coin for the stake.
/// Ticket + change are transferred to the caller automatically.
public fun accept_intel_bounty(
    bounty: &mut Bounty<SUI>,
    zero_coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::claim<SUI>(bounty, zero_coin, clock, ctx)
}

/// Explorer collects reward after being approved.
public fun collect_intel_reward(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    bounty::claim_reward_bounty<SUI>(bounty, ticket, ctx)
}

// ═══════════════════════════════════════════════
// Verifier functions
// ═══════════════════════════════════════════════

/// Verifier approves an explorer's submission.
/// In production, add IntelReport quality checks here before approving.
public fun verify_intel(
    bounty: &mut Bounty<SUI>,
    explorer: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::approve_hunter<SUI>(bounty, explorer, cap, clock, ctx)
}

// ═══════════════════════════════════════════════
// Cleanup (permissionless)
// ═══════════════════════════════════════════════

/// Expire a stale intel bounty. Anyone can call after deadline + grace.
/// Caller receives cleanup reward (1%).
public fun expire_intel_bounty(
    bounty: &mut Bounty<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    bounty::expire_bounty<SUI>(bounty, clock, ctx)
}

// ═══════════════════════════════════════════════
// Read-only accessors
// ═══════════════════════════════════════════════

public fun intel_bounty_status(bounty: &Bounty<SUI>): u8 {
    bounty::status<SUI>(bounty)
}

public fun intel_bounty_reward(bounty: &Bounty<SUI>): u64 {
    bounty::reward_amount<SUI>(bounty)
}
