#[test_only]
/// Tests for verify_kill module.
///
/// Happy path: correct killmail + character → auto-approve
/// Negative: wrong task type, not active hunter, character mismatch,
///           not killer, killmail too old, solar system mismatch,
///           loss type mismatch, killmail replay
/// Monkey: timestamp boundary, grace period edge, full claim_reward cycle
module bounty_escrow::test_verify_kill;

use std::string::utf8;
use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use world::access::AdminACL;
use world::character::{Self, Character};
use world::killmail::{Self, Killmail};
use world::killmail_registry::KillmailRegistry;
use world::object_registry::ObjectRegistry;
use world::test_helpers::{Self, admin, tenant};
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::task_type;
use bounty_escrow::constants;
use bounty_escrow::verify_kill;

// === Addresses ===
const CREATOR: address = @0xCA;
const HUNTER: address = @0xBB;
const VERIFIER: address = @0xDD;

// === Game IDs ===
const KILLER_GAME_ID: u64 = 5001;
const VICTIM_GAME_ID: u64 = 5002;
const KILLMAIL_ITEM_ID: u64 = 9001;
const SOLAR_SYSTEM_42: u64 = 42;

// === Loss types (match world::killmail create_killmail u8 param) ===
const LOSS_SHIP: u8 = 1;
const LOSS_STRUCTURE: u8 = 2;

// === Timing ===
const NOW: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000; // +1 day
const GRACE: u64 = 86_400_000; // 1 day

// =====================================================================
// Setup helpers
// =====================================================================

/// Create a Character, share it. Returns its ID.
/// Caller must have called setup_world first.
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

/// Create bounty (CREATOR), 5000 SUI escrow.
fun setup_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(scenario));
    bounty::create<SUI>(
        utf8(b"Kill target"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
}

/// Set task type = KILL + criteria.
fun setup_kill_task(scenario: &mut ts::Scenario, clock: &clock::Clock, solar: u64, loss: u8) {
    ts::next_tx(scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), clock, ts::ctx(scenario));
    task_type::set_kill_criteria(&mut bounty, solar, loss, 1, ts::ctx(scenario));
    ts::return_shared(bounty);
}

/// Hunter claims the bounty.
fun hunter_claim(scenario: &mut ts::Scenario, hunter: address, clock: &clock::Clock) {
    ts::next_tx(scenario, hunter);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(scenario));
    bounty::claim(&mut bounty, stake, clock, ts::ctx(scenario));
    ts::return_shared(bounty);
}

/// Create a shared killmail via the admin API.
/// Uses char_id's character as reporter (provides tenant).
fun setup_killmail(
    scenario: &mut ts::Scenario,
    char_id: ID,
    killmail_item_id: u64,
    killer_game_id: u64,
    kill_timestamp: u64,
    solar_system_id: u64,
    loss_type: u8,
) {
    ts::next_tx(scenario, admin());
    let mut km_registry = ts::take_shared<KillmailRegistry>(scenario);
    let admin_acl = ts::take_shared<AdminACL>(scenario);
    let character = ts::take_shared_by_id<Character>(scenario, char_id);
    killmail::create_killmail(
        &mut km_registry, &admin_acl,
        killmail_item_id, killer_game_id, VICTIM_GAME_ID,
        &character, kill_timestamp, loss_type, solar_system_id,
        ts::ctx(scenario),
    );
    ts::return_shared(character);
    ts::return_shared(admin_acl);
    ts::return_shared(km_registry);
}

