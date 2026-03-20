module bounty_escrow::bounty;

use std::string::String;
use sui::object::{Self, UID, ID};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::clock::Clock;
use sui::transfer;
use sui::event;
use sui::vec_set::{Self, VecSet};
use sui::vec_map::{Self, VecMap};
use bounty_escrow::constants;
use bounty_escrow::escrow;
use bounty_escrow::verifier::{Self, VerifierCap};

// === Structs ===

public struct Bounty<phantom T> has key {
    id: UID,
    version: u64,
    creator: address,
    title: String,
    description: String,
    escrow: Balance<T>,
    stake_pool: Balance<T>,
    reward_amount: u64,
    required_stake: u64,
    cleanup_reward_bps: u16,
    deadline: u64,
    grace_period: u64,
    status: u8,
    max_claims: u64,
    active_claims: u64,
    completed_claims: u64,
    claimed_hunters: VecSet<address>,
    active_hunter_stakes: VecMap<address, u64>,
    approved_hunters: VecSet<address>,
    metadata: VecMap<String, String>,
}

public struct ClaimTicket has key {
    id: UID,
    bounty_id: ID,
    hunter: address,
    stake_amount: u64,
    claimed_at: u64,
}

// === Events ===

public struct BountyCreated has copy, drop {
    bounty_id: ID,
    creator: address,
    coin_type: std::ascii::String,
    reward_amount: u64,
    required_stake: u64,
    max_claims: u64,
    deadline: u64,
    grace_period: u64,
    verifier: address,
}

public struct BountyClaimed has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
    hunter: address,
    stake_amount: u64,
}

public struct BountyApproved has copy, drop {
    bounty_id: ID,
    hunter: address,
    verifier: address,
}

public struct RewardClaimed has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
    hunter: address,
    reward_amount: u64,
    stake_returned: u64,
}

public struct BountyCancelled has copy, drop {
    bounty_id: ID,
    creator: address,
    active_claims_at_cancel: u64,
    penalty_per_hunter: u64,
}

public struct PenaltyWithdrawn has copy, drop {
    bounty_id: ID,
    hunter: address,
    stake_returned: u64,
    penalty_received: u64,
}

public struct RemainingWithdrawn has copy, drop {
    bounty_id: ID,
    creator: address,
    escrow_returned: u64,
    stakes_returned: u64,
}

public struct BountyExpired has copy, drop {
    bounty_id: ID,
    caller: address,
    cleanup_reward: u64,
    refund_to_creator: u64,
    forfeited_stakes: u64,
}

public struct BountyAbandoned has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
    hunter: address,
    forfeited_stake: u64,
}

public struct TicketDestroyed has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
}

public struct VerifierCapDestroyed has copy, drop {
    bounty_id: ID,
    cap_id: ID,
}

// === Accessors ===

public fun status<T>(bounty: &Bounty<T>): u8 { bounty.status }
public fun creator<T>(bounty: &Bounty<T>): address { bounty.creator }
public fun reward_amount<T>(bounty: &Bounty<T>): u64 { bounty.reward_amount }
public fun required_stake<T>(bounty: &Bounty<T>): u64 { bounty.required_stake }
public fun active_claims<T>(bounty: &Bounty<T>): u64 { bounty.active_claims }
public fun completed_claims<T>(bounty: &Bounty<T>): u64 { bounty.completed_claims }
public fun max_claims<T>(bounty: &Bounty<T>): u64 { bounty.max_claims }
public fun deadline<T>(bounty: &Bounty<T>): u64 { bounty.deadline }
public fun grace_period<T>(bounty: &Bounty<T>): u64 { bounty.grace_period }
public fun escrow_value<T>(bounty: &Bounty<T>): u64 { balance::value(&bounty.escrow) }
public fun stake_pool_value<T>(bounty: &Bounty<T>): u64 { balance::value(&bounty.stake_pool) }
public fun ticket_bounty_id(ticket: &ClaimTicket): ID { ticket.bounty_id }
public fun ticket_hunter(ticket: &ClaimTicket): address { ticket.hunter }
public fun ticket_stake_amount(ticket: &ClaimTicket): u64 { ticket.stake_amount }

