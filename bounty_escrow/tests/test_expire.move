#[test_only]
module bounty_escrow::test_expire;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER1: address = @0xC;
// Anyone can trigger expire, use a neutral caller
const CALLER: address = @0xE;

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

fun setup_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock): Bounty<SUI> {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Kill pirate".to_string(),
        b"Destroy pirate ship".to_string(),
        coin, 1000, 100, 1,
        DEADLINE, GRACE, 100,   // cleanup_reward_bps = 100 = 1%
        VERIFIER, clock, ts::ctx(scenario),
    );
    ts::next_tx(scenario, CREATOR);
    ts::take_shared<Bounty<SUI>>(scenario)
}

#[test]
fun test_expire_no_claims() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock);

    // Advance past deadline + grace
    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    ts::next_tx(&mut scenario, CALLER);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, CALLER);
    assert!(bounty::status(&bounty) == constants::status_expired());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    assert!(bounty::active_claims(&bounty) == 0);

    // CALLER should have received cleanup_reward coin (1% of 1000 = 10)
    let cleanup = ts::take_from_sender<coin::Coin<SUI>>(&scenario);
    assert!(coin::value(&cleanup) == 10);
    ts::return_to_sender(&scenario, cleanup);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_expire_with_claims_stakes_forfeited() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock);

    // HUNTER1 claims
    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    assert!(bounty::stake_pool_value(&bounty) == 100);

    // Advance past deadline + grace
    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    ts::next_tx(&mut scenario, CALLER);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, CALLER);
    assert!(bounty::status(&bounty) == constants::status_expired());
    // All balances drained
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    assert!(bounty::active_claims(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 20)]
fun test_expire_within_grace_period_fails() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock);

    // Advance to past deadline but within grace (deadline + grace/2)
    clock::set_for_testing(&mut clock, DEADLINE + GRACE / 2);

    ts::next_tx(&mut scenario, CALLER);
    // e_grace_period_not_passed (20)
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_expire_after_grace_succeeds() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock);

    // Advance to exactly deadline + grace + 1
    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    ts::next_tx(&mut scenario, CALLER);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, CALLER);
    assert!(bounty::status(&bounty) == constants::status_expired());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 21)]
fun test_double_expire_fails() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock);

    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    ts::next_tx(&mut scenario, CALLER);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, CALLER);
    // Second expire -> e_bounty_not_active (21)
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
