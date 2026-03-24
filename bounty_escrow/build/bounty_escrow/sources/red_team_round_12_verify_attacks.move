#[test_only]
/// Round 12: Verify Module Adversarial Attacks
///
/// Attack vectors targeting the v5 auto-verification pipeline:
///   12a: Stolen character — attacker uses own character to claim another's kill
///   12b: Cross-bounty killmail double-dip — same killmail on two bounties
///   12c: Front-run verify — attacker steals shared killmail for own bounty claim
///   12d: Oracle admin impersonation — non-admin registers oracle
///   12e: Oracle admin impersonation — non-admin deactivates oracle
///   12f: Oracle double registration — re-register same address
///   12g: Intel slot griefing — attacker (active hunter) posts garbage, blocks real hunter
///   12h: Intel non-creator confirm — attacker tries to confirm
///   12i: Intel double confirm — creator confirms twice
///   12j: Seal namespace bypass — id shorter than bounty_id
///   12k: Seal namespace byte mismatch — wrong prefix bytes
///   12l: Double auto-approve — verify_kill twice on same bounty (already approved)
///   12m: Verify on cancelled bounty — verify_kill after bounty cancelled
module bounty_escrow::red_team_round_12_verify_attacks;

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
use bounty_escrow::oracle;
use bounty_escrow::intel_escrow;

// === Addresses ===
const CREATOR: address = @0xCA;
const HUNTER: address = @0xBB;
const ATTACKER: address = @0xDD;
const VERIFIER: address = @0xEE;
const ORACLE_ADDR: address = @0xF1;

// === Game IDs ===
const KILLER_GAME_ID: u64 = 5001;
const ATTACKER_GAME_ID: u64 = 6001;
const VICTIM_GAME_ID: u64 = 5002;
const KILLMAIL_ITEM_ID: u64 = 9001;
const KILLMAIL_ITEM_ID_2: u64 = 9002;
const SOLAR_SYSTEM_42: u64 = 42;

const LOSS_SHIP: u8 = 1;

// === Timing ===
const NOW: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

// =====================================================================
// Setup helpers
// =====================================================================

fun setup_character(scenario: &mut ts::Scenario, owner: address, game_id: u32): ID {
    ts::next_tx(scenario, admin());
    let mut registry = ts::take_shared<ObjectRegistry>(scenario);
    let admin_acl = ts::take_shared<AdminACL>(scenario);
    let character = character::create_character(
        &mut registry, &admin_acl,
        game_id, tenant(), 100, owner, utf8(b"char"), ts::ctx(scenario),
    );
    let id = object::id(&character);
    character::share_character(character, &admin_acl, ts::ctx(scenario));
    ts::return_shared(registry);
    ts::return_shared(admin_acl);
    id
}

fun setup_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(scenario));
    bounty::create<SUI>(
        utf8(b"Bounty"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
}

fun setup_kill_task(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    task_type::set_task_type(&mut bounty, constants::task_type_kill(), clock, ts::ctx(scenario));
    task_type::set_kill_criteria(&mut bounty, 0, 0, 1, ts::ctx(scenario));
    ts::return_shared(bounty);
}

fun hunter_claim(scenario: &mut ts::Scenario, hunter: address, clock: &clock::Clock) {
    ts::next_tx(scenario, hunter);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(scenario));
    bounty::claim(&mut bounty, stake, clock, ts::ctx(scenario));
    ts::return_shared(bounty);
}

fun setup_killmail(
    scenario: &mut ts::Scenario,
    char_id: ID,
    killmail_item_id: u64,
    killer_game_id: u64,
    kill_timestamp: u64,
) {
    ts::next_tx(scenario, admin());
    let mut km_registry = ts::take_shared<KillmailRegistry>(scenario);
    let admin_acl = ts::take_shared<AdminACL>(scenario);
    let character = ts::take_shared_by_id<Character>(scenario, char_id);
    killmail::create_killmail(
        &mut km_registry, &admin_acl,
        killmail_item_id, killer_game_id, VICTIM_GAME_ID,
        &character, kill_timestamp, LOSS_SHIP, SOLAR_SYSTEM_42,
        ts::ctx(scenario),
    );
    ts::return_shared(character);
    ts::return_shared(admin_acl);
    ts::return_shared(km_registry);
}

