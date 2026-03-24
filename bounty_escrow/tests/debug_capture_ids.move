#[test_only]
/// Temporary debug test to capture deterministic object IDs for test vector generation.
/// Delete after generating vectors.
module bounty_escrow::debug_capture_ids;

use std::string::utf8;
use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};

const CREATOR: address = @0xCA;
const HUNTER: address = @0xBB;
const VERIFIER: address = @0xDD;

const NOW: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

/// Captures bounty ID for DELIVERY test setup (simple, no world).
#[test]
fun debug_delivery_bounty_id() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    // Same as test_verify_delivery::setup_bounty
    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        utf8(b"Deliver items"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let id = object::id_address(&bounty);
    std::debug::print(&id);
    std::debug::print(&utf8(b"^^^ DELIVERY BOUNTY ID ^^^"));
    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

/// Captures bounty ID for BUILD test setup (after full world setup).
/// Must match the exact setup sequence in test_verify_build.
#[test]
fun debug_build_bounty_id() {
    use world::assembly::{Self, Assembly};
    use world::character::{Self, Character};
    use world::network_node::{Self, NetworkNode};
    use world::object_registry::ObjectRegistry;
    use world::access::AdminACL;
    use world::test_helpers::{Self, admin, tenant};

    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, NOW);

    // World setup (same as test_verify_build::full_world_setup)
    test_helpers::setup_world(&mut scenario);
    test_helpers::configure_fuel(&mut scenario);
    test_helpers::configure_assembly_energy(&mut scenario);

    // Character
    let char_id = {
        ts::next_tx(&mut scenario, admin());
        let mut registry = ts::take_shared<ObjectRegistry>(&scenario);
        let admin_acl = ts::take_shared<AdminACL>(&scenario);
        let character = character::create_character(
            &mut registry, &admin_acl,
            5001u32, tenant(), 100, HUNTER, utf8(b"hunter"), ts::ctx(&mut scenario),
        );
        let id = object::id(&character);
        character::share_character(character, &admin_acl, ts::ctx(&mut scenario));
        ts::return_shared(registry);
        ts::return_shared(admin_acl);
        id
    };

    // NetworkNode
    let nwn_id = {
        ts::next_tx(&mut scenario, admin());
        let mut registry = ts::take_shared<ObjectRegistry>(&scenario);
        let character = ts::take_shared_by_id<Character>(&scenario, char_id);
        let admin_acl = ts::take_shared<AdminACL>(&scenario);
        let nwn = network_node::anchor(
            &mut registry, &character, &admin_acl,
            5000u64, 111000u64,
            x"7a8f3b2e9c4d1a6f5e8b2d9c3f7a1e5b7a8f3b2e9c4d1a6f5e8b2d9c3f7a1e5b",
            1000, 3_600_000, 100, ts::ctx(&mut scenario),
        );
        let id = object::id(&nwn);
        nwn.share_network_node(&admin_acl, ts::ctx(&mut scenario));
        ts::return_shared(character);
        ts::return_shared(admin_acl);
        ts::return_shared(registry);
        id
    };

    // Assembly
    let assembly_id = {
        ts::next_tx(&mut scenario, admin());
        let character = ts::take_shared_by_id<Character>(&scenario, char_id);
        let mut registry = ts::take_shared<ObjectRegistry>(&scenario);
        let mut nwn = ts::take_shared_by_id<NetworkNode>(&scenario, nwn_id);
        let admin_acl = ts::take_shared<AdminACL>(&scenario);
        let assembly = assembly::anchor(
            &mut registry, &mut nwn, &character, &admin_acl,
            1001u64, 8888u64,
            x"7a8f3b2e9c4d1a6f5e8b2d9c3f7a1e5b7a8f3b2e9c4d1a6f5e8b2d9c3f7a1e5b",
            ts::ctx(&mut scenario),
        );
        let id = object::id(&assembly);
        assembly.share_assembly(&admin_acl, ts::ctx(&mut scenario));
        ts::return_shared(character);
        ts::return_shared(admin_acl);
        ts::return_shared(registry);
        ts::return_shared(nwn);
        id
    };

    // Bounty (same as test_verify_build::setup_bounty)
    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        utf8(b"Build assembly"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let bounty_addr = object::id_address(&bounty);
    std::debug::print(&bounty_addr);
    std::debug::print(&utf8(b"^^^ BUILD BOUNTY ID ^^^"));

    let assembly = ts::take_shared_by_id<Assembly>(&scenario, assembly_id);
    let asm_addr = object::id_address(&assembly);
    std::debug::print(&asm_addr);
    std::debug::print(&utf8(b"^^^ BUILD ASSEMBLY ID ^^^"));

    ts::return_shared(bounty);
    ts::return_shared(assembly);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
