#[test_only]
/// Tests for verify_delivery module.
///
/// Negative tests that abort BEFORE oracle signature verification:
///   - wrong task type, not active hunter, no task type set
///
/// NOTE: Happy path + attestation mismatch tests require pre-computed Ed25519
/// signatures. These should be added when an off-chain signing tool is available.
/// The oracle signature verification itself is covered by oracle module tests.
module bounty_escrow::test_verify_delivery;

use std::string::utf8;
use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::task_type;
use bounty_escrow::constants;
use bounty_escrow::oracle;
use bounty_escrow::verify_delivery;

const CREATOR: address = @0xCA;
const HUNTER: address = @0xBB;
const VERIFIER: address = @0xDD;
const ORACLE_ADMIN: address = @0xAD;
const ORACLE_ADDR: address = @0x0A;

const NOW: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

// Dummy attestation data (will fail signature check, but tests abort before that)
const DUMMY_MSG: vector<u8> = x"00";
const DUMMY_SIG: vector<u8> = x"00";

// =====================================================================
// Setup helpers
// =====================================================================

fun setup_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(scenario));
    bounty::create<SUI>(
        utf8(b"Deliver items"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
}

fun setup_delivery_task(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_delivery(), clock, ts::ctx(scenario));
    task_type::set_delivery_criteria(&mut bounty, 100, 10, @0x0, ts::ctx(scenario));
    ts::return_shared(bounty);
}

fun setup_oracle_registry(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, ORACLE_ADMIN);
    let registry = oracle::create_registry(clock, ts::ctx(scenario));
    oracle::share_registry_for_testing(registry);
}

fun hunter_claim(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(scenario));
    bounty::claim(&mut bounty, stake, clock, ts::ctx(scenario));
    ts::return_shared(bounty);
}

// =====================================================================
// Negative: wrong task type (KILL instead of DELIVERY)
// =====================================================================

#[test, expected_failure(abort_code = 65)] // e_wrong_task_type
fun test_verify_delivery_wrong_task_type() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    setup_bounty(&mut scenario, &clock);

    // Set KILL instead of DELIVERY
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
        task_type::set_kill_criteria(&mut bounty, 0, 0, 1, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
    verify_delivery::verify_delivery(
        &mut bounty, &registry, DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR,
        &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: no task type set (defaults to CUSTOM)
// =====================================================================

#[test, expected_failure(abort_code = 65)] // e_wrong_task_type
fun test_verify_delivery_no_task_type() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    setup_bounty(&mut scenario, &clock);
    // No set_task_type
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
    verify_delivery::verify_delivery(
        &mut bounty, &registry, DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR,
        &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: hunter not active (not claimed)
// =====================================================================

#[test, expected_failure(abort_code = 17)] // e_hunter_not_active
fun test_verify_delivery_hunter_not_active() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    setup_bounty(&mut scenario, &clock);
    setup_delivery_task(&mut scenario, &clock);
    // Hunter does NOT claim
    setup_oracle_registry(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
    verify_delivery::verify_delivery(
        &mut bounty, &registry, DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR,
        &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: oracle not active (not registered)
// =====================================================================

#[test, expected_failure(abort_code = 75)] // e_oracle_not_active
fun test_verify_delivery_oracle_not_active() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    setup_bounty(&mut scenario, &clock);
    setup_delivery_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);
    // Oracle NOT registered → verify_attestation aborts with e_oracle_not_active

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
    verify_delivery::verify_delivery(
        &mut bounty, &registry, DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR,
        &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: oracle deactivated
// =====================================================================

#[test, expected_failure(abort_code = 75)] // e_oracle_not_active
fun test_verify_delivery_oracle_deactivated() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    setup_bounty(&mut scenario, &clock);
    setup_delivery_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);

    // Register then deactivate oracle
    ts::next_tx(&mut scenario, ORACLE_ADMIN);
    {
        let mut registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
        // 32-byte dummy pubkey
        let pubkey = x"0000000000000000000000000000000000000000000000000000000000000001";
        oracle::register_oracle(&mut registry, ORACLE_ADDR, utf8(b"oracle"), pubkey, &clock, ts::ctx(&mut scenario));
        oracle::deactivate_oracle(&mut registry, ORACLE_ADDR, ts::ctx(&mut scenario));
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
    verify_delivery::verify_delivery(
        &mut bounty, &registry, DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR,
        &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: invalid attestation signature (registered oracle, bad sig)
// =====================================================================

#[test, expected_failure(abort_code = 77)] // e_invalid_attestation
fun test_verify_delivery_invalid_signature() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    setup_bounty(&mut scenario, &clock);
    setup_delivery_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);

    // Register oracle with real-looking 32-byte pubkey
    ts::next_tx(&mut scenario, ORACLE_ADMIN);
    {
        let mut registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
        let pubkey = x"d75a980182b10ab7d54bfed3c964073a0ee172f3daa3f4a18446b7c8b7b9f1cc";
        oracle::register_oracle(&mut registry, ORACLE_ADDR, utf8(b"oracle"), pubkey, &clock, ts::ctx(&mut scenario));
        ts::return_shared(registry);
    };

    // Bad signature (wrong length/content) → ed25519 verify fails
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
    let bad_sig = x"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    verify_delivery::verify_delivery(
        &mut bounty, &registry, DUMMY_MSG, bad_sig, ORACLE_ADDR,
        &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
