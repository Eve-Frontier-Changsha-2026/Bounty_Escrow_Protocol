#[test_only]
/// Round 11: Task Type Access Control
/// Attack vectors:
///   11a: Non-creator sets task type
///   11b: Set task type after claims exist (active_claims > 0)
///   11c: Set task type on non-OPEN bounty
///   11d: Set task type twice (overwrite)
///   11e: Invalid task type value (out of range)
///   11f: Set kill criteria on DELIVERY bounty (wrong type)
///   11g: Non-creator sets kill criteria
///   11h: Set kill criteria twice (overwrite)
module bounty_escrow::red_team_round_11_task_type_access;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::task_type;
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER: address = @0xC;
const ATTACKER: address = @0xD;

fun create_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Test bounty".to_string(), b"desc".to_string(), coin,
        1000, 100, 5,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
}

// --- 11a: Non-creator tries to set task type ---
// DEFENSE: assert!(ctx.sender() == creator) in set_task_type
#[test, expected_failure(abort_code = 13)] // e_not_creator
fun red_team_round_11a_non_creator_set_task_type() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, ATTACKER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- 11b: Set task type after hunter has claimed (active_claims > 0) ---
// DEFENSE: assert!(active_claims == 0)
#[test, expected_failure(abort_code = 64)] // e_task_type_has_active_claims
fun red_team_round_11b_set_type_after_claim() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_bounty(&mut scenario, &clock);

    // Hunter claims
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Creator tries to set task type — should fail
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- 11c: Set task type on cancelled bounty ---
// DEFENSE: assert!(status == status_open())
#[test, expected_failure(abort_code = 63)] // e_task_type_requires_open
fun red_team_round_11c_set_type_cancelled() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_bounty(&mut scenario, &clock);

    // Cancel
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Try set task type on cancelled
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- 11d: Set task type twice ---
// DEFENSE: assert!(!dynamic_field::exists_(uid, TaskTypeKey()))
#[test, expected_failure(abort_code = 62)] // e_task_type_already_set
fun red_team_round_11d_set_type_twice() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
    // Try overwrite
    task_type::set_task_type(&mut bounty, constants::task_type_delivery(), &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- 11e: Invalid task type value ---
// DEFENSE: assert!(task_type <= task_type_intel())
#[test, expected_failure(abort_code = 61)] // e_invalid_task_type
fun red_team_round_11e_invalid_task_type() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_task_type(&mut bounty, 99, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- 11f: Set kill criteria on DELIVERY bounty ---
// DEFENSE: assert!(config.task_type == task_type_kill())
#[test, expected_failure(abort_code = 65)] // e_wrong_task_type
fun red_team_round_11f_kill_criteria_on_delivery() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_delivery(), &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_kill_criteria(&mut bounty, 0, 0, 1, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- 11g: Non-creator sets criteria ---
// DEFENSE: assert!(ctx.sender() == creator)
#[test, expected_failure(abort_code = 13)] // e_not_creator
fun red_team_round_11g_attacker_sets_criteria() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Attacker tries to set criteria
    ts::next_tx(&mut scenario, ATTACKER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_kill_criteria(&mut bounty, 0, 0, 1, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- 11h: Set kill criteria twice (overwrite attempt) ---
// DEFENSE: assert!(!dynamic_field::exists_(uid, KillCriteriaKey()))
#[test, expected_failure(abort_code = 66)] // e_criteria_already_set
fun red_team_round_11h_criteria_overwrite() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    task_type::set_kill_criteria(&mut bounty, 0, 0, 1, ts::ctx(&mut scenario));
    // Try overwrite
    task_type::set_kill_criteria(&mut bounty, 999, 1, 10, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