/// Full happy-path setup. Returns char_id.
fun full_setup(
    scenario: &mut ts::Scenario,
    clock: &mut clock::Clock,
    solar_criteria: u64,
    loss_criteria: u8,
    kill_timestamp: u64,
    km_solar: u64,
    km_loss: u8,
): ID {
    clock::set_for_testing(clock, NOW);
    test_helpers::setup_world(scenario);
    let char_id = setup_character(scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(scenario, clock);
    setup_kill_task(scenario, clock, solar_criteria, loss_criteria);
    hunter_claim(scenario, HUNTER, clock);
    setup_killmail(scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, kill_timestamp, km_solar, km_loss);
    char_id
}

// =====================================================================
// Happy path
// =====================================================================

#[test]
/// Correct killmail + matching character → auto-approve.
fun test_verify_kill_happy_path() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(&mut scenario, &mut clock, 0, 0, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    // No abort = hunter auto-approved
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
/// Happy path with specific solar system criteria that matches.
fun test_verify_kill_solar_match() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(
        &mut scenario, &mut clock,
        SOLAR_SYSTEM_42, 0, // criteria: specific solar, any loss
        NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP,
    );

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
/// Happy path with loss_type=SHIP criteria matching SHIP killmail.
fun test_verify_kill_loss_ship_match() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(
        &mut scenario, &mut clock,
        0, 1, // criteria: any solar, SHIP
        NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP,
    );

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
/// Happy path with loss_type=STRUCTURE criteria matching STRUCTURE killmail.
fun test_verify_kill_loss_structure_match() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(
        &mut scenario, &mut clock,
        0, 2, // criteria: any solar, STRUCTURE
        NOW + 1, SOLAR_SYSTEM_42, LOSS_STRUCTURE,
    );

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: wrong task type
// =====================================================================

#[test, expected_failure(abort_code = 65)] // e_wrong_task_type
fun test_verify_kill_wrong_task_type() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);
    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);

    // Set DELIVERY instead of KILL
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_task_type(&mut bounty, constants::task_type_delivery(), &clock, ts::ctx(&mut scenario));
        task_type::set_delivery_criteria(&mut bounty, 100, 10, @0x0, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };
    hunter_claim(&mut scenario, HUNTER, &clock);
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 65)] // e_wrong_task_type
/// No task type set → defaults to CUSTOM(0) → wrong type.
fun test_verify_kill_no_task_type_set() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);
    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);
    // No set_task_type
    hunter_claim(&mut scenario, HUNTER, &clock);
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: hunter not active
// =====================================================================

#[test, expected_failure(abort_code = 17)] // e_hunter_not_active
fun test_verify_kill_hunter_not_active() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);
    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);
    setup_kill_task(&mut scenario, &clock, 0, 0);
    // Hunter does NOT claim
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: character_address mismatch (character belongs to someone else)
// =====================================================================

#[test, expected_failure(abort_code = 73)] // e_character_mismatch
fun test_verify_kill_character_mismatch() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);

    // Character owned by @0xEE, but HUNTER (@0xBB) sends tx
    let char_id = setup_character(&mut scenario, @0xEE, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);
    setup_kill_task(&mut scenario, &clock, 0, 0);
    hunter_claim(&mut scenario, HUNTER, &clock);
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: not the killer
// =====================================================================

#[test, expected_failure(abort_code = 68)] // e_not_killer
fun test_verify_kill_not_killer() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);

    // Character game_id = 7777, but killmail killer_id = KILLER_GAME_ID (5001)
    let char_id = setup_character(&mut scenario, HUNTER, 7777);
    setup_bounty(&mut scenario, &clock);
    setup_kill_task(&mut scenario, &clock, 0, 0);
    hunter_claim(&mut scenario, HUNTER, &clock);
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: killmail too old
// =====================================================================

