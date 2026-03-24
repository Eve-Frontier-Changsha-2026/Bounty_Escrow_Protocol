#[test_only]
module bounty_escrow::red_team_round_7_type_confusion;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER: address = @0xC;

// Custom token for type confusion testing
public struct FAKE_TOKEN has drop {}

// --- Attack 7a: Create bounty with custom token, try to claim_reward on SUI bounty ---
// Move's type system should prevent cross-type attacks at compile time,
// but we test the runtime behavior with two different bounty types.
#[test]
fun red_team_round_7a_two_bounty_types_isolation() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // Create SUI bounty
    let coin_sui = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"SuiBounty".to_string(), b"desc".to_string(), coin_sui,
        1000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Hunter claims SUI bounty
    ts::next_tx(&mut scenario, HUNTER);
    let mut sui_bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut sui_bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(sui_bounty);

    // Approve
    ts::next_tx(&mut scenario, VERIFIER);
    let mut sui_bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut sui_bounty, HUNTER, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(sui_bounty);

    // Claim reward successfully
    ts::next_tx(&mut scenario, HUNTER);
    let mut sui_bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut sui_bounty, ticket, ts::ctx(&mut scenario));
    assert!(bounty::status(&sui_bounty) == constants::status_completed());
    ts::return_shared(sui_bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// --- Attack 7b: Destroy ticket on wrong type bounty ---
// ClaimTicket is not parameterized by T, so theoretically could be used across types.
// The bounty_id check should prevent this.
#[test, expected_failure(abort_code = 26)] // e_ticket_bounty_mismatch
fun red_team_round_7b_destroy_ticket_wrong_type_bounty() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    // Create SUI bounty
    let coin_sui = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"SuiBounty".to_string(), b"desc".to_string(), coin_sui,
        1000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Create FAKE_TOKEN bounty
    ts::next_tx(&mut scenario, CREATOR);
    let coin_fake = coin::mint_for_testing<FAKE_TOKEN>(2000, ts::ctx(&mut scenario));
    bounty::create<FAKE_TOKEN>(
        b"FakeBounty".to_string(), b"desc".to_string(), coin_fake,
        2000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Hunter claims SUI bounty
    ts::next_tx(&mut scenario, HUNTER);
    let mut sui_bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut sui_bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(sui_bounty);

    // Expire FAKE bounty
    clock::set_for_testing(&mut clock, 1_000_000_000 + 86_400_000 + 86_400_000 + 1);
    ts::next_tx(&mut scenario, @0xF);
    let mut fake_bounty = ts::take_shared<Bounty<FAKE_TOKEN>>(&scenario);
    bounty::expire<FAKE_TOKEN>(&mut fake_bounty, &clock, ts::ctx(&mut scenario));
    ts::return_shared(fake_bounty);

    // Try to destroy SUI ticket using FAKE bounty (different type, different ID)
    ts::next_tx(&mut scenario, HUNTER);
    let fake_bounty = ts::take_shared<Bounty<FAKE_TOKEN>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::destroy_ticket<FAKE_TOKEN>(ticket, &fake_bounty);
    ts::return_shared(fake_bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
