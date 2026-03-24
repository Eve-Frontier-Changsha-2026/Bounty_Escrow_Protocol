#[test_only]
module bounty_escrow::red_team_round_4_economic;

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

// --- Attack 4a: Cancel with required_stake=0 — hunters get zero penalty compensation ---
// This is a design-level concern: creator can lure hunters with no stake,
// let them do work, then cancel. Hunters lose work effort, get nothing.
#[test]
fun red_team_round_4a_cancel_zero_stake_no_penalty() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // Create bounty with required_stake=0
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"FreeStake".to_string(), b"desc".to_string(), coin,
        1000, 0, 1, // required_stake = 0
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Hunter claims (no stake needed)
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    assert!(bounty::active_claims(&bounty) == 1);
    ts::return_shared(bounty);

    // Creator cancels — penalty = required_stake * active_claims = 0
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));
    assert!(bounty::status(&bounty) == constants::status_cancelled());
    ts::return_shared(bounty);

    // Hunter withdraw_penalty — gets stake=0 + penalty=0 = nothing
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::withdraw_penalty<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));
    // Hunter got absolutely nothing for their work
    ts::return_shared(bounty);

    // Creator withdraws remaining — gets back full escrow
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::withdraw_remaining<SUI>(&mut bounty, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 4b: Abandon after approval — hunter loses stake AND reward ---
#[test]
fun red_team_round_4b_abandon_after_approval() {
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

    // Hunter claims
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Verifier approves
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // Hunter abandons AFTER approval — forfeits stake to creator
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));
    // Hunter lost: 100 stake (to creator) + 1000 reward opportunity
    // Escrow still holds 1000 (reward not released)
    assert!(bounty::escrow_value(&bounty) == 1000);
    assert!(bounty::active_claims(&bounty) == 0);
    // Status should be open (not completed, since no completions)
    assert!(bounty::status(&bounty) == constants::status_open());
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 4c: withdraw_remaining before all hunters withdraw_penalty ---
#[test, expected_failure(abort_code = 29)] // e_hunters_not_withdrawn
fun red_team_round_4c_withdraw_remaining_too_early() {
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

    // Hunter claims
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Creator cancels
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Creator tries to withdraw_remaining before hunter withdraws penalty
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::withdraw_remaining<SUI>(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 4d: Creator self-enrichment — cancel after approval, steal unclaimed rewards ---
// After cancel, approved hunters can only withdraw_penalty (stake + required_stake),
// NOT claim_reward. Creator then calls withdraw_remaining to recover full escrow minus penalties.
#[test]
fun red_team_round_4d_cancel_after_approval_creator_keeps_rewards() {
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

    // Hunter claims
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Verifier approves hunter
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // Creator cancels AFTER approval
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));
    assert!(bounty::status(&bounty) == constants::status_cancelled());
    ts::return_shared(bounty);

    // Hunter can only withdraw_penalty (not claim_reward since status is cancelled)
    ts::next_tx(&mut scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::withdraw_penalty<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));
    // Hunter gets: stake(100) + penalty(100) = 200 instead of stake(100) + reward(1000) = 1100
    ts::return_shared(bounty);

    // Creator withdraws remaining: escrow had 1000, paid 100 penalty → 900 left
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::withdraw_remaining<SUI>(&mut bounty, ts::ctx(&mut scenario));
    // Creator net: started with 1000 escrow, got back 900 + received 100 from abandon = 1000
    // Actually creator gets: 900 (remaining escrow) + 0 (stake pool empty, hunter got stake back)
    // Creator LOSES 100 (penalty) but SAVES 1000 (reward). Net profit: 900.
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
