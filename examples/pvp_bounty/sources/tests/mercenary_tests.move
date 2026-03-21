#[test_only]
module pvp_bounty::mercenary_tests;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;
use pvp_bounty::mercenary;

const COMMANDER: address = @0xA;
const BATTLE_JUDGE: address = @0xB;
const MERC1: address = @0xC;

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;

#[test]
fun test_pvp_happy_path() {
    let mut scenario = ts::begin(COMMANDER);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // 1. Commander issues kill order (reward=1000, stake=100 i.e. 10%)
    ts::next_tx(&mut scenario, COMMANDER);
    // Total escrow = 1000 * 3 mercs = 3000
    let payment = coin::mint_for_testing<SUI>(3000, ts::ctx(&mut scenario));
    let change = mercenary::issue_kill_order(
        b"Kill Order: Pirate Lord Zephyr".to_string(),
        b"Eliminate target in Sector K-9".to_string(),
        payment,
        1000,
        DEADLINE,
        BATTLE_JUDGE,
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // 2. Mercenary accepts (needs 100 stake = 1000 * 10%)
    //    Use non-composable variant so ticket is auto-transferred to MERC1
    ts::next_tx(&mut scenario, MERC1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(mercenary::kill_order_stake(&bounty) == 100);

    let stake_coin = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    mercenary::accept_kill_order_and_keep(
        &mut bounty, stake_coin, &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);

    // 3. Battle Judge verifies the kill
    ts::next_tx(&mut scenario, BATTLE_JUDGE);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    mercenary::verify_kill(&mut bounty, MERC1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // 4. Mercenary collects bounty
    ts::next_tx(&mut scenario, MERC1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    mercenary::collect_bounty(&mut bounty, ticket, ts::ctx(&mut scenario));

    // Verify: 2000 escrow left (2 remaining merc slots), stake pool drained for merc1
    assert!(bounty::escrow_value(&bounty) == 2000);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_pvp_abandon() {
    let mut scenario = ts::begin(COMMANDER);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // Commander issues kill order
    ts::next_tx(&mut scenario, COMMANDER);
    let payment = coin::mint_for_testing<SUI>(3000, ts::ctx(&mut scenario));
    let change = mercenary::issue_kill_order(
        b"Kill Order: Rogue Captain".to_string(),
        b"Eliminate target".to_string(),
        payment,
        1000,
        DEADLINE,
        BATTLE_JUDGE,
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // Mercenary accepts — use composable variant, desert in same tx
    ts::next_tx(&mut scenario, MERC1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake_coin = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    let (ticket, stake_change) = mercenary::accept_kill_order(
        &mut bounty, stake_coin, &clock, ts::ctx(&mut scenario),
    );
    coin::destroy_zero(stake_change);

    // Mercenary deserts — stake forfeited to commander
    mercenary::desert(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));

    // Verify: stake pool drained (forfeited to commander), status back to open
    assert!(mercenary::kill_order_status(&bounty) == constants::status_open());
    assert!(bounty::active_claims(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
