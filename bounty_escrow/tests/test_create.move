#[test_only]
module bounty_escrow::test_create;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;

fun setup(scenario: &mut ts::Scenario): clock::Clock {
    let mut clock = clock::create_for_testing(ts::ctx(scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    clock
}

#[test]
fun test_create_success() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);

    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    let deadline = 1_000_000_000 + 86_400_000;
    bounty::create<SUI>(
        b"Kill pirate".to_string(),
        b"Destroy pirate ship in sector 7".to_string(),
        coin, 1000, 100, 5,
        deadline, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(bounty::status(&bounty) == constants::status_open());
    assert!(bounty::reward_amount(&bounty) == 1000);
    assert!(bounty::required_stake(&bounty) == 100);
    assert!(bounty::max_claims(&bounty) == 5);
    assert!(bounty::escrow_value(&bounty) == 5000);
    assert!(bounty::active_claims(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 5)]
fun test_create_empty_title() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"".to_string(), b"desc".to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 1)]
fun test_create_deadline_too_soon() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 1000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 0)]
fun test_create_insufficient_escrow() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 24)]
fun test_create_max_claims_too_high() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(101_000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 101, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 23)]
fun test_create_zero_reward() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        0, 100, 5, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 2)]
fun test_create_deadline_too_far() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 31_536_000_000 + 1, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 6)]
fun test_create_description_too_long() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    // Create a string > 2048 bytes
    let mut desc = vector<u8>[];
    let mut i = 0u64;
    while (i < 2049) {
        desc.push_back(120u8); // 'x'
        i = i + 1;
    };
    bounty::create<SUI>(
        b"Test".to_string(), desc.to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 3)]
fun test_create_bps_too_high() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 86_400_000, 86_400_000, 1001,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_create_change_returned() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = setup(&mut scenario);

    let coin = coin::mint_for_testing<SUI>(6000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(bounty::escrow_value(&bounty) == 5000);
    ts::return_shared(bounty);

    // Check change coin was returned
    let change = ts::take_from_sender<coin::Coin<SUI>>(&scenario);
    assert!(coin::value(&change) == 1000);
    ts::return_to_sender(&scenario, change);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
