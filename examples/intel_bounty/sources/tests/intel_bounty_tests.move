#[test_only]
module intel_bounty::intel_bounty_tests;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;
use intel_bounty::intel_bounty;

const CORPORATION: address = @0xA;
const VERIFIER: address = @0xB;
const EXPLORER: address = @0xC;
const CLEANUP_BOT: address = @0xD;

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000; // +1 day

#[test]
fun test_intel_happy_path() {
    let mut scenario = ts::begin(CORPORATION);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // 1. Corporation creates intel bounty (reward=500, max_reporters=2)
    ts::next_tx(&mut scenario, CORPORATION);
    let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    let change = intel_bounty::create_intel_bounty(
        b"Intel: Scan Sector J-7".to_string(),
        b"Submit terrain data".to_string(),
        payment,
        500,           // reward per report
        2,             // max reporters
        DEADLINE,
        VERIFIER,
        &clock,
        ts::ctx(&mut scenario),
    );
    // change should be 0 (1000 payment = 500 * 2 reporters)
    coin::destroy_zero(change);

    // 2. Explorer accepts (zero stake) — ticket transferred automatically
    ts::next_tx(&mut scenario, EXPLORER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let zero_coin = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
    intel_bounty::accept_intel_bounty(
        &mut bounty, zero_coin, &clock, ts::ctx(&mut scenario),
    );

    // Verify state
    assert!(intel_bounty::intel_bounty_status(&bounty) == constants::status_open());
    assert!(intel_bounty::intel_bounty_reward(&bounty) == 500);
    ts::return_shared(bounty);

    // 3. Verifier approves explorer
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    intel_bounty::verify_intel(&mut bounty, EXPLORER, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // 4. Explorer claims reward
    ts::next_tx(&mut scenario, EXPLORER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    intel_bounty::collect_intel_reward(&mut bounty, ticket, ts::ctx(&mut scenario));

    // Verify: escrow should have 500 left (one reporter slot remaining)
    assert!(bounty::escrow_value(&bounty) == 500);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_intel_expire() {
    let mut scenario = ts::begin(CORPORATION);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // Corporation creates bounty
    ts::next_tx(&mut scenario, CORPORATION);
    let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    let change = intel_bounty::create_intel_bounty(
        b"Intel: Scan Sector K-2".to_string(),
        b"Submit threat data".to_string(),
        payment,
        1000,
        1,
        DEADLINE,
        VERIFIER,
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // Fast-forward past deadline + grace period
    clock::set_for_testing(&mut clock, DEADLINE + 86_400_000 + 1);

    // Cleanup bot expires the bounty
    ts::next_tx(&mut scenario, CLEANUP_BOT);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cleanup_reward = intel_bounty::expire_intel_bounty(
        &mut bounty, &clock, ts::ctx(&mut scenario),
    );

    // Verify expired state
    assert!(intel_bounty::intel_bounty_status(&bounty) == constants::status_expired());
    // Cleanup reward = 1000 * 100 / 10000 = 10
    assert!(coin::value(&cleanup_reward) == 10);

    transfer::public_transfer(cleanup_reward, CLEANUP_BOT);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
