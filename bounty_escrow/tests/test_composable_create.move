#[test_only]
module bounty_escrow::test_composable_create;

use std::string::utf8;
use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::task_type;
use bounty_escrow::encrypted_details;
use bounty_escrow::constants;

const CREATOR: address = @0xCA;
const VERIFIER: address = @0xDD;

const NOW: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

// ────────────────────────────────────────────────────
// 1. Basic: create_bounty_owned → share → verify shared
// ────────────────────────────────────────────────────
#[test]
fun test_create_owned_and_share_basic() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    // TX1: create owned + share
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    let (bounty, change) = bounty::create_bounty_owned<SUI>(
        utf8(b"Kill target"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    assert!(bounty::status(&bounty) == constants::status_open());
    assert!(bounty::creator(&bounty) == CREATOR);
    assert!(bounty::reward_amount(&bounty) == 1000);
    assert!(bounty::max_claims(&bounty) == 5);
    coin::burn_for_testing(change);
    bounty::share_bounty(bounty);

    // TX2: verify shared object is accessible
    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(bounty::reward_amount(&bounty) == 1000);
    assert!(bounty::status(&bounty) == constants::status_open());
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ────────────────────────────────────────────────────
// 2. Full composable: create → configure all DFs → share → verify
// ────────────────────────────────────────────────────
#[test]
fun test_create_owned_configure_then_share() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    let (mut bounty, change) = bounty::create_bounty_owned<SUI>(
        utf8(b"Kill target"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    coin::burn_for_testing(change);

    // Configure while owned — direct &mut, no take_shared needed
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
    task_type::set_kill_criteria(&mut bounty, 42, 1, 1, ts::ctx(&mut scenario));
    task_type::set_target_victim(&mut bounty, 5002, ts::ctx(&mut scenario));
    task_type::set_encryption_state(&mut bounty, true, &clock, ts::ctx(&mut scenario));

    bounty::share_bounty(bounty);

    // TX2: verify all DFs are accessible on the shared object
    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(task_type::get_task_type(&bounty) == constants::task_type_kill());
    assert!(task_type::get_verification_mode(&bounty) == constants::verify_mode_auto());
    assert!(task_type::has_target_victim(&bounty) == true);
    assert!(task_type::is_criteria_encrypted(&bounty) == true);
    assert!(task_type::get_created_at(&bounty) == NOW);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ────────────────────────────────────────────────────
// 3. Encrypted details composable: create → set_encrypted_details → share
// ────────────────────────────────────────────────────
#[test]
fun test_create_owned_with_encrypted_details() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    let (mut bounty, change) = bounty::create_bounty_owned<SUI>(
        utf8(b"Intel mission"), utf8(b"secret stuff"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    coin::burn_for_testing(change);

    // Set task type INTEL + encryption state + encrypted details in same TX
    task_type::set_task_type(&mut bounty, constants::task_type_intel(), &clock, ts::ctx(&mut scenario));
    task_type::set_encryption_state(&mut bounty, true, &clock, ts::ctx(&mut scenario));

    let payload = b"encrypted-seal-payload-bytes-here";
    encrypted_details::set_encrypted_details(&mut bounty, payload, &clock, ts::ctx(&mut scenario));

    // Verify before sharing (still owned)
    assert!(encrypted_details::has_encrypted_details(&bounty) == true);
    assert!(encrypted_details::get_encrypted_payload(&bounty) == &payload);

    bounty::share_bounty(bounty);

    // TX2: verify encrypted details survive sharing
    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(encrypted_details::has_encrypted_details(&bounty) == true);
    assert!(encrypted_details::get_encrypted_payload(&bounty) == &payload);
    assert!(task_type::get_task_type(&bounty) == constants::task_type_intel());
    assert!(task_type::get_verification_mode(&bounty) == constants::verify_mode_seal());
    assert!(task_type::is_criteria_encrypted(&bounty) == true);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ────────────────────────────────────────────────────
// 4. Change coin: verify exact change returned
// ────────────────────────────────────────────────────
#[test]
fun test_create_owned_change_coin_returned() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    // reward_amount=200, max_claims=3 → escrow needs 600, input=1000 → change=400
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    let (bounty, change) = bounty::create_bounty_owned<SUI>(
        utf8(b"Delivery"), utf8(b"haul stuff"), coin,
        200, 50, 3, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    assert!(coin::value(&change) == 400); // 1000 - 200*3 = 400

    coin::burn_for_testing(change);
    bounty::share_bounty(bounty);

    // Also test exact match: reward_amount=500, max_claims=2 → escrow=1000, input=1000 → change=0
    ts::next_tx(&mut scenario, CREATOR);
    let coin2 = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    let (bounty2, change2) = bounty::create_bounty_owned<SUI>(
        utf8(b"Exact"), utf8(b"no change"), coin2,
        500, 50, 2, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    assert!(coin::value(&change2) == 0);

    coin::burn_for_testing(change2);
    bounty::share_bounty(bounty2);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
