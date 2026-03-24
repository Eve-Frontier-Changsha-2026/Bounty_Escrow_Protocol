#[test_only]
module bounty_escrow::red_team_round_3_object_manipulation;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER: address = @0xC;

// Custom token to avoid take_shared ambiguity with two Bounty<SUI>
public struct ALT_TOKEN has drop {}

// --- Attack 3a: Cross-bounty ticket — use ticket from SUI bounty on ALT bounty ---
#[test, expected_failure(abort_code = 26)] // e_ticket_bounty_mismatch
fun red_team_round_3a_cross_bounty_ticket_claim_reward() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // Create SUI bounty
    let coin1 = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"BountyA".to_string(), b"desc".to_string(), coin1,
        1000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Hunter claims SUI bounty (gets ticket with bounty A's ID)
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty_a = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty_a, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty_a);

    // Create ALT bounty (different type → unambiguous take_shared)
    ts::next_tx(&mut scenario, CREATOR);
    let coin2 = coin::mint_for_testing<ALT_TOKEN>(2000, ts::ctx(&mut scenario));
    bounty::create<ALT_TOKEN>(
        b"BountyB".to_string(), b"desc".to_string(), coin2,
        2000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Try to use SUI ticket on ALT bounty → bounty_id mismatch
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty_b = ts::take_shared<Bounty<ALT_TOKEN>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<ALT_TOKEN>(&mut bounty_b, ticket, ts::ctx(&mut scenario));
    ts::return_shared(bounty_b);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 3b: Cross-bounty ticket for abandon ---
#[test, expected_failure(abort_code = 26)] // e_ticket_bounty_mismatch
fun red_team_round_3b_cross_bounty_ticket_abandon() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // Create SUI bounty
    let coin1 = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"BountyA".to_string(), b"desc".to_string(), coin1,
        1000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Hunter claims SUI bounty
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty_a = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty_a, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty_a);

    // Create ALT bounty
    ts::next_tx(&mut scenario, CREATOR);
    let coin2 = coin::mint_for_testing<ALT_TOKEN>(2000, ts::ctx(&mut scenario));
    bounty::create<ALT_TOKEN>(
        b"BountyB".to_string(), b"desc".to_string(), coin2,
        2000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Try abandon on ALT bounty with SUI ticket
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty_b = ts::take_shared<Bounty<ALT_TOKEN>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<ALT_TOKEN>(&mut bounty_b, ticket, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty_b);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 3c: Cross-bounty ticket for withdraw_penalty ---
#[test, expected_failure(abort_code = 26)] // e_ticket_bounty_mismatch
fun red_team_round_3c_cross_bounty_ticket_withdraw_penalty() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // Create SUI bounty
    let coin1 = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"BountyA".to_string(), b"desc".to_string(), coin1,
        1000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Hunter claims SUI bounty
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty_a = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty_a, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty_a);

    // Create ALT bounty, have someone claim it, then cancel it
    ts::next_tx(&mut scenario, CREATOR);
    let coin2 = coin::mint_for_testing<ALT_TOKEN>(2000, ts::ctx(&mut scenario));
    bounty::create<ALT_TOKEN>(
        b"BountyB".to_string(), b"desc".to_string(), coin2,
        2000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, @0xE);
    let mut bounty_b = ts::take_shared<Bounty<ALT_TOKEN>>(&scenario);
    let stake2 = coin::mint_for_testing<ALT_TOKEN>(100, ts::ctx(&mut scenario));
    bounty::claim<ALT_TOKEN>(&mut bounty_b, stake2, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty_b);

    // Cancel ALT bounty
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty_b = ts::take_shared<Bounty<ALT_TOKEN>>(&scenario);
    bounty::cancel<ALT_TOKEN>(&mut bounty_b, ts::ctx(&mut scenario));
    ts::return_shared(bounty_b);

    // Hunter tries withdraw_penalty on cancelled ALT bounty with SUI ticket
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty_b = ts::take_shared<Bounty<ALT_TOKEN>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::withdraw_penalty<ALT_TOKEN>(&mut bounty_b, ticket, ts::ctx(&mut scenario));
    ts::return_shared(bounty_b);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
