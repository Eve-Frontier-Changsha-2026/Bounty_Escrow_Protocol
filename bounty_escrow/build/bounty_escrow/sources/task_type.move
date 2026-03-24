/// Task type configuration and criteria for bounties.
/// Supports: CUSTOM(0), KILL(1), DELIVERY(2), BUILD(3), INTEL(4).
/// All config stored as Dynamic Fields on Bounty — zero struct layout change.
module bounty_escrow::task_type;

use sui::clock::Clock;
use sui::dynamic_field;
use bounty_escrow::constants;
use bounty_escrow::bounty::Bounty;

// === DF Key Structs (positional, no fields) ===

public struct TaskTypeKey() has copy, drop, store;
public struct KillCriteriaKey() has copy, drop, store;
public struct DeliveryCriteriaKey() has copy, drop, store;
public struct BuildCriteriaKey() has copy, drop, store;

// === DF Value Structs ===

public struct TaskTypeConfig has copy, drop, store {
    task_type: u8,
    verification_mode: u8,
    created_at: u64,
}

public struct KillCriteria has copy, drop, store {
    solar_system_id: u64,   // 0 = any
    loss_type: u8,          // 0 = any
    min_kills: u64,         // minimum kills required (usually 1)
}

public struct DeliveryCriteria has copy, drop, store {
    item_type_id: u64,
    min_quantity: u64,
    target_assembly_id: address, // @0x0 = any
}

public struct BuildCriteria has copy, drop, store {
    assembly_type_id: u64,
    solar_system_id: u64,   // 0 = any
}

// === Internal: task_type → verification_mode mapping ===

fun verification_mode_for(task_type: u8): u8 {
    if (task_type == constants::task_type_kill()) {
        constants::verify_mode_auto()
    } else if (task_type == constants::task_type_delivery()) {
        constants::verify_mode_oracle()
    } else if (task_type == constants::task_type_build()) {
        constants::verify_mode_auto()
    } else if (task_type == constants::task_type_intel()) {
        constants::verify_mode_seal()
    } else {
        // CUSTOM or any unknown → manual
        constants::verify_mode_manual()
    }
}

// === Setters (creator only, OPEN status, 0 active_claims, one-time) ===

/// Set the task type for a bounty. Can only be set once, before any claims.
public fun set_task_type<T>(
    bounty: &mut Bounty<T>,
    task_type: u8,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == bounty_escrow::bounty::creator(bounty), constants::e_not_creator());
    assert!(bounty_escrow::bounty::status(bounty) == constants::status_open(),
        constants::e_task_type_requires_open());
    assert!(bounty_escrow::bounty::active_claims(bounty) == 0,
        constants::e_task_type_has_active_claims());
    assert!(task_type <= constants::task_type_intel(), constants::e_invalid_task_type());

    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(!dynamic_field::exists_(uid, TaskTypeKey()), constants::e_task_type_already_set());

    dynamic_field::add(uid, TaskTypeKey(), TaskTypeConfig {
        task_type,
        verification_mode: verification_mode_for(task_type),
        created_at: sui::clock::timestamp_ms(clock),
    });
}

/// Set kill criteria. Requires task_type == KILL and no existing criteria.
public fun set_kill_criteria<T>(
    bounty: &mut Bounty<T>,
    solar_system_id: u64,
    loss_type: u8,
    min_kills: u64,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == bounty_escrow::bounty::creator(bounty), constants::e_not_creator());
    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(dynamic_field::exists_(uid, TaskTypeKey()), constants::e_missing_criteria());

    let config = dynamic_field::borrow<TaskTypeKey, TaskTypeConfig>(uid, TaskTypeKey());
    assert!(config.task_type == constants::task_type_kill(), constants::e_wrong_task_type());
    assert!(!dynamic_field::exists_(uid, KillCriteriaKey()), constants::e_criteria_already_set());

    dynamic_field::add(uid, KillCriteriaKey(), KillCriteria {
        solar_system_id,
        loss_type,
        min_kills,
    });
}

/// Set delivery criteria. Requires task_type == DELIVERY.
public fun set_delivery_criteria<T>(
    bounty: &mut Bounty<T>,
    item_type_id: u64,
    min_quantity: u64,
    target_assembly_id: address,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == bounty_escrow::bounty::creator(bounty), constants::e_not_creator());
    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(dynamic_field::exists_(uid, TaskTypeKey()), constants::e_missing_criteria());

    let config = dynamic_field::borrow<TaskTypeKey, TaskTypeConfig>(uid, TaskTypeKey());
    assert!(config.task_type == constants::task_type_delivery(), constants::e_wrong_task_type());
    assert!(!dynamic_field::exists_(uid, DeliveryCriteriaKey()), constants::e_criteria_already_set());

    dynamic_field::add(uid, DeliveryCriteriaKey(), DeliveryCriteria {
        item_type_id,
        min_quantity,
        target_assembly_id,
    });
}

