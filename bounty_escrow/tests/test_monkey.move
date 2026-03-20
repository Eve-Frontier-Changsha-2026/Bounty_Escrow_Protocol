#[test_only]
module bounty_escrow::test_monkey;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::escrow;
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;

#[test]
fun test_reward_amount_1_min_cleanup() {
    // reward=1, cleanup_bps=1 → cleanup_reward should be min 1 (not 0)
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(1, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Tiny".to_string(), b"desc".to_string(), coin,
        1, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 1,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::set_for_testing(&mut clock, 1_000_000_000 + 86_400_000 + 86_400_000 + 1);
    ts::next_tx(&mut scenario, @0xF);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    // Cleanup reward = 1 (min floor), creator gets 0
    assert!(bounty::escrow_value(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_zero_stake_full_lifecycle() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Free".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Claim with 0 stake
    ts::next_tx(&mut scenario, @0xC);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Approve
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, @0xC, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // Claim reward
    ts::next_tx(&mut scenario, @0xC);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::status(&bounty) == constants::status_completed());
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_cleanup_reward_u128_no_overflow() {
    let result = escrow::calculate_cleanup_reward(18_446_744_073_709_551_615, 1000);
    assert!(result > 0);
}

#[test]
fun test_cleanup_reward_zero_bps() {
    let result = escrow::calculate_cleanup_reward(1000, 0);
    assert!(result == 0);
}

#[test]
fun test_cleanup_reward_min_floor() {
    let result = escrow::calculate_cleanup_reward(99, 1);
    assert!(result == 1);
}

#[test]
fun test_shortest_deadline() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    // Deadline = now + exactly MIN_DEADLINE_DURATION (1 hour)
    bounty::create<SUI>(
        b"Rush".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 3_600_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(bounty::status(&bounty) == constants::status_open());
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_coin_change_returned() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // Need 1000, provide 5000
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(bounty::escrow_value(&bounty) == 1000);
    ts::return_shared(bounty);

    let change = ts::take_from_sender<coin::Coin<SUI>>(&scenario);
    assert!(coin::value(&change) == 4000);
    ts::return_to_sender(&scenario, change);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_cleanup_reward_bps_zero_expire() {
    // cleanup_reward_bps = 0 → caller gets nothing on expire
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"NoReward".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 0, // bps=0
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::set_for_testing(&mut clock, 1_000_000_000 + 86_400_000 + 86_400_000 + 1);
    ts::next_tx(&mut scenario, @0xF);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::status(&bounty) == constants::status_expired());
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_claim_abandon_reclaim_cycle() {
    // 3 hunters claim and abandon (max=2), then 3 new hunters claim
    // claimed_hunters should have 6 entries (> max_claims=2)
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Cycle".to_string(), b"desc".to_string(), coin,
        1000, 100, 2,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Hunter @0x10 claims
    ts::next_tx(&mut scenario, @0x10);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Hunter @0x10 abandons
    ts::next_tx(&mut scenario, @0x10);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));
    assert!(bounty::active_claims(&bounty) == 0);
    assert!(bounty::status(&bounty) == constants::status_open());
    ts::return_shared(bounty);

    // Hunter @0x11 claims
    ts::next_tx(&mut scenario, @0x11);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Hunter @0x11 abandons
    ts::next_tx(&mut scenario, @0x11);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Hunter @0x12 claims — this is the 3rd unique hunter, claimed_hunters has 3 entries
    ts::next_tx(&mut scenario, @0x12);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    assert!(bounty::active_claims(&bounty) == 1);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_approve_then_expire_without_claim_reward() {
    // Hunter approved but never calls claim_reward → expire forfeits everything
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Lazy".to_string(), b"desc".to_string(), coin,
        1000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Claim
    ts::next_tx(&mut scenario, @0xC);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Approve
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, @0xC, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // Don't claim reward — advance and expire
    clock::set_for_testing(&mut clock, 1_000_000_000 + 86_400_000 + 86_400_000 + 1);
    ts::next_tx(&mut scenario, @0xF);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    assert!(bounty::status(&bounty) == constants::status_expired());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
