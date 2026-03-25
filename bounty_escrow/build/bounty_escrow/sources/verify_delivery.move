/// Oracle attestation verification for DELIVERY task type.
/// Off-chain indexer tracks ItemDepositedEvent → oracle signs attestation → hunter submits.
module bounty_escrow::verify_delivery;

use sui::clock::Clock;
use sui::event;
use bounty_escrow::constants;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::task_type;
use bounty_escrow::oracle::{Self, OracleRegistry};

// === Events ===

public struct DeliveryVerifiedEvent has copy, drop {
    bounty_id: ID,
    hunter: address,
    item_type_id: u64,
    quantity: u64,
    target_assembly_id: address,
}

// === Entry ===

/// Verify a delivery task via oracle attestation.
///
/// Attestation BCS format (same as oracle::decode_attestation):
///   bounty_id: address, hunter: address, item_type_id: u64,
///   quantity: u64, assembly_id: address, timestamp: u64, nonce: u64
///
/// Checks:
/// 1. task_type == DELIVERY
/// 2. hunter is active claimer
/// 3. oracle signature valid
/// 4. bounty_id in attestation matches this bounty
/// 5. hunter in attestation matches sender
/// 6. item_type_id matches criteria
/// 7. quantity >= criteria.min_quantity
/// 8. assembly_id matches criteria.target_assembly_id (if != @0x0)
/// 9. nonce not already used
public fun verify_delivery<T>(
    bounty: &mut Bounty<T>,
    oracle_registry: &OracleRegistry,
    attestation_message: vector<u8>,
    attestation_signature: vector<u8>,
    oracle_address: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let hunter = ctx.sender();

    // 1. Task type must be DELIVERY
    assert!(task_type::get_task_type(bounty) == constants::task_type_delivery(),
        constants::e_wrong_task_type());

    // 1b. Block auto-verify if criteria are encrypted
    assert!(!task_type::is_criteria_encrypted(bounty), constants::e_criteria_encrypted_manual_only());

    // 2. Hunter must be an active claimer
    assert!(bounty::is_active_hunter(bounty, hunter),
        constants::e_hunter_not_active());

    // 3. Verify oracle signature (aborts on invalid)
    oracle::verify_attestation(oracle_registry, &attestation_message, &attestation_signature, oracle_address);

    // 4. Decode attestation
    let (att_bounty_id, att_hunter, att_item_type_id, att_quantity, att_assembly_id, _timestamp, nonce) =
        oracle::decode_attestation(&attestation_message);

    // 5. Attestation must reference this bounty
    assert!(att_bounty_id == object::id_address(bounty),
        constants::e_attestation_bounty_mismatch());

    // 6. Attestation must reference this hunter
    assert!(att_hunter == hunter,
        constants::e_attestation_hunter_mismatch());

    // 7. Check criteria
    let criteria = task_type::borrow_delivery_criteria(bounty);

    // item_type_id must match
    assert!(att_item_type_id == criteria.delivery_item_type_id(),
        constants::e_delivery_item_mismatch());

    // quantity must meet minimum
    assert!(att_quantity >= criteria.delivery_min_quantity(),
        constants::e_delivery_quantity_insufficient());

    // target_assembly_id filter (@0x0 = any)
    if (criteria.delivery_target_assembly_id() != @0x0) {
        assert!(att_assembly_id == criteria.delivery_target_assembly_id(),
            constants::e_delivery_target_mismatch());
    };

    // 8. Nonce replay protection
    oracle::mark_nonce_used(bounty, nonce);

    // Auto-approve hunter
    bounty::auto_verify_approve(bounty, hunter, clock, ctx);

    event::emit(DeliveryVerifiedEvent {
        bounty_id: object::id(bounty),
        hunter,
        item_type_id: att_item_type_id,
        quantity: att_quantity,
        target_assembly_id: att_assembly_id,
    });
}
