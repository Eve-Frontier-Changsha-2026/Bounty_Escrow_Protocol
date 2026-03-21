module bounty_escrow::bounty;

use std::string::String;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::clock::Clock;
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

/// Original v1 signature — returns only change coin (ABI-compatible).
public fun create_bounty<T>(
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
): Coin<T> {
    let (change, _id) = create_bounty_internal(
        title, description, coin,
        reward_amount, required_stake, max_claims,
        deadline, grace_period, cleanup_reward_bps,
        verifier_addr, clock, ctx,
    );
    change
}

/// Composable version — returns (Coin<T>, ID) for PTB integration.
public fun create_bounty_with_id<T>(
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
): (Coin<T>, ID) {
    create_bounty_internal(
        title, description, coin,
        reward_amount, required_stake, max_claims,
        deadline, grace_period, cleanup_reward_bps,
        verifier_addr, clock, ctx,
    )
}

fun create_bounty_internal<T>(
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
): (Coin<T>, ID) {
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
    assert!(grace_period >= constants::min_grace_period(), constants::e_grace_period_too_short());

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
        coin_type: std::type_name::into_string(std::type_name::with_defining_ids<T>()),
        reward_amount,
        required_stake,
        max_claims,
        deadline,
        grace_period,
        verifier: verifier_addr,
    });

    // --- Share bounty ---
    transfer::share_object(bounty);

    (change, bounty_id)
}

