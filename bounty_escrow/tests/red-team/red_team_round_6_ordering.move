#[test_only]
module bounty_escrow::red_team_round_6_ordering;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER: address = @0xC;

// --- Attack 6a: Expire at exact boundary (now == deadline + grace_period) ---
// expire requires now > deadline + grace_period, so exactly equal should FAIL
#[test, expected_failure(abort_code = 20)] // e_grace_period_not_passed
fun red_team_round_6a_expire_exact_boundary() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;
    let grace = 86_400_000u64;

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Boundary".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        deadline, grace, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Set clock to exactly deadline + grace_period (NOT past it)
    clock::set_for_testing(&mut clock, deadline + grace);
    ts::next_tx(&mut scenario, @0xF);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 6b: Abandon at exact deadline (now == deadline) ---
// abandon requires now < deadline, so exactly equal should FAIL
#[test, expected_failure(abort_code = 30)] // e_abandon_after_deadline
fun red_team_round_6b_abandon_exact_deadline() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 1,
        deadline, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Hunter claims
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Set clock to exactly deadline
    clock::set_for_testing(&mut clock, deadline);
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 6c: Claim at exact deadline (now == deadline) ---
// claim requires now < deadline, so exactly equal should FAIL
#[test, expected_failure(abort_code = 10)] // e_deadline_passed
fun red_team_round_6c_claim_at_exact_deadline() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 1,
        deadline, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Try to claim at exact deadline
    clock::set_for_testing(&mut clock, deadline);
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 6d: Approve at exact grace boundary (now == deadline + grace) ---
// approve requires now <= deadline + grace_period, so exactly equal should SUCCEED
#[test]
fun red_team_round_6d_approve_at_exact_grace_boundary() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;
    let grace = 86_400_000u64;

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 1,
        deadline, grace, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Hunter claims before deadline
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Approve at exact deadline + grace (last possible moment)
    clock::set_for_testing(&mut clock, deadline + grace);
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 6e: Grace period = 0 → now blocked by min_grace_period validation ---
#[test, expected_failure(abort_code = 35)] // e_grace_period_too_short
fun red_team_round_6e_zero_grace_period() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"NoGrace".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        deadline, 0, 100, // grace_period = 0 → aborts with e_grace_period_too_short
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
