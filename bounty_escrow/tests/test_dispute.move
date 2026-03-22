#[test_only]
module bounty_escrow::test_dispute;

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
const DEADLINE: u64 = 1_000_000_000 + 86_400_000; // +1 day
const GRACE: u64 = 86_400_000; // 1 day
const REVIEW_PERIOD: u64 = 259_200_000; // 3 days (default)

// Helper: create bounty(reward=1000, stake=100, max=2) and have HUNTER1 claim
fun setup_claimed_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock): Bounty<SUI> {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(2000, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Test bounty".to_string(),
        b"Description".to_string(),
        coin, 1000, 100, 2,
        DEADLINE, GRACE, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
    ts::next_tx(scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(scenario));
    bounty::claim<SUI>(&mut bounty, stake, clock, ts::ctx(scenario));
    bounty
}

// ========== set_review_period ==========

#[test]
fun test_set_review_period_happy() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // Create bounty, no claims yet
    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"Desc".to_string(),
        coin, 1000, 100, 2, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::set_review_period<SUI>(&mut bounty, 7_200_000, ts::ctx(&mut scenario)); // 2 hours
    assert!(bounty::review_period(&bounty) == 7_200_000);

    // Can overwrite
    bounty::set_review_period<SUI>(&mut bounty, 86_400_000, ts::ctx(&mut scenario)); // 1 day
    assert!(bounty::review_period(&bounty) == 86_400_000);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 13)] // e_not_creator
fun test_set_review_period_not_creator() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"Desc".to_string(),
        coin, 1000, 100, 2, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::set_review_period<SUI>(&mut bounty, 7_200_000, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 37)] // e_hunter_not_claimed (reused as "has claims")
fun test_set_review_period_after_claim() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, CREATOR);
    bounty::set_review_period<SUI>(&mut bounty, 7_200_000, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========== submit_proof ==========

#[test]
fun test_submit_proof_happy() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com/123".to_string(),
        b"Completed the mission".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    assert!(bounty::has_proof(&bounty, HUNTER1));
    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_submitted());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 37)] // e_hunter_not_claimed
fun test_submit_proof_not_claimed() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // HUNTER2 never claimed
    ts::next_tx(&mut scenario, HUNTER2);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com".to_string(),
        b"Proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 36)] // e_proof_already_submitted
fun test_submit_proof_double_submit() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com".to_string(),
        b"Proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Second submit should fail
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof2.example.com".to_string(),
        b"Proof 2".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 10)] // e_deadline_passed
fun test_submit_proof_after_deadline() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    clock::set_for_testing(&mut clock, DEADLINE + 1);
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com".to_string(),
        b"Proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 45)] // e_proof_url_empty
fun test_submit_proof_empty_url() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"".to_string(),
        b"Proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========== reject_proof ==========

#[test]
fun test_reject_proof_happy() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit proof
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com".to_string(),
        b"Proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Verifier rejects
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1,
        b"Insufficient evidence".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_rejected());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 16)] // e_invalid_verifier_cap
fun test_reject_proof_wrong_cap() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit proof
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com".to_string(),
        b"Proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Create a second bounty to get a different cap
    ts::next_tx(&mut scenario, CREATOR);
    let coin2 = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Other".to_string(), b"Other".to_string(),
        coin2, 1000, 100, 1, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Try to use wrong cap
    ts::next_tx(&mut scenario, VERIFIER);
    // take_from_sender returns the most recently created one
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1,
        b"Reason".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 47)] // e_rejection_reason_empty
fun test_reject_proof_empty_reason() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com".to_string(),
        b"Proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1,
        b"".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 51)] // e_review_window_expired
fun test_reject_proof_after_review_window() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com".to_string(),
        b"Proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Advance past review window (default 3 days)
    clock::set_for_testing(&mut clock, BASE_TIME + REVIEW_PERIOD + 1);

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1,
        b"Too late".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========== resubmit_proof ==========

#[test]
fun test_resubmit_proof_happy() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com/v1".to_string(),
        b"First attempt".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Reject
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1,
        b"Needs more detail".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    // Resubmit
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::resubmit_proof<SUI>(
        &mut bounty,
        b"https://proof.example.com/v2".to_string(),
        b"Updated proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_submitted());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 49)] // e_resubmit_exhausted
fun test_resubmit_proof_exhausted() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit → reject → resubmit → reject → try resubmit again
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://v1".to_string(), b"V1".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Bad".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::resubmit_proof<SUI>(
        &mut bounty,
        b"https://v2".to_string(), b"V2".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Still bad".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    // This should fail — already resubmitted once
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::resubmit_proof<SUI>(
        &mut bounty,
        b"https://v3".to_string(), b"V3".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 40)] // e_proof_not_rejected