public fun create<T>(
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

// === Claim ===

public fun claim_bounty<T>(
    bounty: &mut Bounty<T>,
    stake_coin: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<T>) {
    let now = sui::clock::timestamp_ms(clock);
    let hunter = ctx.sender();

    assert!(bounty.status == constants::status_open(), constants::e_bounty_not_open());
    assert!(bounty.active_claims < bounty.max_claims, constants::e_max_claims_reached());
    assert!(now < bounty.deadline, constants::e_deadline_passed());
    assert!(hunter != bounty.creator, constants::e_creator_cannot_claim());
    assert!(!vec_set::contains(&bounty.claimed_hunters, &hunter), constants::e_already_claimed());
    assert!(coin::value(&stake_coin) >= bounty.required_stake, constants::e_insufficient_stake());

    // Lock stake
    let change = if (bounty.required_stake > 0) {
        escrow::lock(&mut bounty.stake_pool, stake_coin, bounty.required_stake, ctx)
    } else {
        stake_coin
    };

    // Update state
    vec_set::insert(&mut bounty.claimed_hunters, hunter);
    vec_map::insert(&mut bounty.active_hunter_stakes, hunter, bounty.required_stake);
    bounty.active_claims = bounty.active_claims + 1;

    if (bounty.active_claims == bounty.max_claims) {
        bounty.status = constants::status_claimed();
    };

    let ticket = ClaimTicket {
        id: object::new(ctx),
        bounty_id: object::id(bounty),
        hunter,
        stake_amount: bounty.required_stake,
        claimed_at: now,
    };

    event::emit(BountyClaimed {
        bounty_id: object::id(bounty),
        ticket_id: object::id(&ticket),
        hunter,
        stake_amount: bounty.required_stake,
    });

    (ticket, change)
}

public fun claim<T>(
    bounty: &mut Bounty<T>,
    stake_coin: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (ticket, change) = claim_bounty(bounty, stake_coin, clock, ctx);
    let sender = ctx.sender();
    transfer::transfer(ticket, sender);
    if (coin::value(&change) > 0) {
        transfer::public_transfer(change, sender);
    } else {
        coin::destroy_zero(change);
    };
}

// === Internal: resolve claim ===

fun resolve_claim<T>(bounty: &mut Bounty<T>, hunter: address, is_completion: bool) {
    let (_, _stake) = vec_map::remove(&mut bounty.active_hunter_stakes, &hunter);
    bounty.active_claims = bounty.active_claims - 1;

    if (is_completion) {
        bounty.completed_claims = bounty.completed_claims + 1;
        vec_set::remove(&mut bounty.approved_hunters, &hunter);
    };

    if (bounty.active_claims == 0 && bounty.completed_claims > 0 &&
        vec_set::length(&bounty.approved_hunters) == 0) {
        bounty.status = constants::status_completed();
    } else if (bounty.active_claims < bounty.max_claims &&
               bounty.status == constants::status_claimed()) {
        bounty.status = constants::status_open();
    };
}

// === Approve ===

public fun approve_hunter<T>(
    bounty: &mut Bounty<T>,
    hunter: address,
    cap: &VerifierCap,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    let now = sui::clock::timestamp_ms(clock);
    let bounty_id = object::id(bounty);

    assert!(bounty.status == constants::status_open() || bounty.status == constants::status_claimed(),
        constants::e_bounty_not_active());
    verifier::validate_cap(cap, bounty_id);
    assert!(vec_map::contains(&bounty.active_hunter_stakes, &hunter), constants::e_hunter_not_active());
    assert!(!vec_set::contains(&bounty.approved_hunters, &hunter), constants::e_already_approved());
    assert!(now <= bounty.deadline + bounty.grace_period, constants::e_grace_period_not_passed());

    vec_set::insert(&mut bounty.approved_hunters, hunter);

    event::emit(BountyApproved {
        bounty_id,
        hunter,
        verifier: _ctx.sender(),
    });
}

public fun approve<T>(
    bounty: &mut Bounty<T>,
    hunter: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    approve_hunter(bounty, hunter, cap, clock, ctx);
}

// === Claim Reward ===

public fun claim_reward_bounty<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    let hunter = ctx.sender();
    let bounty_id = object::id(bounty);

    assert!(ticket.bounty_id == bounty_id, constants::e_ticket_bounty_mismatch());
    assert!(ticket.hunter == hunter, constants::e_not_ticket_owner());
    assert!(vec_set::contains(&bounty.approved_hunters, &hunter), constants::e_hunter_not_approved());
    assert!(balance::value(&bounty.escrow) >= bounty.reward_amount, constants::e_insufficient_escrow_for_reward());

    let stake_amount = ticket.stake_amount;
    let reward = bounty.reward_amount;

    escrow::release_to(&mut bounty.escrow, reward, hunter, ctx);
    if (stake_amount > 0) {
        escrow::release_to(&mut bounty.stake_pool, stake_amount, hunter, ctx);
    };

    resolve_claim(bounty, hunter, true);

    event::emit(RewardClaimed {
        bounty_id,
        ticket_id: object::id(&ticket),
        hunter,
        reward_amount: reward,
        stake_returned: stake_amount,
    });

    let ClaimTicket { id, bounty_id: _, hunter: _, stake_amount: _, claimed_at: _ } = ticket;
    object::delete(id);
}

public fun claim_reward<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    claim_reward_bounty(bounty, ticket, ctx);
}

// === Abandon ===

public fun abandon_bounty<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let now = sui::clock::timestamp_ms(clock);
    let hunter = ctx.sender();
    let bounty_id = object::id(bounty);

    assert!(ticket.bounty_id == bounty_id, constants::e_ticket_bounty_mismatch());
    assert!(ticket.hunter == hunter, constants::e_not_ticket_owner());
    assert!(bounty.status == constants::status_open() || bounty.status == constants::status_claimed(),
        constants::e_bounty_not_active());
    assert!(now < bounty.deadline, constants::e_abandon_after_deadline());

    let stake_amount = ticket.stake_amount;

    if (stake_amount > 0) {
        escrow::release_to(&mut bounty.stake_pool, stake_amount, bounty.creator, ctx);
    };

    if (vec_set::contains(&bounty.approved_hunters, &hunter)) {
        vec_set::remove(&mut bounty.approved_hunters, &hunter);
    };

    resolve_claim(bounty, hunter, false);

    event::emit(BountyAbandoned {
        bounty_id,
        ticket_id: object::id(&ticket),
        hunter,
        forfeited_stake: stake_amount,
    });

    let ClaimTicket { id, bounty_id: _, hunter: _, stake_amount: _, claimed_at: _ } = ticket;
    object::delete(id);
}

