#[test_only]
module bounty_escrow::red_team_round_2_integer_abuse;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty;
use bounty_escrow::escrow;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;

// --- Attack 2a: Overflow in checked_mul (reward * max_claims > MAX_U64) ---
#[test, expected_failure(abort_code = 34)] // e_overflow
fun red_team_round_2a_checked_mul_overflow() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // reward_amount = MAX_U64 / 2 + 1, max_claims = 3 → overflows
    let huge_reward = 9_223_372_036_854_775_808; // 2^63
    let coin = coin::mint_for_testing<SUI>(18_446_744_073_709_551_615, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Overflow".to_string(), b"desc".to_string(), coin,
        huge_reward, 0, 3,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 2b: reward_amount = MAX_U64, max_claims = 1 → no overflow but huge coin needed ---
#[test]
fun red_team_round_2b_max_u64_reward_single_claim() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let max_u64 = 18_446_744_073_709_551_615;
    let coin = coin::mint_for_testing<SUI>(max_u64, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"MaxReward".to_string(), b"desc".to_string(), coin,
        max_u64, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 2c: cleanup_reward calculation with MAX_U64 escrow and max bps ---
#[test]
fun red_team_round_2c_cleanup_reward_max_values() {
    // max bps = 1000, max total = MAX_U64
    let max_u64 = 18_446_744_073_709_551_615;
    let result = escrow::calculate_cleanup_reward(max_u64, 1000);
    // Should be MAX_U64 * 1000 / 10000 = MAX_U64 / 10
    // Using u128 intermediate, this should not overflow
    assert!(result == 1_844_674_407_370_955_161);
}

// --- Attack 2d: Zero-value coin for creation (should fail) ---
#[test, expected_failure(abort_code = 23)] // e_reward_amount_zero
fun red_team_round_2d_zero_reward() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    let coin = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Zero".to_string(), b"desc".to_string(), coin,
        0, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 0,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
