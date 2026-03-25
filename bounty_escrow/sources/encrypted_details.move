/// Encrypted bounty details via Seal protocol.
/// Creator stores Seal-encrypted payload; hunters decrypt after claiming.
module bounty_escrow::encrypted_details;

use sui::clock::Clock;
use sui::event;
use sui::dynamic_field;
use bounty_escrow::constants;
use bounty_escrow::bounty::Bounty;

// === DF Key ===

public struct EncryptedDetailsKey() has copy, drop, store;

// === DF Value ===

public struct EncryptedDetails has copy, drop, store {
    encrypted_payload: vector<u8>,
    created_at: u64,
}

// === Seal Viewer Receipt ===

public struct BountyViewerReceipt has key, store {
    id: UID,
    viewer: address,
    bounty_id: ID,
}

// === Events ===

public struct EncryptedDetailsSetEvent has copy, drop {
    bounty_id: ID,
    creator: address,
    payload_size: u64,
}

public struct ViewerReceiptMintedEvent has copy, drop {
    bounty_id: ID,
    receipt_id: ID,
    viewer: address,
}

// === Core Functions ===

/// Store encrypted details on a bounty. Creator only, one-time, ≤4KB.
public fun set_encrypted_details<T>(
    bounty: &mut Bounty<T>,
    encrypted_payload: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let creator = bounty_escrow::bounty::creator(bounty);
    assert!(ctx.sender() == creator, constants::e_not_creator());
    assert!(bounty_escrow::bounty::status(bounty) == constants::status_open(),
        constants::e_bounty_not_open());
    assert!(bounty_escrow::bounty::active_claims(bounty) == 0,
        constants::e_task_type_has_active_claims());

    let payload_size = encrypted_payload.length();
    assert!(payload_size > 0, constants::e_encrypted_details_not_set());
    assert!(payload_size <= constants::max_encrypted_details_size(),
        constants::e_encrypted_payload_too_large());

    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(!dynamic_field::exists_(uid, EncryptedDetailsKey()),
        constants::e_encrypted_details_already_set());

    dynamic_field::add(uid, EncryptedDetailsKey(), EncryptedDetails {
        encrypted_payload,
        created_at: sui::clock::timestamp_ms(clock),
    });

    event::emit(EncryptedDetailsSetEvent {
        bounty_id: object::id(bounty),
        creator,
        payload_size,
    });
}

/// Mint a BountyViewerReceipt for the calling hunter.
public fun mint_viewer_receipt<T>(
    bounty: &Bounty<T>,
    ctx: &mut TxContext,
) {
    let hunter = ctx.sender();
    assert!(bounty_escrow::bounty::is_active_hunter(bounty, hunter),
        constants::e_hunter_not_active());

    let bounty_id = object::id(bounty);
    let receipt = BountyViewerReceipt {
        id: object::new(ctx),
        viewer: hunter,
        bounty_id,
    };
    let receipt_id = object::id(&receipt);

    transfer::transfer(receipt, hunter);

    event::emit(ViewerReceiptMintedEvent {
        bounty_id,
        receipt_id,
        viewer: hunter,
    });
}

/// Seal key server entry point. Validates namespace prefix = bounty_id.
entry fun seal_approve_bounty(id: vector<u8>, receipt: &BountyViewerReceipt) {
    let bounty_id_bytes = object::id_to_bytes(&receipt.bounty_id);
    let bounty_id_len = bounty_id_bytes.length();
    assert!(id.length() >= bounty_id_len, constants::e_seal_namespace_too_short());

    let mut i = 0;
    while (i < bounty_id_len) {
        assert!(id[i] == bounty_id_bytes[i], constants::e_seal_namespace_mismatch());
        i = i + 1;
    };
}

/// Destroy a BountyViewerReceipt (cleanup).
public fun burn_viewer_receipt(receipt: BountyViewerReceipt) {
    let BountyViewerReceipt { id, .. } = receipt;
    id.delete();
}

// === Accessors ===

public fun has_encrypted_details<T>(bounty: &Bounty<T>): bool {
    let uid = bounty_escrow::bounty::uid(bounty);
    dynamic_field::exists_(uid, EncryptedDetailsKey())
}

public fun get_encrypted_payload<T>(bounty: &Bounty<T>): &vector<u8> {
    let uid = bounty_escrow::bounty::uid(bounty);
    &dynamic_field::borrow<EncryptedDetailsKey, EncryptedDetails>(uid, EncryptedDetailsKey()).encrypted_payload
}

public fun receipt_viewer(receipt: &BountyViewerReceipt): address { receipt.viewer }
public fun receipt_bounty_id(receipt: &BountyViewerReceipt): ID { receipt.bounty_id }
