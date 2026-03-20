#[test_only]
module bounty_escrow::test_approve_claim;

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

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

// Creates a bounty(reward=1000, stake=100, max=1) and has HUNTER1 claim it.
// Returns (bounty) — scenario is left at HUNTER1's tx.
fun setup_claimed_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock): Bounty<SUI> {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Kill pirate".to_string(),
        b"Destroy pirate ship".to_string(),
        coin, 1000, 100, 1,
        DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
    ts::next_tx(scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);

    ts::next_tx(scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(scenario));
    bounty::claim<SUI>(&mut bounty, stake, clock, ts::ctx(scenario));

    bounty
}

#[test]
fun test_approve_and_claim_reward() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Verifier approves HUNTER1
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);

    // HUNTER1 claims reward
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER1);
    // After single completion: status=Completed, escrow=0, stake_pool=0
    assert!(bounty::status(&bounty) == constants::status_completed());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    assert!(bounty::completed_claims(&bounty) == 1);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_approve_during_grace_period() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Advance to just past deadline but within grace period
    clock::set_for_testing(&mut clock, DEADLINE + GRACE / 2);

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    // Should succeed: now <= deadline + grace
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 20)]
fun test_approve_after_grace_period_fails() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Advance past deadline + grace
    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    // e_grace_period_not_passed (20)
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 27)]
fun test_claim_reward_without_approval() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // HUNTER1 tries to claim reward without approval -> e_hunter_not_approved (27)
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