public fun abandon<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    abandon_bounty(bounty, ticket, clock, ctx);
}

// === Cancel ===

public fun cancel_bounty<T>(
    bounty: &mut Bounty<T>,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(sender == bounty.creator, constants::e_not_creator());
    assert!(bounty.status == constants::status_open() || bounty.status == constants::status_claimed(),
        constants::e_bounty_not_cancellable());

    if (bounty.active_claims == 0) {
        escrow::release_all(&mut bounty.escrow, bounty.creator, ctx);
        bounty.status = constants::status_cancelled();
        event::emit(BountyCancelled {
            bounty_id: object::id(bounty),
            creator: sender,
            active_claims_at_cancel: 0,
            penalty_per_hunter: 0,
        });
    } else {
        let approved_count = vec_set::length(&bounty.approved_hunters);
        let unapproved_count = bounty.active_claims - approved_count;
        let approved_penalty = checked_mul(bounty.reward_amount, approved_count);
        let unapproved_penalty = checked_mul(bounty.required_stake, unapproved_count);
        let total_penalty = approved_penalty + unapproved_penalty;
        assert!(balance::value(&bounty.escrow) >= total_penalty,
            constants::e_insufficient_escrow_for_penalty());
        bounty.status = constants::status_cancelled();
        event::emit(BountyCancelled {
            bounty_id: object::id(bounty),
            creator: sender,
            active_claims_at_cancel: bounty.active_claims,
            penalty_per_hunter: bounty.required_stake,
        });
    };
}

public fun cancel<T>(
    bounty: &mut Bounty<T>,
    ctx: &mut TxContext,
) {
    cancel_bounty(bounty, ctx);
}

// === Withdraw Penalty ===

public fun withdraw_penalty_bounty<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    let hunter = ctx.sender();
    let bounty_id = object::id(bounty);

    assert!(bounty.status == constants::status_cancelled(), constants::e_bounty_not_cancelled());
    assert!(ticket.bounty_id == bounty_id, constants::e_ticket_bounty_mismatch());
    assert!(ticket.hunter == hunter, constants::e_not_ticket_owner());
    assert!(vec_map::contains(&bounty.active_hunter_stakes, &hunter), constants::e_hunter_not_active());

    let stake_amount = ticket.stake_amount;
    let is_approved = vec_set::contains(&bounty.approved_hunters, &hunter);
    let penalty = if (is_approved) { bounty.reward_amount } else { bounty.required_stake };

    if (stake_amount > 0) {
        escrow::release_to(&mut bounty.stake_pool, stake_amount, hunter, ctx);
    };
    if (penalty > 0) {
        escrow::release_to(&mut bounty.escrow, penalty, hunter, ctx);
    };

    let (_, _) = vec_map::remove(&mut bounty.active_hunter_stakes, &hunter);
    bounty.active_claims = bounty.active_claims - 1;

    if (is_approved) {
        vec_set::remove(&mut bounty.approved_hunters, &hunter);
    };

    event::emit(PenaltyWithdrawn {
        bounty_id,
        hunter,
        stake_returned: stake_amount,
        penalty_received: penalty,
    });

    let ClaimTicket { id, bounty_id: _, hunter: _, stake_amount: _, claimed_at: _ } = ticket;
    object::delete(id);
}

public fun withdraw_penalty<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    withdraw_penalty_bounty(bounty, ticket, ctx);
}

// === Withdraw Remaining ===

public fun withdraw_remaining_bounty<T>(
    bounty: &mut Bounty<T>,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    assert!(sender == bounty.creator, constants::e_not_creator());
    assert!(bounty.status == constants::status_cancelled(), constants::e_bounty_not_cancelled());
    assert!(bounty.active_claims == 0, constants::e_hunters_not_withdrawn());
    assert!(vec_map::is_empty(&bounty.active_hunter_stakes), constants::e_hunters_not_withdrawn());

    let escrow_left = balance::value(&bounty.escrow);
    let stakes_left = balance::value(&bounty.stake_pool);

    escrow::release_all(&mut bounty.escrow, bounty.creator, ctx);
    escrow::release_all(&mut bounty.stake_pool, bounty.creator, ctx);

    event::emit(RemainingWithdrawn {
        bounty_id: object::id(bounty),
        creator: sender,
        escrow_returned: escrow_left,
        stakes_returned: stakes_left,
    });
}

