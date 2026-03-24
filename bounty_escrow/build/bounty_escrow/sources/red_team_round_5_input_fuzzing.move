#[test_only]
module bounty_escrow::red_team_round_5_input_fuzzing;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty;
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;

// --- Attack 5a: Title at exact max length (256 bytes) — should succeed ---
#[test]
fun red_team_round_5a_max_title_length() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // 256-byte title
    let mut title_bytes = vector::empty<u8>();
    let mut i = 0u64;
    while (i < 256) {
        vector::push_back(&mut title_bytes, b"A"[0]);
        i = i + 1;
    };

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        std::string::utf8(title_bytes), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 5b: Title exceeds max (257 bytes) — should abort ---
#[test, expected_failure(abort_code = 4)] // e_title_too_long
fun red_team_round_5b_title_too_long() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // 257-byte title
    let mut title_bytes = vector::empty<u8>();
    let mut i = 0u64;
    while (i < 257) {
        vector::push_back(&mut title_bytes, b"A"[0]);
        i = i + 1;
    };

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        std::string::utf8(title_bytes), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 5c: Empty title — should abort ---
#[test, expected_failure(abort_code = 5)] // e_title_empty
fun red_team_round_5c_empty_title() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 5d: Description at exact max (2048 bytes) — should succeed ---
#[test]
fun red_team_round_5d_max_description_length() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let mut desc_bytes = vector::empty<u8>();
    let mut i = 0u64;
    while (i < 2048) {
        vector::push_back(&mut desc_bytes, b"B"[0]);
        i = i + 1;
    };

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), std::string::utf8(desc_bytes), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 5e: Description exceeds max (2049 bytes) — should abort ---
#[test, expected_failure(abort_code = 6)] // e_description_too_long
fun red_team_round_5e_description_too_long() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let mut desc_bytes = vector::empty<u8>();
    let mut i = 0u64;
    while (i < 2049) {
        vector::push_back(&mut desc_bytes, b"B"[0]);
        i = i + 1;
    };

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), std::string::utf8(desc_bytes), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 5f: max_claims = 0 ---
#[test, expected_failure(abort_code = 22)] // e_max_claims_zero
fun red_team_round_5f_zero_max_claims() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 0, 0,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 5g: max_claims = 101 (exceeds max) ---
#[test, expected_failure(abort_code = 24)] // e_max_claims_too_high
fun red_team_round_5g_max_claims_exceeded() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(101_000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 0, 101,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 5h: cleanup_bps = 1001 (exceeds max 1000) ---
#[test, expected_failure(abort_code = 3)] // e_cleanup_bps_too_high
fun red_team_round_5h_cleanup_bps_exceeded() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 1001,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
