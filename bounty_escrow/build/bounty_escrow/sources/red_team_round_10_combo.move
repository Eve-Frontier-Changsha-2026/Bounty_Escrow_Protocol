#[test_only]
module bounty_escrow::red_team_round_10_combo;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER1: address = @0xC;
const HUNTER2: address = @0xD;

// --- Attack 10a: Cancel already-cancelled bounty ---
#[test, expected_failure(abort_code = 14)] // e_bounty_not_cancellable
fun red_team_round_10a_double_cancel() {
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

    // Cancel once
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Try cancel again
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 10b: Expire already-expired bounty ---
#[test, expected_failure(abort_code = 21)] // e_bounty_not_active
fun red_team_round_10b_double_expire() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;
    let grace = 86_400_000u64;

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        deadline, grace, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::set_for_testing(&mut clock, deadline + grace + 1);
    ts::next_tx(&mut scenario, @0xF);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Try expire again
    ts::next_tx(&mut scenario, @0xF);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 10c: Cancel expired bounty ---
#[test, expected_failure(abort_code = 14)] // e_bounty_not_cancellable
fun red_team_round_10c_cancel_expired() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;
    let grace = 86_400_000u64;

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        deadline, grace, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::set_for_testing(&mut clock, deadline + grace + 1);
    ts::next_tx(&mut scenario, @0xF);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Creator tries to cancel expired bounty
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 10d: Creator self-claims own bounty ---
#[test, expected_failure(abort_code = 11)] // e_creator_cannot_claim
fun red_team_round_10d_creator_self_claim() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"SelfClaim".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Creator tries to claim own bounty
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 10e: claim_reward on completed bounty (no more escrow) ---
// After all rewards distributed, try to somehow get more
#[test]
fun red_team_round_10e_completed_bounty_escrow_drained() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Multi".to_string(), b"desc".to_string(), coin,
        1000, 100, 2,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Both hunters claim
    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let s1 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, s1, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    ts::next_tx(&mut scenario, HUNTER2);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let s2 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, s2, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Approve both
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    bounty::approve<SUI>(&mut bounty, HUNTER2, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // Hunter1 claims reward
    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket1 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket1, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 1000); // 2000 - 1000
    assert!(bounty::active_claims(&bounty) == 1);
    ts::return_shared(bounty);

    // Hunter2 claims reward
    ts::next_tx(&mut scenario, HUNTER2);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket2 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket2, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 0); // fully drained
    assert!(bounty::stake_pool_value(&bounty) == 0); // all stakes returned
    assert!(bounty::active_claims(&bounty) == 0);
    assert!(bounty::status(&bounty) == constants::status_completed());
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
