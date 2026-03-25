#[test_only]
module bounty_escrow::test_task_type_v7;

use std::string::utf8;
use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::task_type;
use bounty_escrow::constants;

const CREATOR: address = @0xCA;
const HUNTER: address = @0xBB;
const VERIFIER: address = @0xDD;
const RANDOM_USER: address = @0xFF;

const NOW: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

fun setup_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(scenario));
    bounty::create<SUI>(
        utf8(b"Test bounty"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
}

/// Helper: set task type = KILL + kill criteria
fun set_kill_task(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), clock, ts::ctx(scenario));
    task_type::set_kill_criteria(&mut bounty, 0, 0, 1, ts::ctx(scenario));
    ts::return_shared(bounty);
}

/// Helper: hunter claims the bounty
fun hunter_claim(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(scenario));
    bounty::claim(&mut bounty, stake, clock, ts::ctx(scenario));
    ts::return_shared(bounty);
}

// ============================================================
// set_target_victim tests
// ============================================================

#[test]
fun test_set_target_victim_happy_path() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);
    set_kill_task(&mut scenario, &clock);

    // Set target victim
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_target_victim(&mut bounty, 5002, ts::ctx(&mut scenario));

    assert!(task_type::has_target_victim(&bounty) == true);
    let tv = task_type::borrow_target_victim(&bounty);
    assert!(task_type::target_victim_id(tv) == 5002);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 13)]
fun test_set_target_victim_not_creator() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);
    set_kill_task(&mut scenario, &clock);

    // Random user tries to set target victim
    ts::next_tx(&mut scenario, RANDOM_USER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_target_victim(&mut bounty, 5002, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 65)]
fun test_set_target_victim_wrong_task_type() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);

    // Set DELIVERY task type instead of KILL
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_delivery(), &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Try set_target_victim on DELIVERY bounty
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_target_victim(&mut bounty, 5002, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 67)]
fun test_set_target_victim_no_task_type() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);

    // No task type set, directly try set_target_victim
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_target_victim(&mut bounty, 5002, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 66)]
fun test_set_target_victim_already_set() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);
    set_kill_task(&mut scenario, &clock);

    // First set
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_target_victim(&mut bounty, 5002, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Second set → abort 66
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_target_victim(&mut bounty, 9999, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 64)]
fun test_set_target_victim_has_active_claims() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);
    set_kill_task(&mut scenario, &clock);

    // Hunter claims first
    hunter_claim(&mut scenario, &clock);

    // Creator tries to set target victim after claim → abort 64
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_target_victim(&mut bounty, 5002, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ============================================================
// set_encryption_state tests
// ============================================================

#[test]
fun test_set_encryption_state_happy_path() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_encryption_state(&mut bounty, true, &clock, ts::ctx(&mut scenario));

    assert!(task_type::is_criteria_encrypted(&bounty) == true);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_set_encryption_state_false() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_encryption_state(&mut bounty, false, &clock, ts::ctx(&mut scenario));

    // DF exists but value is false
    assert!(task_type::is_criteria_encrypted(&bounty) == false);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 13)]
fun test_set_encryption_state_not_creator() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);

    // Random user tries to set encryption state
    ts::next_tx(&mut scenario, RANDOM_USER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_encryption_state(&mut bounty, true, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 66)]
fun test_set_encryption_state_already_set() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);

    // First set
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_encryption_state(&mut bounty, true, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Second set → abort 66
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_encryption_state(&mut bounty, false, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ============================================================
// Accessor default-value tests
// ============================================================

#[test]
fun test_is_criteria_encrypted_default_false() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);

    // No EncryptionState DF → returns false
    assert!(task_type::is_criteria_encrypted(&bounty) == false);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_has_target_victim_default_false() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);

    // No TargetVictim DF → returns false
    assert!(task_type::has_target_victim(&bounty) == false);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