// =====================================================================
// 12a: Stolen character — attacker creates own character, tries to claim
//      someone else's kill via the shared killmail.
// DEFENSE: killmail.killer_id() == hunter_character.key()
//          Attacker's character has different game_id → e_not_killer
// =====================================================================
#[test, expected_failure(abort_code = 68)] // e_not_killer
fun red_team_round_12a_stolen_kill_credit() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);

    // Hunter's character (game_id 5001) — the real killer
    let hunter_char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    // Attacker's character (game_id 6001) — NOT the killer
    let attacker_char_id = setup_character(&mut scenario, ATTACKER, ATTACKER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);
    setup_kill_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, ATTACKER, &clock); // attacker claims bounty
    // Killmail created by hunter's kill (killer_game_id = 5001)
    setup_killmail(&mut scenario, hunter_char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1);

    // Attacker tries to verify using their own character + hunter's killmail
    ts::next_tx(&mut scenario, ATTACKER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let attacker_character = ts::take_shared_by_id<Character>(&scenario, attacker_char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    // Attack: attacker's character.key() (6001) != killmail.killer_id() (5001) → abort
    verify_kill::verify_kill(&mut bounty, &killmail, &attacker_character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(attacker_character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12b: Cross-bounty killmail double-dip — same killmail on TWO bounties.
// BEHAVIOR: UsedKillmailKey is per-bounty DF → same killmail CAN be used
//           across different bounties. This is BY DESIGN (a kill satisfies
//           multiple independent bounties). Test confirms this succeeds.
// =====================================================================
#[test]
fun red_team_round_12b_cross_bounty_killmail_reuse() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);

    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);

    // Bounty A
    setup_bounty(&mut scenario, &clock);
    setup_kill_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, HUNTER, &clock);

    // Bounty B (use different phantom type to avoid take_shared ambiguity)
    // Actually we can't easily create a second Bounty<SUI> without ambiguity.
    // Instead, we'll create bounty B, set it up, then verify kill on bounty A first,
    // then verify the same killmail on bounty B.
    // For disambiguation we use take_shared_by_id.

    // Get bounty A's ID
    ts::next_tx(&mut scenario, CREATOR);
    let bounty_a = ts::take_shared<Bounty<SUI>>(&scenario);
    let bounty_a_id = object::id(&bounty_a);
    ts::return_shared(bounty_a);

    // Create bounty B
    ts::next_tx(&mut scenario, CREATOR);
    let coin_b = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        utf8(b"Bounty B"), utf8(b"desc2"), coin_b,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Get bounty B's ID (it's the most recent shared object)
    ts::next_tx(&mut scenario, CREATOR);
    // We need to find bounty B. Since we know bounty A's ID, we take both and check.
    let bounty_check = ts::take_shared<Bounty<SUI>>(&scenario);
    let bounty_b_id = if (object::id(&bounty_check) == bounty_a_id) {
        ts::return_shared(bounty_check);
        // bounty B is the other one — but we can't easily get it without its ID.
        // Workaround: use take_shared which returns the first available.
        // Let's try a different approach.
        abort 999 // should not reach
    } else {
        let id = object::id(&bounty_check);
        ts::return_shared(bounty_check);
        id
    };

    // Setup kill task on bounty B
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty_b = ts::take_shared_by_id<Bounty<SUI>>(&scenario, bounty_b_id);
        task_type::set_task_type(&mut bounty_b, constants::task_type_kill(), &clock, ts::ctx(&mut scenario));
        task_type::set_kill_criteria(&mut bounty_b, 0, 0, 1, ts::ctx(&mut scenario));
        ts::return_shared(bounty_b);
    };

    // Hunter claims bounty B
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty_b = ts::take_shared_by_id<Bounty<SUI>>(&scenario, bounty_b_id);
        let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
        bounty::claim(&mut bounty_b, stake, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty_b);
    };

    // Create killmail
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1);

    // Verify kill on bounty A — should succeed
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty_a = ts::take_shared_by_id<Bounty<SUI>>(&scenario, bounty_a_id);
        let character = ts::take_shared_by_id<Character>(&scenario, char_id);
        let killmail = ts::take_shared<Killmail>(&scenario);
        verify_kill::verify_kill(&mut bounty_a, &killmail, &character, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty_a);
        ts::return_shared(character);
        ts::return_shared(killmail);
    };

    // Verify SAME killmail on bounty B — should also succeed (by design)
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty_b = ts::take_shared_by_id<Bounty<SUI>>(&scenario, bounty_b_id);
        let character = ts::take_shared_by_id<Character>(&scenario, char_id);
        let killmail = ts::take_shared<Killmail>(&scenario);
        verify_kill::verify_kill(&mut bounty_b, &killmail, &character, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty_b);
        ts::return_shared(character);
        ts::return_shared(killmail);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12c: Front-run verify — attacker sees hunter's killmail, tries to
