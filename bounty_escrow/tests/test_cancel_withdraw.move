#[test_only]
module bounty_escrow::test_cancel_withdraw;

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

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

fun setup_bounty(
    scenario: &mut ts::Scenario,
    clock: &clock::Clock,
    reward: u64,
    stake: u64,
    max_claims: u64,
): Bounty<SUI> {
    ts::next_tx(scenario, CREATOR);
    let total = reward * max_claims;
    let coin = coin::mint_for_testing<SUI>(total, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Kill pirate".to_string(),
        b"Destroy pirate ship".to_string(),
        coin, reward, stake, max_claims,
        DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
    ts::next_tx(scenario, CREATOR);
    ts::take_shared<Bounty<SUI>>(scenario)
}

#[test]
fun test_cancel_no_claims() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 1000, 100, 1);

    // Cancel with no active claims
    ts::next_tx(&mut scenario, CREATOR);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, CREATOR);
    assert!(bounty::status(&bounty) == constants::status_cancelled());
    // Escrow should be 0 (returned to creator)
    assert!(bounty::escrow_value(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_cancel_with_claims_full_flow() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 1000, 100, 2);

    // HUNTER1 claims
    ts::next_tx(&mut scenario, HUNTER1);
    let stake1 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake1, &clock, ts::ctx(&mut scenario));

    // Creator cancels
    ts::next_tx(&mut scenario, CREATOR);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));

    assert!(bounty::status(&bounty) == constants::status_cancelled());

    // HUNTER1 withdraws penalty
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::withdraw_penalty<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER1);
    assert!(bounty::active_claims(&bounty) == 0);

    // Creator withdraws remaining
    ts::next_tx(&mut scenario, CREATOR);
    bounty::withdraw_remaining<SUI>(&mut bounty, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, CREATOR);
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 13)]
fun test_cancel_non_creator_fails() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 1000, 100, 1);

    ts::next_tx(&mut scenario, HUNTER1);
    // HUNTER1 tries to cancel -> e_not_creator (13)
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 15)]
fun test_cancel_insufficient_escrow_for_penalty() {
    // create(reward=1000, stake=2000, max=2) -> 2 claims -> approve+claim_reward for one
    // escrow: 2000 -> after claim_reward: 1000 remains; 1 active claim
    // cancel needs penalty=2000 for 1 remaining but escrow=1000 -> abort
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 1000, 2000, 2);

    // HUNTER1 claims
    ts::next_tx(&mut scenario, HUNTER1);
    let stake1 = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake1, &clock, ts::ctx(&mut scenario));

    // HUNTER2 claims
    ts::next_tx(&mut scenario, HUNTER2);
    let stake2 = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake2, &clock, ts::ctx(&mut scenario));

    // Approve HUNTER1
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);

    // HUNTER1 claims reward (escrow goes from 2000 to 1000)
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket1 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket1, ts::ctx(&mut scenario));

    // Now escrow=1000, active_claims=1 (HUNTER2), required_stake=2000
    // Cancel needs penalty=2000 but escrow=1000 -> e_insufficient_escrow_for_penalty (15)
    ts::next_tx(&mut scenario, CREATOR);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 29)]
fun test_withdraw_remaining_before_all_hunters_fails() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 1000, 100, 2);

    // 2 hunters claim
    ts::next_tx(&mut scenario, HUNTER1);
    let stake1 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake1, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER2);
    let stake2 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake2, &clock, ts::ctx(&mut scenario));

    // Creator cancels
    ts::next_tx(&mut scenario, CREATOR);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));

    // Only HUNTER1 withdraws penalty
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket1 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::withdraw_penalty<SUI>(&mut bounty, ticket1, ts::ctx(&mut scenario));

    // Creator tries withdraw_remaining before HUNTER2 withdraws -> e_hunters_not_withdrawn (29)
    ts::next_tx(&mut scenario, CREATOR);
    bounty::withdraw_remaining<SUI>(&mut bounty, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 14)]
fun test_double_cancel_fails() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 1000, 100, 1);

    ts::next_tx(&mut scenario, CREATOR);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, CREATOR);
    // Second cancel -> e_bounty_not_cancellable (14)
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 28)]
fun test_withdraw_penalty_not_cancelled_fails() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 1000, 100, 1);

    // HUNTER1 claims (bounty is Open)
    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    // HUNTER1 tries withdraw_penalty on a non-cancelled bounty -> e_bounty_not_cancelled (28)
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::withdraw_penalty<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
