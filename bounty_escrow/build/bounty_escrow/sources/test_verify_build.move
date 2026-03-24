#[test_only]
/// Tests for verify_build module.
///
/// Negative tests covering pre-signature checks:
///   - wrong task type, not active hunter, character mismatch
///   - oracle not active, oracle deactivated, invalid signature
///
/// NOTE: Happy path + attestation field mismatch tests (bounty_id, hunter,
/// assembly_id, criteria) require pre-computed Ed25519 signatures over
/// BCS-encoded build attestation data. Add when signing tool available.
module bounty_escrow::test_verify_build;

use std::string::utf8;
use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use world::access::AdminACL;
use world::assembly::{Self, Assembly};
use world::character::{Self, Character};
use world::network_node::{Self, NetworkNode};
use world::object_registry::ObjectRegistry;
use world::test_helpers::{Self, admin, tenant};
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::task_type;
use bounty_escrow::constants;
use bounty_escrow::oracle;
use bounty_escrow::verify_build;

const CREATOR: address = @0xCA;
const HUNTER: address = @0xBB;
const VERIFIER: address = @0xDD;
const ORACLE_ADMIN: address = @0xAD;
const ORACLE_ADDR: address = @0x0A;

const HUNTER_GAME_ID: u32 = 5001;
const ASSEMBLY_ITEM_ID: u64 = 1001;
const ASSEMBLY_TYPE_ID: u64 = 8888;
const NWN_ITEM_ID: u64 = 5000;
const NWN_TYPE_ID: u64 = 111000;
const LOCATION_HASH: vector<u8> = x"7a8f3b2e9c4d1a6f5e8b2d9c3f7a1e5b7a8f3b2e9c4d1a6f5e8b2d9c3f7a1e5b";

const NOW: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

const DUMMY_MSG: vector<u8> = x"00";
const DUMMY_SIG: vector<u8> = x"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

// =====================================================================
// Setup helpers
// =====================================================================

/// Full world setup + fuel + energy config.
fun setup_world_full(scenario: &mut ts::Scenario) {
    test_helpers::setup_world(scenario);
    test_helpers::configure_fuel(scenario);
    test_helpers::configure_assembly_energy(scenario);
}

fun setup_character(scenario: &mut ts::Scenario, owner: address, game_id: u32): ID {
    ts::next_tx(scenario, admin());
    let mut registry = ts::take_shared<ObjectRegistry>(scenario);
    let admin_acl = ts::take_shared<AdminACL>(scenario);
    let character = character::create_character(
        &mut registry, &admin_acl,
        game_id, tenant(), 100, owner, utf8(b"hunter"), ts::ctx(scenario),
    );
    let id = object::id(&character);
    character::share_character(character, &admin_acl, ts::ctx(scenario));
    ts::return_shared(registry);
    ts::return_shared(admin_acl);
    id
}

fun setup_network_node(scenario: &mut ts::Scenario, char_id: ID): ID {
    ts::next_tx(scenario, admin());
    let mut registry = ts::take_shared<ObjectRegistry>(scenario);
    let character = ts::take_shared_by_id<Character>(scenario, char_id);
    let admin_acl = ts::take_shared<AdminACL>(scenario);
    let nwn = network_node::anchor(
        &mut registry, &character, &admin_acl,
        NWN_ITEM_ID, NWN_TYPE_ID, LOCATION_HASH,
        1000, 3_600_000, 100, ts::ctx(scenario),
    );
    let id = object::id(&nwn);
    nwn.share_network_node(&admin_acl, ts::ctx(scenario));
    ts::return_shared(character);
    ts::return_shared(admin_acl);
    ts::return_shared(registry);
    id
}

fun setup_assembly(scenario: &mut ts::Scenario, nwn_id: ID, char_id: ID): ID {
    ts::next_tx(scenario, admin());
    let character = ts::take_shared_by_id<Character>(scenario, char_id);
    let mut registry = ts::take_shared<ObjectRegistry>(scenario);
    let mut nwn = ts::take_shared_by_id<NetworkNode>(scenario, nwn_id);
    let admin_acl = ts::take_shared<AdminACL>(scenario);
    let assembly = assembly::anchor(
        &mut registry, &mut nwn, &character, &admin_acl,
        ASSEMBLY_ITEM_ID, ASSEMBLY_TYPE_ID, LOCATION_HASH, ts::ctx(scenario),
    );
    let id = object::id(&assembly);
    assembly.share_assembly(&admin_acl, ts::ctx(scenario));
    ts::return_shared(character);
    ts::return_shared(admin_acl);
    ts::return_shared(registry);
    ts::return_shared(nwn);
    id
}

