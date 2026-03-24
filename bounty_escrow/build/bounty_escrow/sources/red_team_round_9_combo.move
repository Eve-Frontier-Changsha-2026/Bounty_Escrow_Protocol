#[test_only]
module bounty_escrow::red_team_round_9_combo;

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

// --- Attack 9a: Grace period = 0 + claim race ---
// Creator sets grace=0. Hunter claims, does work. Deadline passes.
// Verifier has NO grace period to approve. Anyone can expire immediately.
// Hunter stuck: grace_period=0 now blocked at creation by min_grace_period.
// This attack vector is eliminated — creation aborts.
#[test, expected_failure(abort_code = 35)] // e_grace_period_too_short
fun red_team_round_9a_zero_grace_traps_hunter() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"ZeroGrace".to_string(), b"desc".to_string(), coin,
        1000, 500, 1,
        deadline, 0, 100, // grace_period = 0 → aborts with e_grace_period_too_short
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 9b: Multi-hunter partial completion → status edge case ---
// max_claims=2: Hunter1 approved+claimed reward, Hunter2 still active.
// What's the bounty status? Should NOT be completed (active_claims > 0).
#[test]
fun red_team_round_9b_partial_completion_status() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;

    let coin = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Multi".to_string(), b"desc".to_string(), coin,
        1000, 100, 2,
        deadline, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Both hunters claim
    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake1 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake1, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    ts::next_tx(&mut scenario, HUNTER2);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake2 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake2, &clock, ts::ctx(&mut scenario));
    assert!(bounty::status(&bounty) == constants::status_claimed()); // both slots filled
    ts::return_shared(bounty);

    // Approve and reward hunter1
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));
    // After hunter1 completes: active=1, completed=1, status should revert to OPEN
    assert!(bounty::active_claims(&bounty) == 1);
    assert!(bounty::completed_claims(&bounty) == 1);
    assert!(bounty::status(&bounty) == constants::status_open()); // reopened!
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 9c: Double approve attempt ---
#[test, expected_failure(abort_code = 33)] // e_already_approved
fun red_team_round_9c_double_approve() {
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

    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Approve once
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));

    // Try approve again
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