#[test, expected_failure(abort_code = 69)] // e_killmail_too_old
fun test_verify_kill_killmail_too_old() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    // kill_timestamp < task_type created_at (NOW)
    let char_id = full_setup(&mut scenario, &mut clock, 0, 0, NOW - 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: solar system mismatch
// =====================================================================

#[test, expected_failure(abort_code = 70)] // e_solar_system_mismatch
fun test_verify_kill_solar_system_mismatch() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    // Criteria: solar=99999, killmail: solar=42
    let char_id = full_setup(&mut scenario, &mut clock, 99999, 0, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: loss type mismatch (criteria=STRUCTURE, killmail=SHIP)
// =====================================================================

#[test, expected_failure(abort_code = 71)] // e_loss_type_mismatch
fun test_verify_kill_loss_type_mismatch_structure_vs_ship() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    // Criteria: STRUCTURE(2), killmail: SHIP(1)
    let char_id = full_setup(&mut scenario, &mut clock, 0, 2, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 71)] // e_loss_type_mismatch
/// Criteria=SHIP(1), killmail=STRUCTURE(2)
fun test_verify_kill_loss_type_mismatch_ship_vs_structure() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(&mut scenario, &mut clock, 0, 1, NOW + 1, SOLAR_SYSTEM_42, LOSS_STRUCTURE);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Negative: killmail replay
// =====================================================================

#[test, expected_failure(abort_code = 72)] // e_killmail_already_used
/// Same killmail used twice by the same hunter → replay protection fires.
/// (Check order: replay check #8 fires before auto_verify_approve #9)
fun test_verify_kill_replay() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(&mut scenario, &mut clock, 0, 0, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    // First verify — succeeds
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        let character = ts::take_shared_by_id<Character>(&scenario, char_id);
        let killmail = ts::take_shared<Killmail>(&scenario);
        verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
        ts::return_shared(character);
        ts::return_shared(killmail);
    };

    // Second verify same killmail — aborts at e_killmail_already_used (72)
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        let character = ts::take_shared_by_id<Character>(&scenario, char_id);
        let killmail = ts::take_shared<Killmail>(&scenario);
        verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
        ts::return_shared(character);
        ts::return_shared(killmail);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Monkey: kill_timestamp exactly at created_at (boundary)
// =====================================================================

#[test]
/// kill_timestamp == task_type created_at → passes (>= check)
fun test_verify_kill_timestamp_exact_boundary() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(&mut scenario, &mut clock, 0, 0, NOW, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Monkey: verify after deadline but within grace period
// =====================================================================

#[test]
/// Clock past deadline but within grace → auto_verify_approve allows it.
fun test_verify_kill_after_deadline_within_grace() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(&mut scenario, &mut clock, 0, 0, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    clock::set_for_testing(&mut clock, DEADLINE + 1);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Monkey: verify after deadline + grace → should fail
// =====================================================================

#[test, expected_failure(abort_code = 20)] // e_grace_period_not_passed (auto_verify_approve)
fun test_verify_kill_after_grace_period() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(&mut scenario, &mut clock, 0, 0, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// Integration: verify_kill → claim_reward full cycle
// =====================================================================

#[test]
fun test_verify_kill_then_claim_reward() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    let char_id = full_setup(&mut scenario, &mut clock, 0, 0, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    // Verify kill
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        let character = ts::take_shared_by_id<Character>(&scenario, char_id);
        let killmail = ts::take_shared<Killmail>(&scenario);
        verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
        ts::return_shared(character);
        ts::return_shared(killmail);
    };

    // Claim reward — proves hunter was truly approved
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        let ticket = ts::take_from_sender<bounty::ClaimTicket>(&scenario);
        bounty::claim_reward(&mut bounty, ticket, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// v7: encrypted criteria blocks auto-verify
// =====================================================================

#[test, expected_failure(abort_code = 98)] // e_criteria_encrypted_manual_only
fun test_verify_kill_encrypted_criteria_blocked() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);
    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);
    setup_kill_task(&mut scenario, &clock, 0, 0);

    // Set encryption state BEFORE hunter claims (requires 0 active_claims)
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_encryption_state(&mut bounty, true, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    hunter_claim(&mut scenario, HUNTER, &clock);
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// v7: target victim match
// =====================================================================

#[test]
fun test_verify_kill_target_victim_match() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);
    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);

    // Set KILL task + criteria + target victim = VICTIM_GAME_ID
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
        task_type::set_kill_criteria(&mut bounty, 0, 0, 1, ts::ctx(&mut scenario));
        task_type::set_target_victim(&mut bounty, VICTIM_GAME_ID, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    hunter_claim(&mut scenario, HUNTER, &clock);
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// v7: target victim mismatch
// =====================================================================

#[test, expected_failure(abort_code = 94)] // e_victim_mismatch
fun test_verify_kill_target_victim_mismatch() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);
    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);

    // Set target victim to 9999 (won't match VICTIM_GAME_ID=5002)
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_task_type(&mut bounty, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
        task_type::set_kill_criteria(&mut bounty, 0, 0, 1, ts::ctx(&mut scenario));
        task_type::set_target_victim(&mut bounty, 9999, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    hunter_claim(&mut scenario, HUNTER, &clock);
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1, SOLAR_SYSTEM_42, LOSS_SHIP);

    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