//      use it with hunter's character but as a different sender.
// DEFENSE: character_address == sender → e_character_mismatch
// =====================================================================
#[test, expected_failure(abort_code = 73)] // e_character_mismatch
fun red_team_round_12c_frontrun_verify_stolen_character() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);

    // Character owned by HUNTER
    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);
    setup_kill_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, ATTACKER, &clock); // attacker claims
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1);

    // Attacker sends tx using HUNTER's shared character
    ts::next_tx(&mut scenario, ATTACKER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let character = ts::take_shared_by_id<Character>(&scenario, char_id);
    let killmail = ts::take_shared<Killmail>(&scenario);
    // Attack: character.character_address() = HUNTER, but sender = ATTACKER → abort
    verify_kill::verify_kill(&mut bounty, &killmail, &character, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    ts::return_shared(character);
    ts::return_shared(killmail);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12d: Oracle admin impersonation — non-admin tries to register oracle
// DEFENSE: assert!(ctx.sender() == registry.admin) → e_not_registry_admin
// =====================================================================
#[test, expected_failure(abort_code = 74)] // e_not_registry_admin
fun red_team_round_12d_oracle_admin_impersonation_register() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    // Creator creates registry (becomes admin)
    ts::next_tx(&mut scenario, CREATOR);
    let registry = oracle::create_registry(&clock, ts::ctx(&mut scenario));
    oracle::share_registry_for_testing(registry);

    // Attacker tries to register oracle — not admin
    ts::next_tx(&mut scenario, ATTACKER);
    let mut registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
    let fake_pubkey = x"0000000000000000000000000000000000000000000000000000000000000001";
    oracle::register_oracle(
        &mut registry, ORACLE_ADDR, utf8(b"fake"), fake_pubkey,
        &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12e: Oracle admin impersonation — non-admin deactivates oracle
// DEFENSE: assert!(ctx.sender() == registry.admin) → e_not_registry_admin
// =====================================================================
#[test, expected_failure(abort_code = 74)] // e_not_registry_admin
fun red_team_round_12e_oracle_admin_impersonation_deactivate() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    // Creator creates registry + registers oracle
    ts::next_tx(&mut scenario, CREATOR);
    let mut registry = oracle::create_registry(&clock, ts::ctx(&mut scenario));
    let real_pubkey = x"0000000000000000000000000000000000000000000000000000000000000002";
    oracle::register_oracle(
        &mut registry, ORACLE_ADDR, utf8(b"real"), real_pubkey,
        &clock, ts::ctx(&mut scenario),
    );
    oracle::share_registry_for_testing(registry);

    // Attacker tries to deactivate — not admin
    ts::next_tx(&mut scenario, ATTACKER);
    let mut registry = ts::take_shared<oracle::OracleRegistry>(&scenario);
    oracle::deactivate_oracle(&mut registry, ORACLE_ADDR, ts::ctx(&mut scenario));
    ts::return_shared(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12f: Oracle double registration — re-register same oracle address
// DEFENSE: vec_map::contains check → e_oracle_already_registered
// =====================================================================
#[test, expected_failure(abort_code = 76)] // e_oracle_already_registered
fun red_team_round_12f_oracle_double_registration() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    ts::next_tx(&mut scenario, CREATOR);
    let mut registry = oracle::create_registry(&clock, ts::ctx(&mut scenario));
    let pubkey = x"0000000000000000000000000000000000000000000000000000000000000003";
    oracle::register_oracle(
        &mut registry, ORACLE_ADDR, utf8(b"oracle1"), pubkey,
        &clock, ts::ctx(&mut scenario),
    );
    // Try to register same address again — should fail
    let pubkey2 = x"0000000000000000000000000000000000000000000000000000000000000004";
    oracle::register_oracle(
        &mut registry, ORACLE_ADDR, utf8(b"oracle1-overwrite"), pubkey2,
        &clock, ts::ctx(&mut scenario),
    );
    oracle::share_registry_for_testing(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12g: Intel slot griefing — attacker is active hunter, posts garbage
//      payload to occupy singleton IntelConfigKey, blocking real hunter.
// BEHAVIOR: First hunter to post_intel wins the slot. This is BY DESIGN.
//           Second hunter gets e_intel_already_posted.
//           Attacker pays stake as deterrent. Test confirms griefing works
//           but costs attacker their stake.
// =====================================================================
#[test, expected_failure(abort_code = 83)] // e_intel_already_posted
fun red_team_round_12g_intel_slot_griefing() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    // Setup INTEL bounty
    setup_bounty(&mut scenario, &clock);
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_task_type(&mut bounty, constants::task_type_intel(), &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    // Both attacker and hunter claim
    hunter_claim(&mut scenario, ATTACKER, &clock);
    hunter_claim(&mut scenario, HUNTER, &clock);

    // Attacker posts garbage intel first — succeeds (by design)
    ts::next_tx(&mut scenario, ATTACKER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        intel_escrow::post_intel(&mut bounty, b"GARBAGE_ENCRYPTED_DATA", &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    // Real hunter tries to post — blocked by singleton slot
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        intel_escrow::post_intel(&mut bounty, b"REAL_VALUABLE_INTEL", &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12h: Non-creator tries to confirm intel — identity bypass attempt
// DEFENSE: assert!(caller == bounty::creator(bounty)) → e_not_intel_creator
// =====================================================================
#[test, expected_failure(abort_code = 85)] // e_not_intel_creator
fun red_team_round_12h_intel_non_creator_confirm() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_task_type(&mut bounty, constants::task_type_intel(), &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };
    hunter_claim(&mut scenario, HUNTER, &clock);

    // Hunter posts intel
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        intel_escrow::post_intel(&mut bounty, b"ENCRYPTED_INTEL", &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    // Attacker (not creator) tries to confirm
    ts::next_tx(&mut scenario, ATTACKER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    intel_escrow::confirm_intel(&mut bounty, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12i: Double confirm intel — creator confirms twice
// DEFENSE: assert!(!config.confirmed) → e_intel_already_confirmed
// =====================================================================
#[test, expected_failure(abort_code = 86)] // e_intel_already_confirmed
fun red_team_round_12i_intel_double_confirm() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_task_type(&mut bounty, constants::task_type_intel(), &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };
    hunter_claim(&mut scenario, HUNTER, &clock);

    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        intel_escrow::post_intel(&mut bounty, b"ENCRYPTED_INTEL", &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    // First confirm — succeeds
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        intel_escrow::confirm_intel(&mut bounty, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    // Second confirm — should fail
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    intel_escrow::confirm_intel(&mut bounty, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12j: Seal namespace bypass — id shorter than bounty_id bytes
// DEFENSE: assert!(id.length() >= bounty_id_len) → e_seal_namespace_too_short
// =====================================================================
#[test, expected_failure(abort_code = 91)] // e_seal_namespace_too_short
fun red_team_round_12j_seal_namespace_too_short() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_task_type(&mut bounty, constants::task_type_intel(), &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };
    hunter_claim(&mut scenario, HUNTER, &clock);

    // Hunter posts intel → creator gets ViewerReceipt
    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        intel_escrow::post_intel(&mut bounty, b"ENCRYPTED_INTEL", &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    // Attacker calls seal_approve with too-short id
    ts::next_tx(&mut scenario, CREATOR);
    let receipt = ts::take_from_sender<intel_escrow::ViewerReceipt>(&scenario);
    // Only 10 bytes — bounty ID is 32 bytes
    intel_escrow::seal_approve(x"00000000000000000000", &receipt);
    ts::return_to_sender(&scenario, receipt);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12k: Seal namespace byte mismatch — correct length, wrong prefix
// DEFENSE: byte-by-byte comparison → e_seal_namespace_mismatch
// =====================================================================
#[test, expected_failure(abort_code = 92)] // e_seal_namespace_mismatch
fun red_team_round_12k_seal_namespace_wrong_prefix() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    setup_bounty(&mut scenario, &clock);
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        task_type::set_task_type(&mut bounty, constants::task_type_intel(), &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };
    hunter_claim(&mut scenario, HUNTER, &clock);

    ts::next_tx(&mut scenario, HUNTER);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        intel_escrow::post_intel(&mut bounty, b"ENCRYPTED_INTEL", &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    ts::next_tx(&mut scenario, CREATOR);
    let receipt = ts::take_from_sender<intel_escrow::ViewerReceipt>(&scenario);
    // 32 bytes of 0xFF — almost certainly won't match any bounty_id
    let wrong_id = x"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF";
    intel_escrow::seal_approve(wrong_id, &receipt);
    ts::return_to_sender(&scenario, receipt);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =====================================================================
// 12l: Double auto-approve — verify_kill twice with different killmails,
//      second time hunter already approved.
// DEFENSE: auto_verify_approve checks !approved_hunters.contains → e_already_approved
// STRATEGY: Create second killmail AFTER first verify so only one
//           Killmail exists in scenario at a time (avoids take_shared ambiguity).
// =====================================================================
#[test, expected_failure(abort_code = 33)] // e_already_approved
fun red_team_round_12l_double_auto_approve() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);

    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);
    setup_kill_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, HUNTER, &clock);

    // Create first killmail only
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1);

    // First verify — succeeds (hunter gets auto-approved)
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

    // Create second killmail AFTER first verify (different item ID → no replay issue)
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID_2, KILLER_GAME_ID, NOW + 2);

    // Second verify with new killmail — passes replay check but hits already_approved
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
// 12m: Verify on cancelled bounty — cancel then try verify_kill
// DEFENSE: auto_verify_approve checks status == OPEN or CLAIMED → e_bounty_not_active
// =====================================================================
#[test, expected_failure(abort_code = 21)] // e_bounty_not_active
fun red_team_round_12m_verify_on_cancelled_bounty() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);
    test_helpers::setup_world(&mut scenario);

    let char_id = setup_character(&mut scenario, HUNTER, KILLER_GAME_ID as u32);
    setup_bounty(&mut scenario, &clock);
    setup_kill_task(&mut scenario, &clock);
    hunter_claim(&mut scenario, HUNTER, &clock);
    setup_killmail(&mut scenario, char_id, KILLMAIL_ITEM_ID, KILLER_GAME_ID, NOW + 1);

    // Creator cancels bounty
    ts::next_tx(&mut scenario, CREATOR);
    {
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        bounty::cancel(&mut bounty, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
    };

    // Hunter tries to verify after cancel
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
// 12n: Oracle pubkey injection — register with invalid pubkey length
// DEFENSE: assert!(pubkey.length() == 32) → e_invalid_attestation
// =====================================================================
#[test, expected_failure(abort_code = 77)] // e_invalid_attestation
fun red_team_round_12n_oracle_invalid_pubkey_length() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    ts::next_tx(&mut scenario, CREATOR);
    let mut registry = oracle::create_registry(&clock, ts::ctx(&mut scenario));
    // 16 bytes instead of 32
    let short_pubkey = x"00000000000000000000000000000001";
    oracle::register_oracle(
        &mut registry, ORACLE_ADDR, utf8(b"bad-key"), short_pubkey,
        &clock, ts::ctx(&mut scenario),
    );
    oracle::share_registry_for_testing(registry);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
