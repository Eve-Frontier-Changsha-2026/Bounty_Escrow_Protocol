/// Intel escrow for encrypted intelligence trading via Seal protocol.
/// Pattern: Hunter posts encrypted intel → Creator decrypts via Seal → Creator confirms → auto-approve.
/// If intel is garbage → existing dispute flow.
module bounty_escrow::intel_escrow;

use sui::clock::Clock;
use sui::event;
use sui::dynamic_field;
use bounty_escrow::constants;
use bounty_escrow::bounty::Bounty;
use bounty_escrow::task_type;

// === DF Key ===

public struct IntelConfigKey() has copy, drop, store;

// === DF Value ===

public struct IntelConfig has copy, drop, store {
    hunter: address,
    encrypted_payload: vector<u8>,
    posted_at: u64,
    confirmed: bool,
}

// === Seal viewer receipt — minted to creator for Seal key server access ===

public struct ViewerReceipt has key, store {
    id: UID,
    viewer: address,    // bounty creator
    bounty_id: ID,
}

// === Events ===

public struct IntelPostedEvent has copy, drop {
    bounty_id: ID,
    hunter: address,
    payload_size: u64,
}

public struct IntelConfirmedEvent has copy, drop {
    bounty_id: ID,
    hunter: address,
    confirmed_by: address,
}

// === Core Functions ===

/// Hunter posts Seal-encrypted intel payload. Mints ViewerReceipt to creator.
/// Requires: task_type == INTEL, hunter has active claim, no existing intel.
public fun post_intel<T>(
    bounty: &mut Bounty<T>,
    encrypted_payload: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let hunter = ctx.sender();
    let bounty_id = object::id(bounty);
    let now = sui::clock::timestamp_ms(clock);

    // Validate task type
    assert!(task_type::get_task_type(bounty) == constants::task_type_intel(),
        constants::e_wrong_task_type());

    // Validate bounty state
    assert!(bounty_escrow::bounty::status(bounty) == constants::status_open() ||
        bounty_escrow::bounty::status(bounty) == constants::status_claimed(),
        constants::e_bounty_not_active());

    // Validate payload
    let payload_size = encrypted_payload.length();
    assert!(payload_size > 0, constants::e_intel_payload_empty());
    assert!(payload_size <= constants::max_intel_payload_size(), constants::e_intel_payload_too_large());

    // Check no existing intel for this bounty (singleton per bounty)
    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(!dynamic_field::exists_(uid, IntelConfigKey()), constants::e_intel_already_posted());

    // Store intel config
    dynamic_field::add(uid, IntelConfigKey(), IntelConfig {
        hunter,
        encrypted_payload,
        posted_at: now,
        confirmed: false,
    });

    // Mint ViewerReceipt to creator (for Seal key server)
    let creator = bounty_escrow::bounty::creator(bounty);
    let receipt = ViewerReceipt {
        id: object::new(ctx),
        viewer: creator,
        bounty_id,
    };
    transfer::transfer(receipt, creator);

    event::emit(IntelPostedEvent {
        bounty_id,
        hunter,
        payload_size,
    });
}

/// Creator confirms intel is valid → auto-approve hunter.
public fun confirm_intel<T>(
    bounty: &mut Bounty<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let caller = ctx.sender();
    let bounty_id = object::id(bounty);

    // Only creator can confirm
    assert!(caller == bounty_escrow::bounty::creator(bounty), constants::e_not_intel_creator());

    // Read and update intel config
    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(dynamic_field::exists_(uid, IntelConfigKey()), constants::e_intel_not_posted());

    let config = dynamic_field::borrow_mut<IntelConfigKey, IntelConfig>(uid, IntelConfigKey());
    assert!(!config.confirmed, constants::e_intel_already_confirmed());
    config.confirmed = true;
    let hunter = config.hunter;

    // Auto-approve the hunter
    bounty_escrow::bounty::auto_verify_approve(bounty, hunter, clock, ctx);

    event::emit(IntelConfirmedEvent {
        bounty_id,
        hunter,
        confirmed_by: caller,
    });
}

/// Seal key server entry point. Verifies the viewer receipt matches the bounty namespace.
/// The Seal key server calls this to authorize decryption.
/// `id` is the Seal namespace bytes (should start with bounty_id bytes).
entry fun seal_approve(id: vector<u8>, receipt: &ViewerReceipt) {
    // Verify the Seal namespace ID starts with the bounty_id bytes
    let bounty_id_bytes = object::id_to_bytes(&receipt.bounty_id);
    let bounty_id_len = bounty_id_bytes.length();
    assert!(id.length() >= bounty_id_len, 0);

    let mut i = 0;
    while (i < bounty_id_len) {
        assert!(id[i] == bounty_id_bytes[i], 0);
        i = i + 1;
    };
    // Seal key server is now authorized to release decryption key to receipt.viewer
}

// === Accessors ===

/// Check if intel has been posted for this bounty.
public fun has_intel<T>(bounty: &Bounty<T>): bool {
    let uid = bounty_escrow::bounty::uid(bounty);
    dynamic_field::exists_(uid, IntelConfigKey())
}

/// Check if intel has been confirmed by creator.
public fun is_intel_confirmed<T>(bounty: &Bounty<T>): bool {
    let uid = bounty_escrow::bounty::uid(bounty);
    if (!dynamic_field::exists_(uid, IntelConfigKey())) return false;
    dynamic_field::borrow<IntelConfigKey, IntelConfig>(uid, IntelConfigKey()).confirmed
}

/// Get intel hunter address. Aborts if no intel posted.
public fun intel_hunter<T>(bounty: &Bounty<T>): address {
    let uid = bounty_escrow::bounty::uid(bounty);
    dynamic_field::borrow<IntelConfigKey, IntelConfig>(uid, IntelConfigKey()).hunter
}

/// Get ViewerReceipt viewer address.
public fun receipt_viewer(receipt: &ViewerReceipt): address { receipt.viewer }

/// Get ViewerReceipt bounty_id.
public fun receipt_bounty_id(receipt: &ViewerReceipt): ID { receipt.bounty_id }
