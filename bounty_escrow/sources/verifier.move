module bounty_escrow::verifier;

use bounty_escrow::constants;

/// Capability token for verifying bounty completion.
/// Only minted inside bounty::create via issue_cap.
public struct VerifierCap has key {
    id: UID,
    bounty_id: ID,
}

/// Mint a VerifierCap and transfer to `verifier` address.
public(package) fun issue_cap(
    bounty_id: ID,
    verifier: address,
    ctx: &mut TxContext,
) {
    let cap = VerifierCap {
        id: object::new(ctx),
        bounty_id,
    };
    transfer::transfer(cap, verifier);
}

/// Assert cap belongs to the given bounty.
public(package) fun validate_cap(cap: &VerifierCap, bounty_id: ID) {
    assert!(cap.bounty_id == bounty_id, constants::e_invalid_verifier_cap());
}

/// Return the bounty_id this cap is for.
public(package) fun bounty_id(cap: &VerifierCap): ID {
    cap.bounty_id
}

/// Return the cap's ID (for events).
public(package) fun cap_id(cap: &VerifierCap): ID {
    object::id(cap)
}

/// Destroy a VerifierCap. Caller must verify bounty is in terminal state before calling.
public(package) fun destroy_cap(cap: VerifierCap) {
    let VerifierCap { id, bounty_id: _ } = cap;
    object::delete(id);
}
