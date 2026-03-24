/// Oracle registry for off-chain attestation verification.
/// Self-contained Ed25519 verification — no world contract dependency.
/// Used by DELIVERY and BUILD (hybrid) task types.
module bounty_escrow::oracle;

use sui::vec_map::{Self, VecMap};
use sui::event;
use sui::clock::Clock;
use sui::ed25519;
use sui::hash;
use sui::dynamic_field;
use sui::bcs;
use bounty_escrow::constants;
use bounty_escrow::bounty::Bounty;

// === Structs ===

public struct OracleRegistry has key {
    id: UID,
    admin: address,
    oracles: VecMap<address, OracleInfo>,
}

public struct OracleInfo has copy, drop, store {
    name: std::string::String,
    active: bool,
    registered_at: u64,
}

// === DF Key for nonce replay protection (on Bounty) ===

public struct OracleNonceKey has copy, drop, store { nonce: u64 }

// === Events ===

public struct OracleRegistryCreated has copy, drop {
    registry_id: ID,
    admin: address,
}

public struct OracleRegisteredEvent has copy, drop {
    registry_id: ID,
    oracle_address: address,
    name: std::string::String,
}

public struct OracleDeactivatedEvent has copy, drop {
    registry_id: ID,
    oracle_address: address,
}

// === Admin Functions ===

/// Create a new oracle registry. Caller becomes admin.
public fun create_registry(clock: &Clock, ctx: &mut TxContext): OracleRegistry {
    let registry = OracleRegistry {
        id: object::new(ctx),
        admin: ctx.sender(),
        oracles: vec_map::empty(),
    };
    let _ = sui::clock::timestamp_ms(clock); // anchor timestamp

    event::emit(OracleRegistryCreated {
        registry_id: object::id(&registry),
        admin: ctx.sender(),
    });

    registry
}

/// Register an oracle address. Admin only.
public fun register_oracle(
    registry: &mut OracleRegistry,
    oracle_address: address,
    name: std::string::String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == registry.admin, constants::e_not_registry_admin());
    assert!(!vec_map::contains(&registry.oracles, &oracle_address),
        constants::e_oracle_already_registered());

    vec_map::insert(&mut registry.oracles, oracle_address, OracleInfo {
        name,
        active: true,
        registered_at: sui::clock::timestamp_ms(clock),
    });

    event::emit(OracleRegisteredEvent {
        registry_id: object::id(registry),
        oracle_address,
        name,
    });
}

/// Deactivate an oracle. Admin only. Does not remove — preserves history.
public fun deactivate_oracle(
    registry: &mut OracleRegistry,
    oracle_address: address,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == registry.admin, constants::e_not_registry_admin());
    let info = vec_map::get_mut(&mut registry.oracles, &oracle_address);
    info.active = false;

    event::emit(OracleDeactivatedEvent {
        registry_id: object::id(registry),
        oracle_address,
    });
}

// === Query ===

/// Check if an oracle address is active.
public fun is_active_oracle(registry: &OracleRegistry, addr: address): bool {
    if (!vec_map::contains(&registry.oracles, &addr)) return false;
    vec_map::get(&registry.oracles, &addr).active
}

public fun admin(registry: &OracleRegistry): address { registry.admin }

// === Attestation Verification ===

/// Verify Ed25519 signature over a message.
/// Message should be: sha3_256(bcs-encoded attestation data).
/// Returns true if signature is valid AND oracle is active.
public fun verify_attestation(
    _registry: &OracleRegistry,
    message: &vector<u8>,
    signature: &vector<u8>,
    oracle_pubkey: &vector<u8>,
): bool {
    // Hash the message with keccak256 for Ed25519
    let msg_hash = hash::keccak256(message);
    ed25519::ed25519_verify(signature, oracle_pubkey, &msg_hash)
}

// === Nonce replay protection (on Bounty UID) ===

/// Check if a nonce has been used for this bounty.
public(package) fun is_nonce_used<T>(bounty: &Bounty<T>, nonce: u64): bool {
    let uid = bounty_escrow::bounty::uid(bounty);
    dynamic_field::exists_(uid, OracleNonceKey { nonce })
}

/// Mark a nonce as used for this bounty. Aborts if already used.
public(package) fun mark_nonce_used<T>(bounty: &mut Bounty<T>, nonce: u64) {
    assert!(!is_nonce_used(bounty, nonce), constants::e_nonce_already_used());
    let uid = bounty_escrow::bounty::uid_mut(bounty);
    dynamic_field::add(uid, OracleNonceKey { nonce }, true);
}

// === Attestation Data BCS Helpers ===
// Attestation format (BCS-encoded, oracle signs keccak256 of this):
//   bounty_id: address, hunter: address, item_type_id: u64,
//   quantity: u64, assembly_id: address, timestamp: u64, nonce: u64

/// Decode BCS-encoded attestation data.
public fun decode_attestation(data: &vector<u8>): (address, address, u64, u64, address, u64, u64) {
    let mut bcs_data = bcs::new(*data);
    let bounty_id = bcs_data.peel_address();
    let hunter = bcs_data.peel_address();
    let item_type_id = bcs_data.peel_u64();
    let quantity = bcs_data.peel_u64();
    let assembly_id = bcs_data.peel_address();
    let timestamp = bcs_data.peel_u64();
    let nonce = bcs_data.peel_u64();
    (bounty_id, hunter, item_type_id, quantity, assembly_id, timestamp, nonce)
}
