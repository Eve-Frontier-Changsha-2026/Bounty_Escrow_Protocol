/// Oracle hybrid verification for BUILD task type.
/// Assembly has no public type_id() accessor, so we use:
///   - &Assembly for on-chain existence proof
///   - Oracle attestation for type_id + solar_system verification
module bounty_escrow::verify_build;

use sui::clock::Clock;
use sui::event;
use sui::bcs;
use world::assembly::Assembly;
use world::character::Character;
use bounty_escrow::constants;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::task_type;
use bounty_escrow::oracle::{Self, OracleRegistry};

// === Events ===

public struct BuildVerifiedEvent has copy, drop {
    bounty_id: ID,
    hunter: address,
    assembly_id: ID,
    assembly_type_id: u64,
    solar_system_id: u64,
}

// === Entry ===

/// Verify a build task using oracle hybrid approach:
/// 1. &Assembly proves on-chain existence
/// 2. Oracle attestation proves type_id + solar_system (no public accessor)
///
/// Attestation BCS format:
///   bounty_id: address, hunter: address, assembly_type_id: u64,
///   solar_system_id: u64, assembly_id: address, timestamp: u64, nonce: u64
///
/// Checks:
/// 1. task_type == BUILD
/// 2. hunter is active claimer
/// 3. character_address == sender
/// 4. assembly_id in attestation matches &Assembly object ID
/// 5. bounty_id in attestation matches bounty
/// 6. hunter in attestation matches sender
/// 7. assembly_type_id matches criteria
/// 8. solar_system_id matches criteria (if criteria != 0)
/// 9. nonce not already used
public fun verify_build<T>(
    bounty: &mut Bounty<T>,
    assembly: &Assembly,
    hunter_character: &Character,
    oracle_registry: &OracleRegistry,
    attestation_message: vector<u8>,
    attestation_signature: vector<u8>,
    oracle_address: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let hunter = ctx.sender();

    // 1. Task type must be BUILD
    assert!(task_type::get_task_type(bounty) == constants::task_type_build(),
        constants::e_wrong_task_type());

    // 2. Hunter must be an active claimer
    assert!(bounty::is_active_hunter(bounty, hunter),
        constants::e_hunter_not_active());

    // 3. Character must belong to sender
    assert!(hunter_character.character_address() == hunter,
        constants::e_character_mismatch());

    // 4. Verify oracle signature (aborts on invalid)
    oracle::verify_attestation(oracle_registry, &attestation_message, &attestation_signature, oracle_address);

    // 5. Decode attestation
    let (att_bounty_id, att_hunter, att_type_id, att_solar, att_assembly_id, _timestamp, nonce) =
        decode_build_attestation(&attestation_message);

    // 6. Attestation must reference this bounty
    assert!(att_bounty_id == object::id_address(bounty),
        constants::e_attestation_bounty_mismatch());

    // 7. Attestation must reference this hunter
    assert!(att_hunter == hunter,
        constants::e_attestation_hunter_mismatch());

    // 8. Assembly ID in attestation must match the on-chain Assembly object
    let assembly_id = object::id(assembly);
    assert!(att_assembly_id == object::id_to_address(&assembly_id),
        constants::e_not_assembly_owner());

    // 9. Check criteria
    let criteria = task_type::borrow_build_criteria(bounty);

    // assembly_type_id must match
    assert!(att_type_id == criteria.build_assembly_type_id(),
        constants::e_not_assembly_owner());

    // solar_system_id filter (0 = any)
    if (criteria.build_solar_system_id() != 0) {
        assert!(att_solar == criteria.build_solar_system_id(),
            constants::e_solar_system_mismatch());
    };

    // 10. Nonce replay protection
    oracle::mark_nonce_used(bounty, nonce);

    // Auto-approve hunter
    bounty::auto_verify_approve(bounty, hunter, clock, ctx);

    event::emit(BuildVerifiedEvent {
        bounty_id: object::id(bounty),
        hunter,
        assembly_id,
        assembly_type_id: att_type_id,
        solar_system_id: att_solar,
    });
}

// === BCS Decode ===

/// Decode BCS-encoded build attestation data.
/// Format: bounty_id(address), hunter(address), assembly_type_id(u64),
///         solar_system_id(u64), assembly_id(address), timestamp(u64), nonce(u64)
fun decode_build_attestation(data: &vector<u8>): (address, address, u64, u64, address, u64, u64) {
    let mut bcs_data = bcs::new(*data);
    let bounty_id = bcs_data.peel_address();
    let hunter = bcs_data.peel_address();
    let assembly_type_id = bcs_data.peel_u64();
    let solar_system_id = bcs_data.peel_u64();
    let assembly_id = bcs_data.peel_address();
    let timestamp = bcs_data.peel_u64();
    let nonce = bcs_data.peel_u64();
    (bounty_id, hunter, assembly_type_id, solar_system_id, assembly_id, timestamp, nonce)
}
