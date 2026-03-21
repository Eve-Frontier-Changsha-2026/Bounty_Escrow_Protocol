#[test_only]
module logistics_bounty::logistics_tests;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;
use logistics_bounty::logistics;

const DAO: address = @0xA;          // creator + verifier (multi-sig)
const RUNNER: address = @0xC;

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;

#[test]
fun test_logistics_happy_path() {
    let mut scenario = ts::begin(DAO);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // 1. DAO posts logistics task (reward=2000, deposit=500)
    ts::next_tx(&mut scenario, DAO);
    let treasury = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    let change = logistics::post_logistics_task(
        b"Supply Run: Outpost Gamma".to_string(),
        b"Deliver 500 fuel cells".to_string(),
        treasury,
        2000,       // reward
        500,        // security deposit
        DEADLINE,
        DAO,        // DAO is also verifier
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // 2. Runner accepts with deposit (ticket auto-transferred to RUNNER)
    ts::next_tx(&mut scenario, RUNNER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let deposit = coin::mint_for_testing<SUI>(500, ts::ctx(&mut scenario));
    logistics::accept_logistics_task(
        &mut bounty, deposit, &clock, ts::ctx(&mut scenario),
    );

    assert!(logistics::task_status(&bounty) == constants::status_claimed());
    assert!(bounty::stake_pool_value(&bounty) == 500);
    ts::return_shared(bounty);

    // 3. DAO approves delivery
    ts::next_tx(&mut scenario, DAO);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    logistics::approve_delivery(&mut bounty, RUNNER, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // 4. Runner collects payment
    ts::next_tx(&mut scenario, RUNNER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    logistics::collect_payment(&mut bounty, ticket, ts::ctx(&mut scenario));

    assert!(logistics::task_status(&bounty) == constants::status_completed());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_logistics_cancel_withdraw() {
    let mut scenario = ts::begin(DAO);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // DAO posts task
    ts::next_tx(&mut scenario, DAO);
    let treasury = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    let change = logistics::post_logistics_task(
        b"Repair: Station Delta".to_string(),
        b"Fix hull breach".to_string(),
        treasury,
        2000,
        500,
        DEADLINE,
        DAO,
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // Runner accepts (ticket auto-transferred to RUNNER)
    ts::next_tx(&mut scenario, RUNNER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let deposit = coin::mint_for_testing<SUI>(500, ts::ctx(&mut scenario));
    logistics::accept_logistics_task(
        &mut bounty, deposit, &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);

    // DAO cancels task (runner has claimed → withdrawal pattern)
    ts::next_tx(&mut scenario, DAO);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    logistics::cancel_task(&mut bounty, ts::ctx(&mut scenario));
    assert!(logistics::task_status(&bounty) == constants::status_cancelled());
    ts::return_shared(bounty);

    // Runner withdraws deposit + penalty compensation
    ts::next_tx(&mut scenario, RUNNER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    logistics::runner_withdraw(&mut bounty, ticket, ts::ctx(&mut scenario));
    assert!(bounty::active_claims(&bounty) == 0);
    ts::return_shared(bounty);

    // DAO withdraws remaining
    ts::next_tx(&mut scenario, DAO);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    logistics::dao_withdraw_remaining(&mut bounty, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