fun setup_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(scenario));
    bounty::create<SUI>(
        utf8(b"Build assembly"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
}

fun setup_build_task(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_build(), clock, ts::ctx(scenario));
    task_type::set_build_criteria(&mut bounty, ASSEMBLY_TYPE_ID, 0, ts::ctx(scenario));
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

/// Full world + assembly setup. Returns (char_id, assembly_id).
fun full_world_setup(scenario: &mut ts::Scenario, clock: &mut clock::Clock): (ID, ID) {
    clock::set_for_testing(clock, NOW);
    setup_world_full(scenario);
    let char_id = setup_character(scenario, HUNTER, HUNTER_GAME_ID);
    let nwn_id = setup_network_node(scenario, char_id);
    let assembly_id = setup_assembly(scenario, nwn_id, char_id);
    (char_id, assembly_id)
}

// =====================================================================
// Negative: wrong task type (KILL instead of BUILD)
// =====================================================================

#[test, expected_failure(abort_code = 65)] // e_wrong_task_type
fun test_verify_build_wrong_task_type() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let (char_id, assembly_id) = full_world_setup(&mut scenario, &mut clock);
    setup_bounty(&mut scenario, &clock);

    // Set KILL instead of BUILD
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
    let assembly = ts::take_shared_by_id<Assembly>(&scenario, assembly_id);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);

    verify_build::verify_build(
        &mut bounty, &assembly, &character, &registry,
        DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR, &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    ts::return_shared(assembly);
    ts::return_shared(character);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: no task type set (defaults to CUSTOM)
// =====================================================================

#[test, expected_failure(abort_code = 65)] // e_wrong_task_type
fun test_verify_build_no_task_type() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let (char_id, assembly_id) = full_world_setup(&mut scenario, &mut clock);
    setup_bounty(&mut scenario, &clock);
    // No set_task_type
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let assembly = ts::take_shared_by_id<Assembly>(&scenario, assembly_id);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);

    verify_build::verify_build(
        &mut bounty, &assembly, &character, &registry,
        DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR, &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    ts::return_shared(assembly);
    ts::return_shared(character);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: hunter not active (not claimed)
// =====================================================================

#[test, expected_failure(abort_code = 17)] // e_hunter_not_active
fun test_verify_build_hunter_not_active() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let (char_id, assembly_id) = full_world_setup(&mut scenario, &mut clock);
    setup_bounty(&mut scenario, &clock);
    setup_build_task(&mut scenario, &clock);
    // Hunter does NOT claim
    setup_oracle_registry(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let assembly = ts::take_shared_by_id<Assembly>(&scenario, assembly_id);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);

    verify_build::verify_build(
        &mut bounty, &assembly, &character, &registry,
        DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR, &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    ts::return_shared(assembly);
    ts::return_shared(character);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: character mismatch (character.address != sender)
// =====================================================================

#[test, expected_failure(abort_code = 73)] // e_character_mismatch
fun test_verify_build_character_mismatch() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    setup_world_full(&mut scenario);
    // Character owned by @0xEE, not HUNTER
    let char_id = setup_character(&mut scenario, @0xEE, HUNTER_GAME_ID);
    let nwn_id = setup_network_node(&mut scenario, char_id);
    let assembly_id = setup_assembly(&mut scenario, nwn_id, char_id);
    setup_bounty(&mut scenario, &clock);
    setup_build_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let assembly = ts::take_shared_by_id<Assembly>(&scenario, assembly_id);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);

    verify_build::verify_build(
        &mut bounty, &assembly, &character, &registry,
        DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR, &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    ts::return_shared(assembly);
    ts::return_shared(character);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: oracle not active (not registered)
// =====================================================================

#[test, expected_failure(abort_code = 75)] // e_oracle_not_active
fun test_verify_build_oracle_not_active() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let (char_id, assembly_id) = full_world_setup(&mut scenario, &mut clock);
    setup_bounty(&mut scenario, &clock);
    setup_build_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);
    // Oracle NOT registered

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let assembly = ts::take_shared_by_id<Assembly>(&scenario, assembly_id);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);

    verify_build::verify_build(
        &mut bounty, &assembly, &character, &registry,
        DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR, &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    ts::return_shared(assembly);
    ts::return_shared(character);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: oracle deactivated
// =====================================================================

#[test, expected_failure(abort_code = 75)] // e_oracle_not_active
fun test_verify_build_oracle_deactivated() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let (char_id, assembly_id) = full_world_setup(&mut scenario, &mut clock);
    setup_bounty(&mut scenario, &clock);
    setup_build_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);

    // Register then deactivate oracle
    ts::next_tx(&mut scenario, ORACLE_ADMIN);
    {
        let mut registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
        let pubkey = x"d75a980182b10ab7d54bfed3c964073a0ee172f3daa3f4a18446b7c8b7b9f1cc";
        oracle::register_oracle(&mut registry, ORACLE_ADDR, utf8(b"oracle"), pubkey, &clock, ts::ctx(&mut scenario));
        oracle::deactivate_oracle(&mut registry, ORACLE_ADDR, ts::ctx(&mut scenario));
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let assembly = ts::take_shared_by_id<Assembly>(&scenario, assembly_id);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);

    verify_build::verify_build(
        &mut bounty, &assembly, &character, &registry,
        DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR, &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    ts::return_shared(assembly);
    ts::return_shared(character);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: invalid attestation signature
// =====================================================================

#[test, expected_failure(abort_code = 77)] // e_invalid_attestation
fun test_verify_build_invalid_signature() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let (char_id, assembly_id) = full_world_setup(&mut scenario, &mut clock);
    setup_bounty(&mut scenario, &clock);
    setup_build_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);
    setup_oracle_registry(&mut scenario, &clock);

    // Register oracle with real pubkey
    ts::next_tx(&mut scenario, ORACLE_ADMIN);
    {
        let mut registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
        let pubkey = x"d75a980182b10ab7d54bfed3c964073a0ee172f3daa3f4a18446b7c8b7b9f1cc";
        oracle::register_oracle(&mut registry, ORACLE_ADDR, utf8(b"oracle"), pubkey, &clock, ts::ctx(&mut scenario));
        ts::return_shared(registry);
    };

    // Bad signature → ed25519 verify fails
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let assembly = ts::take_shared_by_id<Assembly>(&scenario, assembly_id);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let registry = ts::take_shared<oracle::OracleRegistry>(&scenario);

    verify_build::verify_build(
        &mut bounty, &assembly, &character, &registry,
        DUMMY_MSG, DUMMY_SIG, ORACLE_ADDR, &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    ts::return_shared(assembly);
    ts::return_shared(character);
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
