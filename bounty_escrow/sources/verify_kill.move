/// Auto-verification for KILL task type.
/// Verifies hunter's kill using on-chain Killmail shared object + Character identity.
/// Killmail replay protection via UsedKillmailKey DF on Bounty.
module bounty_escrow::verify_kill;

use sui::clock::Clock;
use sui::dynamic_field;
use sui::event;
use world::killmail::{Self, Killmail};
use world::character::Character;
use world::in_game_id;
use bounty_escrow::constants;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::task_type;

// === DF Key for killmail replay protection ===

public struct UsedKillmailKey has copy, drop, store { killmail_id: ID }

// === Events ===

public struct KillVerifiedEvent has copy, drop {
    bounty_id: ID,
    hunter: address,
    killmail_id: ID,
    killer_character_id: u64,
    solar_system_id: u64,
}

// === Entry ===

/// Verify a kill task by providing the on-chain Killmail and hunter's Character.
///
/// Checks:
/// 1. task_type == KILL
/// 2. hunter is active claimer
/// 3. character_address == sender (hunter owns this character)
/// 4. killmail.killer_id == character.key (hunter is the killer)
/// 5. killmail.kill_timestamp >= task_type created_at (kill after bounty config)
/// 6. solar_system_id matches criteria (if criteria != 0)
/// 7. loss_type matches criteria (if criteria != 0)
/// 8. killmail not already used for this bounty
public fun verify_kill<T>(
    bounty: &mut Bounty<T>,
    killmail: &Killmail,
    hunter_character: &Character,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let hunter = ctx.sender();

    // 1. Task type must be KILL
    assert!(task_type::get_task_type(bounty) == constants::task_type_kill(),
        constants::e_wrong_task_type());

    // 2. Hunter must be an active claimer
    assert!(bounty::is_active_hunter(bounty, hunter),
        constants::e_hunter_not_active());

    // 3. Character must belong to sender
    assert!(hunter_character.character_address() == hunter,
        constants::e_character_mismatch());

    // 4. Hunter's character must be the killer
    assert!(killmail.killer_id() == hunter_character.key(),
        constants::e_not_killer());

    // 5. Kill must be after task type was configured
    let created_at = task_type::get_created_at(bounty);
    assert!(killmail.kill_timestamp() >= created_at,
        constants::e_killmail_too_old());

    // 6-7. Check criteria
    let criteria = task_type::borrow_kill_criteria(bounty);

    // Solar system filter (0 = any)
    if (criteria.kill_solar_system_id() != 0) {
        assert!(
            in_game_id::item_id(&killmail.solar_system_id()) == criteria.kill_solar_system_id(),
            constants::e_solar_system_mismatch(),
        );
    };

    // Loss type filter (0 = any, 1 = SHIP, 2 = STRUCTURE)
    let criteria_loss = criteria.kill_loss_type();
    if (criteria_loss != 0) {
        if (criteria_loss == 1) {
            assert!(killmail.loss_type() == killmail::ship(),
                constants::e_loss_type_mismatch());
        } else {
            assert!(killmail.loss_type() == killmail::structure(),
                constants::e_loss_type_mismatch());
        };
    };

    // 8. Killmail replay protection
    let killmail_id = object::id(killmail);
    let uid = bounty::uid_mut(bounty);
    assert!(!dynamic_field::exists_(uid, UsedKillmailKey { killmail_id }),
        constants::e_killmail_already_used());
    dynamic_field::add(uid, UsedKillmailKey { killmail_id }, true);

    // Auto-approve hunter
    bounty::auto_verify_approve(bounty, hunter, clock, ctx);

    event::emit(KillVerifiedEvent {
        bounty_id: object::id(bounty),
        hunter,
        killmail_id,
        killer_character_id: in_game_id::item_id(&hunter_character.key()),
        solar_system_id: in_game_id::item_id(&killmail.solar_system_id()),
    });
}
