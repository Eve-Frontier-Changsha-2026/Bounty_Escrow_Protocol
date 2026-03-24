#[test_only]
module bounty_escrow::test_abandon;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER1: address = @0xC;
const HUNTER2: address = @0xD;

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

fun setup_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock, max_claims: u64): Bounty<SUI> {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Kill pirate".to_string(),
        b"Destroy pirate ship".to_string(),
        coin, 1000, 100, max_claims,
        DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
    ts::next_tx(scenario, CREATOR);
    ts::take_shared<Bounty<SUI>>(scenario)
}

#[test]
fun test_abandon_success() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 5);

    // HUNTER1 claims
    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    let before_stake = bounty::stake_pool_value(&bounty);
    let before_claims = bounty::active_claims(&bounty);

    // HUNTER1 abandons
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER1);
    // active_claims reduced by 1
    assert!(bounty::active_claims(&bounty) == before_claims - 1);
    // stake_pool decreases (stake sent to creator)
    assert!(bounty::stake_pool_value(&bounty) == before_stake - 100);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_abandon_reopens_claimed() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // max=1 so after claim status=Claimed
    let mut bounty = setup_bounty(&mut scenario, &clock, 1);

    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    // Verify status is Claimed
    assert!(bounty::status(&bounty) == constants::status_claimed());

    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER1);
    // After abandon, active_claims < max_claims, status reopens
    assert!(bounty::status(&bounty) == constants::status_open());
    assert!(bounty::active_claims(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 30)]
fun test_abandon_after_deadline_fails() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_bounty(&mut scenario, &clock, 5);

    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    // Advance past deadline
    clock::set_for_testing(&mut clock, DEADLINE + 1);

    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    // e_abandon_after_deadline (30)
    bounty::abandon<SUI>(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 26)]
fun test_abandon_wrong_bounty_fails() {
    // Create two bounties; HUNTER1 claims bounty A, then tries to use ticket on bounty B
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // Create bounty A
    ts::next_tx(&mut scenario, CREATOR);
    let coin_a = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Bounty A".to_string(), b"desc A".to_string(),
        coin_a, 1000, 100, 1,
        DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Create bounty B
    ts::next_tx(&mut scenario, CREATOR);
    let coin_b = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Bounty B".to_string(), b"desc B".to_string(),
        coin_b, 1000, 100, 1,
        DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Take the two bounties (order: most recently shared = B, then A)
    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty_b = ts::take_shared<Bounty<SUI>>(&scenario);
    let mut bounty_a = ts::take_shared<Bounty<SUI>>(&scenario);

    // Claim bounty A
    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty_a, stake, &clock, ts::ctx(&mut scenario));

    // Try to abandon with ticket from A on bounty B -> e_ticket_bounty_mismatch (26)
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty_b, ticket, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty_a);
    ts::return_shared(bounty_b);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