// === Helpers ===

fun checked_mul(a: u64, b: u64): u64 {
    let result = (a as u128) * (b as u128);
    assert!(result <= (18_446_744_073_709_551_615u128), constants::e_overflow());
    result as u64
}

fun is_terminal(status: u8): bool {
    status == constants::status_completed() ||
    status == constants::status_cancelled() ||
    status == constants::status_expired()
}

// === Create ===

public fun create_bounty<T>(
    title: String,
    description: String,
    mut coin: Coin<T>,
    reward_amount: u64,
    required_stake: u64,
    max_claims: u64,
    deadline: u64,
    grace_period: u64,
    cleanup_reward_bps: u16,
    verifier_addr: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    let now = sui::clock::timestamp_ms(clock);
    let sender = ctx.sender();

    // --- Validations ---
    assert!(title.length() > 0, constants::e_title_empty());
    assert!(title.length() <= constants::max_title_length(), constants::e_title_too_long());
    assert!(description.length() <= constants::max_description_length(), constants::e_description_too_long());
    assert!(reward_amount > 0, constants::e_reward_amount_zero());
    assert!(max_claims > 0, constants::e_max_claims_zero());
    assert!(max_claims <= constants::max_claims(), constants::e_max_claims_too_high());
    assert!(cleanup_reward_bps <= constants::max_cleanup_reward_bps(), constants::e_cleanup_bps_too_high());
    assert!(deadline >= now + constants::min_deadline_duration(), constants::e_deadline_too_soon());
    assert!(deadline <= now + constants::max_deadline_duration(), constants::e_deadline_too_far());

    let total_escrow = checked_mul(reward_amount, max_claims);
    assert!(coin::value(&coin) >= total_escrow, constants::e_insufficient_escrow());

    // --- Lock funds ---
    let mut escrow_bal = balance::zero<T>();
    let change = escrow::lock(&mut escrow_bal, coin, total_escrow, ctx);

    // --- Build Bounty ---
    let bounty = Bounty<T> {
        id: object::new(ctx),
        version: constants::current_version(),
        creator: sender,
        title,
        description,
        escrow: escrow_bal,
        stake_pool: balance::zero(),
        reward_amount,
        required_stake,
        cleanup_reward_bps,
        deadline,
        grace_period,
        status: constants::status_open(),
        max_claims,
        active_claims: 0,
        completed_claims: 0,
        claimed_hunters: vec_set::empty(),
        active_hunter_stakes: vec_map::empty(),
        approved_hunters: vec_set::empty(),
        metadata: vec_map::empty(),
    };

    let bounty_id = object::id(&bounty);

    // --- Mint VerifierCap ---
    verifier::issue_cap(bounty_id, verifier_addr, ctx);

    // --- Emit event ---
    event::emit(BountyCreated {
        bounty_id,
        creator: sender,
        coin_type: std::type_name::into_string(std::type_name::get<T>()),
        reward_amount,
        required_stake,
        max_claims,
        deadline,
        grace_period,
        verifier: verifier_addr,
    });

    // --- Share bounty ---
    transfer::share_object(bounty);

    change
}

public entry fun create<T>(
    title: String,
    description: String,
    coin: Coin<T>,
    reward_amount: u64,
    required_stake: u64,
    max_claims: u64,
    deadline: u64,
    grace_period: u64,
    cleanup_reward_bps: u16,
    verifier_addr: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let change = create_bounty(
        title, description, coin,
        reward_amount, required_stake, max_claims,
        deadline, grace_period, cleanup_reward_bps,
        verifier_addr, clock, ctx,
    );
    let sender = ctx.sender();
    if (coin::value(&change) > 0) {
        transfer::public_transfer(change, sender);
    } else {
        coin::destroy_zero(change);
    };
}