fun test_resubmit_proof_not_rejected() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Proof".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Try resubmit while still SUBMITTED (not rejected)
    bounty::resubmit_proof<SUI>(
        &mut bounty,
        b"https://v2".to_string(), b"V2".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========== dispute_rejection ==========

#[test]
fun test_dispute_rejection_happy() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit → reject → dispute
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Nope".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::dispute_rejection<SUI>(
        &mut bounty,
        b"I completed the task, here is evidence".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_disputed());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 40)] // e_proof_not_rejected
fun test_dispute_when_not_rejected() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Try dispute while SUBMITTED (not rejected)
    bounty::dispute_rejection<SUI>(
        &mut bounty,
        b"Dispute".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========== resolve_dispute ==========

#[test]
fun test_resolve_dispute_approve() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit → reject → dispute
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Nope".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::dispute_rejection<SUI>(
        &mut bounty,
        b"I did it".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Creator resolves: approve
    ts::next_tx(&mut scenario, CREATOR);
    bounty::resolve_dispute<SUI>(
        &mut bounty, HUNTER1, true,
        &clock, ts::ctx(&mut scenario),
    );

    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_resolved_approved());

    // Hunter can now claim reward
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_resolve_dispute_reject() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit → reject → dispute
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Nope".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::dispute_rejection<SUI>(
        &mut bounty, b"I did it".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Creator resolves: reject
    ts::next_tx(&mut scenario, CREATOR);
    bounty::resolve_dispute<SUI>(
        &mut bounty, HUNTER1, false,
        &clock, ts::ctx(&mut scenario),
    );

    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_resolved_rejected());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 13)] // e_not_creator
fun test_resolve_dispute_not_creator() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Nope".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::dispute_rejection<SUI>(
        &mut bounty, b"Dispute".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // HUNTER2 tries to resolve (not creator)
    ts::next_tx(&mut scenario, HUNTER2);
    bounty::resolve_dispute<SUI>(
        &mut bounty, HUNTER1, true,
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 41)] // e_proof_not_disputed
fun test_resolve_dispute_not_disputed() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Try resolve without dispute
    ts::next_tx(&mut scenario, CREATOR);
    bounty::resolve_dispute<SUI>(
        &mut bounty, HUNTER1, true,
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========== auto_approve_proof ==========

#[test]
fun test_auto_approve_happy() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Advance past review period
    clock::set_for_testing(&mut clock, BASE_TIME + REVIEW_PERIOD);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::auto_approve_proof<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_approved());

    // Can claim reward
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 42)] // e_review_period_not_expired
fun test_auto_approve_too_early() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Only advance a little (less than review period)
    clock::set_for_testing(&mut clock, BASE_TIME + REVIEW_PERIOD - 1);

    bounty::auto_approve_proof<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 43)] // e_already_auto_approved
fun test_auto_approve_already_approved() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit proof
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Verifier approves via legacy path
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);

    // Try auto-approve — already in approved_hunters
    clock::set_for_testing(&mut clock, BASE_TIME + REVIEW_PERIOD);
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::auto_approve_proof<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========== Integration Tests ==========

#[test]
fun test_full_proof_flow_with_resubmit() {
    // claim → submit → reject → resubmit → approve_hunter → claim_reward
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://v1".to_string(), b"V1".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Reject
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Not enough".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    // Resubmit
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::resubmit_proof<SUI>(
        &mut bounty,
        b"https://v2".to_string(), b"V2 better".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Approve via legacy
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);

    // Claim reward
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    assert!(bounty::completed_claims(&bounty) == 1);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_full_dispute_flow() {
    // claim → submit → reject → dispute → resolve(approve) → claim_reward
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Nope".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::dispute_rejection<SUI>(
        &mut bounty, b"I disagree".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    bounty::resolve_dispute<SUI>(
        &mut bounty, HUNTER1, true,
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    assert!(bounty::completed_claims(&bounty) == 1);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_legacy_and_proof_coexist() {
    // HUNTER1 uses proof flow, HUNTER2 uses legacy approve
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // HUNTER2 also claims
    ts::next_tx(&mut scenario, HUNTER2);
    let stake2 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake2, &clock, ts::ctx(&mut scenario));

    // HUNTER1 uses proof flow
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // HUNTER2 gets legacy approve
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER2, &cap, &clock, ts::ctx(&mut scenario));

    // Also approve HUNTER1 via legacy
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);

    // Both claim reward
    ts::next_tx(&mut scenario, HUNTER2);
    let ticket2 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket2, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER1);
    let ticket1 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket1, ts::ctx(&mut scenario));

    assert!(bounty::completed_claims(&bounty) == 2);
    assert!(bounty::status(&bounty) == constants::status_completed());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_proof_then_cancel() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit proof
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Creator cancels
    ts::next_tx(&mut scenario, CREATOR);
    bounty::cancel<SUI>(&mut bounty, ts::ctx(&mut scenario));

    // Hunter withdraws penalty (unapproved → penalty = required_stake = 100)
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::withdraw_penalty<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_proof_then_expire() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit proof
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Advance past deadline + grace
    clock::set_for_testing(&mut clock, DEADLINE + GRACE + 1);

    // Anyone can expire
    ts::next_tx(&mut scenario, HUNTER2);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    assert!(bounty::status(&bounty) == constants::status_expired());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ========== Monkey / Edge Case Tests ==========

