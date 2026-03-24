#[test_only]
module bounty_escrow::test_integration;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER1: address = @0xC;
const HUNTER2: address = @0xD;
const HUNTER3: address = @0xE;
const CLEANUP_CALLER: address = @0xF;

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

// ─── helpers ─────────────────────────────────────────────────────────────────

fun make_bounty(
    scenario: &mut ts::Scenario,
    clock: &clock::Clock,
    reward: u64,
    stake: u64,
    max_claims: u64,
): Bounty<SUI> {
    ts::next_tx(scenario, CREATOR);
    let total = reward * max_claims;
    let coin = coin::mint_for_testing<SUI>(total, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Kill pirate".to_string(),
        b"Destroy pirate ship".to_string(),
        coin, reward, stake, max_claims,
        DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
    ts::next_tx(scenario, CREATOR);
    ts::take_shared<Bounty<SUI>>(scenario)
}

fun do_claim(
    scenario: &mut ts::Scenario,
    bounty: &mut Bounty<SUI>,
    clock: &clock::Clock,
    hunter: address,
    stake: u64,
) {
    ts::next_tx(scenario, hunter);
    let stake_coin = coin::mint_for_testing<SUI>(stake, ts::ctx(scenario));
    bounty::claim<SUI>(bounty, stake_coin, clock, ts::ctx(scenario));
}

fun do_approve(
    scenario: &mut ts::Scenario,
    bounty: &mut Bounty<SUI>,
    clock: &clock::Clock,
    hunter: address,
) {
    ts::next_tx(scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(scenario);
    bounty::approve<SUI>(bounty, hunter, &cap, clock, ts::ctx(scenario));
    ts::return_to_sender(scenario, cap);
}

fun do_claim_reward(
    scenario: &mut ts::Scenario,
    bounty: &mut Bounty<SUI>,
    hunter: address,
) {
    ts::next_tx(scenario, hunter);
    let ticket = ts::take_from_sender<ClaimTicket>(scenario);
    bounty::claim_reward<SUI>(bounty, ticket, ts::ctx(scenario));
}

// ─── 1. Happy Path ────────────────────────────────────────────────────────────

#[test]
fun test_01_happy_path() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = make_bounty(&mut scenario, &clock, 1000, 100, 1);

    // Verify initial state
    assert!(bounty::status(&bounty) == constants::status_open());
    assert!(bounty::escrow_value(&bounty) == 1000);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    // HUNTER1 claims
    do_claim(&mut scenario, &mut bounty, &clock, HUNTER1, 100);
    assert!(bounty::status(&bounty) == constants::status_claimed());
    assert!(bounty::active_claims(&bounty) == 1);
    assert!(bounty::stake_pool_value(&bounty) == 100);
    assert!(bounty::escrow_value(&bounty) == 1000);

    // VERIFIER approves HUNTER1
    do_approve(&mut scenario, &mut bounty, &clock, HUNTER1);

    // HUNTER1 claims reward
    do_claim_reward(&mut scenario, &mut bounty, HUNTER1);

    // Final state
    ts::next_tx(&mut scenario, HUNTER1);
    assert!(bounty::status(&bounty) == constants::status_completed());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    assert!(bounty::completed_claims(&bounty) == 1);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── 2. Creator Breach (Withdrawal Pattern) ──────────────────────────────────

#[test]
fun test_02_creator_breach_withdrawal_pattern() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // reward=1000, stake=100, max=2  → escrow=2000
    let mut bounty = make_bounty(&mut scenario, &clock, 1000, 100, 2);
    assert!(bounty::escrow_value(&bounty) == 2000);

    // 2x claim
    do_claim(&mut scenario, &mut bounty, &clock, HUNTER1, 100);
    assert!(bounty::stake_pool_value(&bounty) == 100);

    do_claim(&mut scenario, &mut bounty, &clock, HUNTER2, 100);
    assert!(bounty::status(&bounty) == constants::status_claimed());
    assert!(bounty::active_claims(&bounty) == 2);
    assert!(bounty::stake_pool_value(&bounty) == 200);

    // Creator cancels
    ts::next_tx(&mut scenario, CREATOR);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));
    assert!(bounty::status(&bounty) == constants::status_cancelled());
    // escrow untouched (penalty mode: 2 active × 100 = 200 ≤ 2000)
    assert!(bounty::escrow_value(&bounty) == 2000);

    // HUNTER1 withdraws penalty: gets back stake=100 + penalty=100 from escrow
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket1 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::withdraw_penalty<SUI>(&mut bounty, ticket1, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 1900);
    assert!(bounty::stake_pool_value(&bounty) == 100);
    assert!(bounty::active_claims(&bounty) == 1);

    // HUNTER2 withdraws penalty: gets back stake=100 + penalty=100 from escrow
    ts::next_tx(&mut scenario, HUNTER2);
    let ticket2 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::withdraw_penalty<SUI>(&mut bounty, ticket2, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 1800);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    assert!(bounty::active_claims(&bounty) == 0);

    // Creator withdraws remaining escrow (1800)
    ts::next_tx(&mut scenario, CREATOR);
    bounty::withdraw_remaining<SUI>(&mut bounty, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── 3. Hunter Dereliction (Expire) ──────────────────────────────────────────

#[test]
fun test_03_hunter_dereliction_expire() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // cleanup_reward_bps=100 (1%)
    let mut bounty = make_bounty(&mut scenario, &clock, 1000, 100, 1);

    do_claim(&mut scenario, &mut bounty, &clock, HUNTER1, 100);
    assert!(bounty::status(&bounty) == constants::status_claimed());
    assert!(bounty::escrow_value(&bounty) == 1000);
    assert!(bounty::stake_pool_value(&bounty) == 100);

    // Advance past deadline + grace
    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    // CLEANUP_CALLER triggers expire
    ts::next_tx(&mut scenario, CLEANUP_CALLER);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, CLEANUP_CALLER);
    assert!(bounty::status(&bounty) == constants::status_expired());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    assert!(bounty::active_claims(&bounty) == 0);

    // CLEANUP_CALLER should have received cleanup coin (1% of 1000 = 10)
    let cleanup_coin = ts::take_from_sender<coin::Coin<SUI>>(&scenario);
    assert!(coin::value(&cleanup_coin) == 10);
    ts::return_to_sender(&scenario, cleanup_coin);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── 4. Multi-hunter Partial Completion ──────────────────────────────────────

