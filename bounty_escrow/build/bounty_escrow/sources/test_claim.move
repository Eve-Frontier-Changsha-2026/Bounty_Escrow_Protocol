#[test_only]
module bounty_escrow::test_claim;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER1: address = @0xC;
const HUNTER2: address = @0xD;

// Base clock time
const BASE_TIME: u64 = 1_000_000_000;
// Deadline = BASE_TIME + 1 day
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
// Grace period = 1 day
const GRACE: u64 = 86_400_000;

fun setup_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock, max_claims: u64): Bounty<SUI> {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Kill pirate".to_string(),
        b"Destroy pirate ship".to_string(),
        coin, 1000, 100, max_claims,
        DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
    ts::next_tx(scenario, CREATOR);
    ts::take_shared<Bounty<SUI>>(scenario)
}

#[test]
fun test_claim_success() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 5);

    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER1);
    // active_claims = 1, status = Open (max_claims=5)
    assert!(bounty::active_claims(&bounty) == 1);
    assert!(bounty::status(&bounty) == constants::status_open());
    // stake_pool should have 100
    assert!(bounty::stake_pool_value(&bounty) == 100);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_claim_triggers_claimed_status() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 1);

    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER1);
    // max_claims=1, so after 1 claim status becomes Claimed
    assert!(bounty::status(&bounty) == constants::status_claimed());
    assert!(bounty::active_claims(&bounty) == 1);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 12)]
fun test_claim_duplicate() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 5);

    ts::next_tx(&mut scenario, HUNTER1);
    let stake1 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake1, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER1);
    let stake2 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    // Second claim by same hunter -> e_already_claimed (12)
    bounty::claim<SUI>(&mut bounty, stake2, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 11)]
fun test_creator_cannot_claim_own() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 5);

    ts::next_tx(&mut scenario, CREATOR);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    // Creator tries to claim -> e_creator_cannot_claim (11)
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 10)]
fun test_claim_deadline_passed() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 5);

    // Advance past deadline
    clock::set_for_testing(&mut clock, DEADLINE + 1);

    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    // Deadline passed -> e_deadline_passed (10)
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 7)]
fun test_claim_max_claims_reached() {
    // create(max=1) -> HUNTER1 claims (status->Claimed) -> HUNTER2 tries to claim
    // Since status is now Claimed(1) not Open(0), aborts with e_bounty_not_open (7)
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 1);

    ts::next_tx(&mut scenario, HUNTER1);
    let stake1 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake1, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER2);
    let stake2 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    // Status is now Claimed, not Open -> e_bounty_not_open (7)
    bounty::claim<SUI>(&mut bounty, stake2, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 9)]
fun test_claim_insufficient_stake() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 5);

    ts::next_tx(&mut scenario, HUNTER1);
    // required_stake=100, provide only 50
    let stake = coin::mint_for_testing<SUI>(50, ts::ctx(&mut scenario));
    // e_insufficient_stake (9)
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