#[test]
fun test_abandon_with_pending_proof() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit proof
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Abandon with pending proof — should work, proof DF cleaned up
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::abandon<SUI>(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));

    // Proof DF cleaned up on abandon
    assert!(!bounty::has_proof(&bounty, HUNTER1));
    assert!(bounty::active_claims(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_resubmit_then_dispute_on_second_rejection() {
    // submit → reject → resubmit → reject again → dispute → resolve(approve)
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Submit
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://v1".to_string(), b"V1".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Reject
    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Bad".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );

    // Resubmit
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::resubmit_proof<SUI>(
        &mut bounty,
        b"https://v2".to_string(), b"V2".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Reject again
    ts::next_tx(&mut scenario, VERIFIER);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"Still bad".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    // Can't resubmit (exhausted), so dispute
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::dispute_rejection<SUI>(
        &mut bounty, b"I insist".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Creator approves
    ts::next_tx(&mut scenario, CREATOR);
    bounty::resolve_dispute<SUI>(
        &mut bounty, HUNTER1, true,
        &clock, ts::ctx(&mut scenario),
    );

    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_resolved_approved());

    // Claim reward
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_auto_approve_with_custom_review_period() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // Create bounty with custom review period
    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"Desc".to_string(),
        coin, 1000, 100, 2, DEADLINE, GRACE, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let custom_period: u64 = 7_200_000; // 2 hours
    bounty::set_review_period<SUI>(&mut bounty, custom_period, ts::ctx(&mut scenario));

    // Hunter claims
    ts::next_tx(&mut scenario, HUNTER1);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    // Submit proof
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    // Advance past custom review period (2 hours)
    clock::set_for_testing(&mut clock, BASE_TIME + custom_period);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::auto_approve_proof<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_approved());

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 40)] // e_proof_not_rejected (status is RESOLVED_REJECTED, not REJECTED)
fun test_dispute_after_resolved_rejected() {
    // Once RESOLVED_REJECTED, cannot re-dispute (status != REJECTED)
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // Full flow to resolved_rejected
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://proof".to_string(), b"Done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, VERIFIER);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::reject_proof<SUI>(
        &mut bounty, HUNTER1, b"No".to_string(),
        &cap, &clock, ts::ctx(&mut scenario),
    );
    ts::return_to_sender(&scenario, cap);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::dispute_rejection<SUI>(
        &mut bounty, b"Appeal".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, CREATOR);
    bounty::resolve_dispute<SUI>(
        &mut bounty, HUNTER1, false, // reject
        &clock, ts::ctx(&mut scenario),
    );

    // Status is now RESOLVED_REJECTED — try dispute again
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::dispute_rejection<SUI>(
        &mut bounty, b"Second appeal".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_multiple_hunters_submit_proofs() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    let mut bounty = setup_claimed_bounty(&mut scenario, &clock);

    // HUNTER2 claims
    ts::next_tx(&mut scenario, HUNTER2);
    let stake2 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake2, &clock, ts::ctx(&mut scenario));

    // Both submit proofs
    ts::next_tx(&mut scenario, HUNTER1);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://h1-proof".to_string(), b"H1 done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    ts::next_tx(&mut scenario, HUNTER2);
    bounty::submit_proof<SUI>(
        &mut bounty,
        b"https://h2-proof".to_string(), b"H2 done".to_string(),
        &clock, ts::ctx(&mut scenario),
    );

    assert!(bounty::has_proof(&bounty, HUNTER1));
    assert!(bounty::has_proof(&bounty, HUNTER2));
    assert!(bounty::proof_status(&bounty, HUNTER1) == constants::proof_submitted());
    assert!(bounty::proof_status(&bounty, HUNTER2) == constants::proof_submitted());

    // Auto-approve both after review period
    clock::set_for_testing(&mut clock, BASE_TIME + REVIEW_PERIOD);

    ts::next_tx(&mut scenario, HUNTER1);
    bounty::auto_approve_proof<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER2);
    bounty::auto_approve_proof<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));

    // Both claim rewards
    ts::next_tx(&mut scenario, HUNTER1);
    let ticket1 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket1, ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, HUNTER2);
    let ticket2 = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket2, ts::ctx(&mut scenario));

    assert!(bounty::status(&bounty) == constants::status_completed());
    assert!(bounty::completed_claims(&bounty) == 2);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