#[test]
fun test_04_multi_hunter_partial_completion() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // max=3, reward=1000, stake=100 → escrow=3000
    let mut bounty = make_bounty(&mut scenario, &clock, 1000, 100, 3);
    assert!(bounty::escrow_value(&bounty) == 3000);

    // 3x claim
    do_claim(&mut scenario, &mut bounty, &clock, HUNTER1, 100);
    do_claim(&mut scenario, &mut bounty, &clock, HUNTER2, 100);
    do_claim(&mut scenario, &mut bounty, &clock, HUNTER3, 100);
    assert!(bounty::status(&bounty) == constants::status_claimed());
    assert!(bounty::active_claims(&bounty) == 3);
    assert!(bounty::stake_pool_value(&bounty) == 300);

    // Approve + claim_reward for HUNTER1
    do_approve(&mut scenario, &mut bounty, &clock, HUNTER1);
    do_claim_reward(&mut scenario, &mut bounty, HUNTER1);
    // escrow: 3000-1000=2000, stake_pool: 300-100=200, active=2
    assert!(bounty::escrow_value(&bounty) == 2000);
    assert!(bounty::stake_pool_value(&bounty) == 200);
    assert!(bounty::active_claims(&bounty) == 2);
    assert!(bounty::completed_claims(&bounty) == 1);
    // status back to Open since active_claims < max_claims after completion
    assert!(bounty::status(&bounty) == constants::status_open());

    // HUNTER2 abandons (before deadline)
    ts::next_tx(&mut scenario, HUNTER2);
    let ticket2 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty, ticket2, &clock, ts::ctx(&mut scenario));
    // HUNTER2's stake forfeited to creator; stake_pool: 200-100=100, active=1
    assert!(bounty::stake_pool_value(&bounty) == 100);
    assert!(bounty::active_claims(&bounty) == 1);

    // Advance past deadline + grace
    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    // CLEANUP_CALLER expires the bounty → HUNTER3's stake forfeited
    ts::next_tx(&mut scenario, CLEANUP_CALLER);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, CLEANUP_CALLER);
    assert!(bounty::status(&bounty) == constants::status_expired());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    assert!(bounty::active_claims(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── 5. Abandon + Reclaim ─────────────────────────────────────────────────────

#[test]
fun test_05_abandon_and_reclaim() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = make_bounty(&mut scenario, &clock, 1000, 100, 1);
    assert!(bounty::escrow_value(&bounty) == 1000);

    // HUNTER1 claims
    do_claim(&mut scenario, &mut bounty, &clock, HUNTER1, 100);
    assert!(bounty::status(&bounty) == constants::status_claimed());
    assert!(bounty::active_claims(&bounty) == 1);

    // HUNTER1 abandons → stake forfeited to creator, bounty reopened
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket1 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty, ticket1, &clock, ts::ctx(&mut scenario));
    assert!(bounty::status(&bounty) == constants::status_open());
    assert!(bounty::active_claims(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    // HUNTER2 claims
    do_claim(&mut scenario, &mut bounty, &clock, HUNTER2, 100);
    assert!(bounty::status(&bounty) == constants::status_claimed());
    assert!(bounty::stake_pool_value(&bounty) == 100);

    // Approve + claim_reward for HUNTER2
    do_approve(&mut scenario, &mut bounty, &clock, HUNTER2);
    do_claim_reward(&mut scenario, &mut bounty, HUNTER2);

    ts::next_tx(&mut scenario, HUNTER2);
    assert!(bounty::status(&bounty) == constants::status_completed());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── 6. Grace Period Verification ────────────────────────────────────────────

#[test]
fun test_06_grace_period_verification() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = make_bounty(&mut scenario, &clock, 1000, 100, 1);

    do_claim(&mut scenario, &mut bounty, &clock, HUNTER1, 100);

    // Advance past deadline but within grace period
    clock::set_for_testing(&mut clock, DEADLINE + GRACE / 2);

    // Approve still works in grace period
    do_approve(&mut scenario, &mut bounty, &clock, HUNTER1);
    // status remains Claimed (not expired)
    assert!(bounty::status(&bounty) == constants::status_claimed());

    // HUNTER1 claims reward
    do_claim_reward(&mut scenario, &mut bounty, HUNTER1);

    ts::next_tx(&mut scenario, HUNTER1);
    assert!(bounty::status(&bounty) == constants::status_completed());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── 7. Orphan Cleanup ───────────────────────────────────────────────────────

#[test]
fun test_07_orphan_cleanup() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = make_bounty(&mut scenario, &clock, 1000, 100, 1);

    do_claim(&mut scenario, &mut bounty, &clock, HUNTER1, 100);

    // Advance past deadline + grace
    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    // CLEANUP_CALLER expires
    ts::next_tx(&mut scenario, CLEANUP_CALLER);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    assert!(bounty::status(&bounty) == constants::status_expired());

    // HUNTER1 destroys orphan ticket (bounty is terminal)
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::destroy_ticket<SUI>(ticket, &bounty);

    // VERIFIER destroys orphan VerifierCap
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::destroy_verifier_cap<SUI>(cap, &bounty);

    // Bounty still exists as shared object; pools empty
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    assert!(bounty::status(&bounty) == constants::status_expired());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── 8. Cancel Escrow Insufficient (should abort) ────────────────────────────

#[test]
#[expected_failure(abort_code = 15)]
fun test_08_cancel_insufficient_escrow_for_penalty() {
    // reward=1000, stake=2000, max=2 → escrow=2000
    // HUNTER1 claims, HUNTER2 claims → status=Claimed, escrow=2000, stake_pool=4000
    // Approve+claim_reward HUNTER1 → escrow=1000, active=1
    // Cancel: penalty=2000 for 1 hunter but escrow=1000 → abort 15
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = make_bounty(&mut scenario, &clock, 1000, 2000, 2);
    assert!(bounty::escrow_value(&bounty) == 2000);

    // HUNTER1 claims
    do_claim(&mut scenario, &mut bounty, &clock, HUNTER1, 2000);
    assert!(bounty::stake_pool_value(&bounty) == 2000);

    // HUNTER2 claims → bounty now status_claimed
    do_claim(&mut scenario, &mut bounty, &clock, HUNTER2, 2000);
    assert!(bounty::status(&bounty) == constants::status_claimed());
    assert!(bounty::active_claims(&bounty) == 2);
    assert!(bounty::escrow_value(&bounty) == 2000);

    // Approve HUNTER1
    do_approve(&mut scenario, &mut bounty, &clock, HUNTER1);

    // HUNTER1 claims reward → escrow=2000-1000=1000, active=1
    do_claim_reward(&mut scenario, &mut bounty, HUNTER1);
    assert!(bounty::escrow_value(&bounty) == 1000);
    assert!(bounty::active_claims(&bounty) == 1);

    // Creator tries to cancel: penalty per hunter=2000, active=1 → need 2000 but escrow=1000
    ts::next_tx(&mut scenario, CREATOR);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
