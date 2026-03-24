#[test_only]
module bounty_escrow::red_team_round_1_access_control;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::verifier::VerifierCap;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER: address = @0xC;
const ATTACKER: address = @0xD;

public struct ALT_TOKEN has drop {}

// --- Attack 1a: Non-creator tries to cancel bounty ---
#[test, expected_failure(abort_code = 13)] // e_not_creator
fun red_team_round_1a_non_creator_cancel() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Attacker tries to cancel
    ts::next_tx(&mut scenario, ATTACKER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 1b: Stolen ticket is STRUCTURALLY PREVENTED ---
// ClaimTicket has `key` but NOT `store` → `public_transfer` fails at compile time.
// Tickets are soulbound. No runtime test needed — this is a compile-time defense.

// --- Attack 1c: Wrong VerifierCap for different bounty ---
// Uses ALT_TOKEN for bounty B to avoid take_shared ambiguity
#[test, expected_failure(abort_code = 16)] // e_invalid_verifier_cap
fun red_team_round_1c_wrong_verifier_cap() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // Create SUI bounty (verifier = VERIFIER)
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"BountyA".to_string(), b"desc".to_string(), coin,
        1000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Create ALT bounty (verifier = @0xE)
    ts::next_tx(&mut scenario, CREATOR);
    let coin2 = coin::mint_for_testing<ALT_TOKEN>(2000, ts::ctx(&mut scenario));
    bounty::create<ALT_TOKEN>(
        b"BountyB".to_string(), b"desc".to_string(), coin2,
        2000, 200, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        @0xE,
        &clock, ts::ctx(&mut scenario),
    );

    // Hunter claims SUI bounty
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty_a = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty_a, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty_a);

    // @0xE tries to approve hunter on SUI bounty using ALT bounty's cap
    ts::next_tx(&mut scenario, @0xE);
    let mut bounty_a = ts::take_shared<Bounty<SUI>>(&scenario);
    let wrong_cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty_a, HUNTER, &wrong_cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, wrong_cap);
    ts::return_shared(bounty_a);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 1d: Non-creator tries to withdraw_remaining ---
#[test, expected_failure(abort_code = 13)] // e_not_creator
fun red_team_round_1d_non_creator_withdraw_remaining() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Creator cancels (no active claims)
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Attacker tries to withdraw remaining
    ts::next_tx(&mut scenario, ATTACKER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::withdraw_remaining<SUI>(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
