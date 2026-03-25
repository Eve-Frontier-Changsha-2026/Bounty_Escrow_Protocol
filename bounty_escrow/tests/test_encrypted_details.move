#[test_only]
module bounty_escrow::test_encrypted_details;

use std::string::utf8;
use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::encrypted_details::{Self, BountyViewerReceipt};
use bounty_escrow::constants;

const CREATOR: address = @0xCA;
const HUNTER: address = @0xBB;
const VERIFIER: address = @0xDD;
const RANDOM_USER: address = @0xFF;

const NOW: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;
const GRACE: u64 = 86_400_000;

// ─── Helpers ───

fun setup_clock(scenario: &mut ts::Scenario): clock::Clock {
    let mut clock = clock::create_for_testing(ts::ctx(scenario));
    clock::set_for_testing(&mut clock, NOW);
    clock
}

fun setup_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(scenario));
    bounty::create<SUI>(
        utf8(b"Test bounty"), utf8(b"desc"), coin,
        1000, 100, 5, DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
}

fun hunter_claim(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    ts::next_tx(scenario, HUNTER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(scenario));
    bounty::claim(&mut bounty, stake, clock, ts::ctx(scenario));
    ts::return_shared(bounty);
}

fun make_payload(size: u64): vector<u8> {
    let mut v = vector[];
    let mut i = 0;
    while (i < size) {
        v.push_back(0xAB);
        i = i + 1;
    };
    v
}

// ─── Happy Paths ───

#[test]
fun test_set_encrypted_details_happy_path() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);

    // Creator sets encrypted details
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let payload = b"encrypted_secret_data";
    encrypted_details::set_encrypted_details(&mut bounty, payload, &clock, ts::ctx(&mut scenario));

    assert!(encrypted_details::has_encrypted_details(&bounty) == true);
    assert!(*encrypted_details::get_encrypted_payload(&bounty) == payload);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_set_encrypted_details_max_size() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let payload = make_payload(4096);
    encrypted_details::set_encrypted_details(&mut bounty, payload, &clock, ts::ctx(&mut scenario));

    assert!(encrypted_details::has_encrypted_details(&bounty) == true);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_mint_viewer_receipt_happy_path() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);

    // Hunter mints receipt
    ts::next_tx(&mut scenario, HUNTER);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let bounty_id = object::id(&bounty);
    encrypted_details::mint_viewer_receipt(&bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Verify receipt
    ts::next_tx(&mut scenario, HUNTER);
    let receipt = ts::take_from_sender<BountyViewerReceipt>(&scenario);
    assert!(encrypted_details::receipt_viewer(&receipt) == HUNTER);
    assert!(encrypted_details::receipt_bounty_id(&receipt) == bounty_id);
    ts::return_to_sender(&scenario, receipt);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_seal_approve_bounty_happy_path() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);

    // Mint receipt
    ts::next_tx(&mut scenario, HUNTER);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let bounty_id = object::id(&bounty);
    encrypted_details::mint_viewer_receipt(&bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // seal_approve with id = bounty_id_bytes ++ suffix
    ts::next_tx(&mut scenario, HUNTER);
    let receipt = ts::take_from_sender<BountyViewerReceipt>(&scenario);
    let mut id_bytes = object::id_to_bytes(&bounty_id);
    id_bytes.push_back(0x01);
    id_bytes.push_back(0x02);
    encrypted_details::seal_approve_bounty(id_bytes, &receipt);
    ts::return_to_sender(&scenario, receipt);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_burn_viewer_receipt() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);

    // Mint receipt
    ts::next_tx(&mut scenario, HUNTER);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    encrypted_details::mint_viewer_receipt(&bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Burn receipt
    ts::next_tx(&mut scenario, HUNTER);
    let receipt = ts::take_from_sender<BountyViewerReceipt>(&scenario);
    encrypted_details::burn_viewer_receipt(receipt);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_has_encrypted_details_false_by_default() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(encrypted_details::has_encrypted_details(&bounty) == false);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── Negative: set_encrypted_details ───

#[test]
#[expected_failure(abort_code = 13)]
fun test_set_encrypted_details_not_creator() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, RANDOM_USER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    encrypted_details::set_encrypted_details(
        &mut bounty, b"payload", &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 7)]
fun test_set_encrypted_details_bounty_not_open() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);

    // Cancel bounty → status CANCELLED
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::cancel_bounty(&mut bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Try set encrypted details on cancelled bounty
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    encrypted_details::set_encrypted_details(
        &mut bounty, b"payload", &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 64)]
fun test_set_encrypted_details_has_active_claims() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);

    // Creator tries to set after hunter claimed
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    encrypted_details::set_encrypted_details(
        &mut bounty, b"payload", &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 96)]
fun test_set_encrypted_details_empty_payload() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    encrypted_details::set_encrypted_details(
        &mut bounty, b"", &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 97)]
fun test_set_encrypted_details_too_large() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let payload = make_payload(4097);
    encrypted_details::set_encrypted_details(
        &mut bounty, payload, &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 95)]
fun test_set_encrypted_details_already_set() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);

    // First set
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    encrypted_details::set_encrypted_details(
        &mut bounty, b"first", &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);

    // Second set → abort
    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    encrypted_details::set_encrypted_details(
        &mut bounty, b"second", &clock, ts::ctx(&mut scenario),
    );
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── Negative: mint_viewer_receipt ───

#[test]
#[expected_failure(abort_code = 17)]
fun test_mint_viewer_receipt_not_active_hunter() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);

    // Random user (not a hunter) tries to mint receipt
    ts::next_tx(&mut scenario, RANDOM_USER);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    encrypted_details::mint_viewer_receipt(&bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ─── Negative: seal_approve_bounty ───

#[test]
#[expected_failure(abort_code = 91)]
fun test_seal_approve_namespace_too_short() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);

    // Mint receipt
    ts::next_tx(&mut scenario, HUNTER);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    encrypted_details::mint_viewer_receipt(&bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // seal_approve with id too short (< 32 bytes)
    ts::next_tx(&mut scenario, HUNTER);
    let receipt = ts::take_from_sender<BountyViewerReceipt>(&scenario);
    let short_id = b"too_short";
    encrypted_details::seal_approve_bounty(short_id, &receipt);
    ts::return_to_sender(&scenario, receipt);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 92)]
fun test_seal_approve_namespace_mismatch() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup_clock(&mut scenario);
    setup_bounty(&mut scenario, &clock);
    hunter_claim(&mut scenario, &clock);

    // Mint receipt
    ts::next_tx(&mut scenario, HUNTER);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let bounty_id = object::id(&bounty);
    encrypted_details::mint_viewer_receipt(&bounty, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // seal_approve with wrong prefix (flip first byte)
    ts::next_tx(&mut scenario, HUNTER);
    let receipt = ts::take_from_sender<BountyViewerReceipt>(&scenario);
    let mut id_bytes = object::id_to_bytes(&bounty_id);
    let first = id_bytes[0];
    *&mut id_bytes[0] = first ^ 0xFF;
    id_bytes.push_back(0x01); // make it long enough
    encrypted_details::seal_approve_bounty(id_bytes, &receipt);
    ts::return_to_sender(&scenario, receipt);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