/// Set build criteria. Requires task_type == BUILD.
public fun set_build_criteria<T>(
    bounty: &mut Bounty<T>,
    assembly_type_id: u64,
    solar_system_id: u64,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == bounty_escrow::bounty::creator(bounty), constants::e_not_creator());
    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(dynamic_field::exists_(uid, TaskTypeKey()), constants::e_missing_criteria());

    let config = dynamic_field::borrow<TaskTypeKey, TaskTypeConfig>(uid, TaskTypeKey());
    assert!(config.task_type == constants::task_type_build(), constants::e_wrong_task_type());
    assert!(!dynamic_field::exists_(uid, BuildCriteriaKey()), constants::e_criteria_already_set());

    dynamic_field::add(uid, BuildCriteriaKey(), BuildCriteria {
        assembly_type_id,
        solar_system_id,
    });
}

// === Accessors (public, backward compat: no DF → CUSTOM) ===

/// Returns task type. Defaults to CUSTOM if not set.
public fun get_task_type<T>(bounty: &Bounty<T>): u8 {
    let uid = bounty_escrow::bounty::uid(bounty);
    if (dynamic_field::exists_(uid, TaskTypeKey())) {
        dynamic_field::borrow<TaskTypeKey, TaskTypeConfig>(uid, TaskTypeKey()).task_type
    } else {
        constants::task_type_custom()
    }
}

/// Returns verification mode. Defaults to MANUAL if not set.
public fun get_verification_mode<T>(bounty: &Bounty<T>): u8 {
    let uid = bounty_escrow::bounty::uid(bounty);
    if (dynamic_field::exists_(uid, TaskTypeKey())) {
        dynamic_field::borrow<TaskTypeKey, TaskTypeConfig>(uid, TaskTypeKey()).verification_mode
    } else {
        constants::verify_mode_manual()
    }
}

/// Returns created_at timestamp of task type config. 0 if not set.
public fun get_created_at<T>(bounty: &Bounty<T>): u64 {
    let uid = bounty_escrow::bounty::uid(bounty);
    if (dynamic_field::exists_(uid, TaskTypeKey())) {
        dynamic_field::borrow<TaskTypeKey, TaskTypeConfig>(uid, TaskTypeKey()).created_at
    } else {
        0
    }
}

// === Package-level accessors for verify_* modules ===

/// Borrow kill criteria. Aborts if not set.
public(package) fun borrow_kill_criteria<T>(bounty: &Bounty<T>): &KillCriteria {
    let uid = bounty_escrow::bounty::uid(bounty);
    assert!(dynamic_field::exists_(uid, KillCriteriaKey()), constants::e_missing_criteria());
    dynamic_field::borrow<KillCriteriaKey, KillCriteria>(uid, KillCriteriaKey())
}

/// Borrow delivery criteria. Aborts if not set.
public(package) fun borrow_delivery_criteria<T>(bounty: &Bounty<T>): &DeliveryCriteria {
    let uid = bounty_escrow::bounty::uid(bounty);
    assert!(dynamic_field::exists_(uid, DeliveryCriteriaKey()), constants::e_missing_criteria());
    dynamic_field::borrow<DeliveryCriteriaKey, DeliveryCriteria>(uid, DeliveryCriteriaKey())
}

/// Borrow build criteria. Aborts if not set.
public(package) fun borrow_build_criteria<T>(bounty: &Bounty<T>): &BuildCriteria {
    let uid = bounty_escrow::bounty::uid(bounty);
    assert!(dynamic_field::exists_(uid, BuildCriteriaKey()), constants::e_missing_criteria());
    dynamic_field::borrow<BuildCriteriaKey, BuildCriteria>(uid, BuildCriteriaKey())
}

// === Criteria field accessors ===

public fun kill_solar_system_id(c: &KillCriteria): u64 { c.solar_system_id }
public fun kill_loss_type(c: &KillCriteria): u8 { c.loss_type }
public fun kill_min_kills(c: &KillCriteria): u64 { c.min_kills }

public fun delivery_item_type_id(c: &DeliveryCriteria): u64 { c.item_type_id }
public fun delivery_min_quantity(c: &DeliveryCriteria): u64 { c.min_quantity }
public fun delivery_target_assembly_id(c: &DeliveryCriteria): address { c.target_assembly_id }

public fun build_assembly_type_id(c: &BuildCriteria): u64 { c.assembly_type_id }
public fun build_solar_system_id(c: &BuildCriteria): u64 { c.solar_system_id }
