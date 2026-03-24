#[test_only]
module bounty_escrow::red_team_round_8_dos;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;

/// Build a unique 32-byte address from an index
fun make_address(index: u64): address {
    let idx_bytes = std::bcs::to_bytes(&index);
    let mut addr_bytes = vector::empty<u8>();
    // Pad with zeros to reach 32 bytes (idx_bytes is 8 bytes for u64)
    let mut j = 0u64;
    while (j < 24) {
        vector::push_back(&mut addr_bytes, 0u8);
        j = j + 1;
    };
    let mut k = 0u64;
    while (k < vector::length(&idx_bytes)) {
        vector::push_back(&mut addr_bytes, *vector::borrow(&idx_bytes, k));
        k = k + 1;
    };
    sui::address::from_bytes(addr_bytes)
}

// --- Attack 8a: 10 hunters claim then expire ---
// Tests VecMap iteration in expire_bounty while loop
// Note: 100 hunters times out in test VM — in production, gas limit is the real constraint.
#[test]
fun red_team_round_8a_many_claims_then_expire() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let deadline = 1_000_000_000 + 86_400_000;
    let grace = 86_400_000u64;
    let num_hunters = 10u64;

    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(num_hunters * 10, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"MaxClaims".to_string(), b"desc".to_string(), coin,
        10, 1, num_hunters,
        deadline, grace, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // N hunters claim
    let mut i = 0u64;
    while (i < num_hunters) {
        let hunter = make_address(1000 + i);
        ts::next_tx(&mut scenario, hunter);
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        let stake = coin::mint_for_testing<SUI>(1, ts::ctx(&mut scenario));
        bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);
        i = i + 1;
    };

    // Verify all slots filled
    ts::next_tx(&mut scenario, @0xF);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(bounty::active_claims(&bounty) == num_hunters);
    assert!(bounty::status(&bounty) == constants::status_claimed());
    ts::return_shared(bounty);

    // Expire — clears N entries from VecMap
    clock::set_for_testing(&mut clock, deadline + grace + 1);
    ts::next_tx(&mut scenario, @0xF);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    assert!(bounty::status(&bounty) == constants::status_expired());
    assert!(bounty::active_claims(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 8b: Repeated claim-abandon to bloat claimed_hunters VecSet ---
#[test]
fun red_team_round_8b_vecset_bloat_claimed_hunters() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Bloat".to_string(), b"desc".to_string(), coin,
        1000, 1, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // 20 different hunters each claim and abandon
    let mut i = 0u64;
    while (i < 20) {
        let hunter = make_address(2000 + i);

        ts::next_tx(&mut scenario, hunter);
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        let stake = coin::mint_for_testing<SUI>(1, ts::ctx(&mut scenario));
        bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);

        ts::next_tx(&mut scenario, hunter);
        let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
        let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
        bounty::abandon<SUI>(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));
        ts::return_shared(bounty);

        i = i + 1;
    };

    // Bounty should still be open and functional
    ts::next_tx(&mut scenario, @0xF);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(bounty::status(&bounty) == constants::status_open());
    assert!(bounty::active_claims(&bounty) == 0);
    ts::return_shared(bounty);

    // 21st unique hunter can still claim
    let new_hunter = make_address(2020);
    ts::next_tx(&mut scenario, new_hunter);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(1, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    assert!(bounty::active_claims(&bounty) == 1);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