public fun withdraw_remaining<T>(
    bounty: &mut Bounty<T>,
    ctx: &mut TxContext,
) {
    withdraw_remaining_bounty(bounty, ctx);
}

// === Expire ===

public fun expire_bounty<T>(
    bounty: &mut Bounty<T>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    let now = sui::clock::timestamp_ms(clock);
    let caller = ctx.sender();

    assert!(bounty.status == constants::status_open() || bounty.status == constants::status_claimed(),
        constants::e_bounty_not_active());
    assert!(now > bounty.deadline + bounty.grace_period,
        constants::e_grace_period_not_passed());

    let escrow_remaining = balance::value(&bounty.escrow);
    let cleanup_reward = escrow::calculate_cleanup_reward(escrow_remaining, bounty.cleanup_reward_bps);

    // Take cleanup reward as coin to return
    let cleanup_coin = if (cleanup_reward > 0) {
        coin::take(&mut bounty.escrow, cleanup_reward, ctx)
    } else {
        coin::zero<T>(ctx)
    };

    let forfeited = balance::value(&bounty.stake_pool);
    escrow::release_all(&mut bounty.stake_pool, bounty.creator, ctx);

    let refund = balance::value(&bounty.escrow);
    escrow::release_all(&mut bounty.escrow, bounty.creator, ctx);

    bounty.status = constants::status_expired();

    while (vec_map::length(&bounty.active_hunter_stakes) > 0) {
        let (_, _) = vec_map::pop(&mut bounty.active_hunter_stakes);
    };
    bounty.active_claims = 0;

    event::emit(BountyExpired {
        bounty_id: object::id(bounty),
        caller,
        cleanup_reward,
        refund_to_creator: refund,
        forfeited_stakes: forfeited,
    });

    cleanup_coin
}

public fun expire<T>(
    bounty: &mut Bounty<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let cleanup_coin = expire_bounty(bounty, clock, ctx);
    let caller = ctx.sender();
    if (coin::value(&cleanup_coin) > 0) {
        transfer::public_transfer(cleanup_coin, caller);
    } else {
        coin::destroy_zero(cleanup_coin);
    };
}

// === Cleanup: Destroy Ticket ===

public fun destroy_ticket_bounty<T>(
    ticket: ClaimTicket,
    bounty: &Bounty<T>,
) {
    assert!(is_terminal(bounty.status), constants::e_bounty_not_terminal());
    assert!(ticket.bounty_id == object::id(bounty), constants::e_ticket_bounty_mismatch());

    let ticket_id = object::id(&ticket);
    let bounty_id = ticket.bounty_id;

    let ClaimTicket { id, bounty_id: _, hunter: _, stake_amount: _, claimed_at: _ } = ticket;
    object::delete(id);

    event::emit(TicketDestroyed { bounty_id, ticket_id });
}

public fun destroy_ticket<T>(
    ticket: ClaimTicket,
    bounty: &Bounty<T>,
) {
    destroy_ticket_bounty(ticket, bounty);
}

// === Cleanup: Destroy VerifierCap ===

public fun destroy_verifier_cap_bounty<T>(
    cap: VerifierCap,
    bounty: &Bounty<T>,
) {
    assert!(is_terminal(bounty.status), constants::e_bounty_not_terminal());
    let bounty_id = verifier::bounty_id(&cap);
    assert!(bounty_id == object::id(bounty), constants::e_ticket_bounty_mismatch());

    let cap_id = verifier::cap_id(&cap);
    verifier::destroy_cap(cap);

    event::emit(VerifierCapDestroyed { bounty_id, cap_id });
}

public fun destroy_verifier_cap<T>(
    cap: VerifierCap,
    bounty: &Bounty<T>,
) {
    destroy_verifier_cap_bounty(cap, bounty);
}
