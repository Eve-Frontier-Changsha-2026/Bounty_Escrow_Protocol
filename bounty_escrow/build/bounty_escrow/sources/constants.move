module bounty_escrow::constants;

// === 狀態碼 ===
public fun status_open(): u8 { 0 }
public fun status_claimed(): u8 { 1 }
public fun status_completed(): u8 { 2 }
public fun status_cancelled(): u8 { 3 }
public fun status_expired(): u8 { 4 }

// === 上限 ===
public fun max_cleanup_reward_bps(): u16 { 1000 }
public fun max_claims(): u64 { 100 }
public fun max_title_length(): u64 { 256 }
public fun max_description_length(): u64 { 2048 }
public fun max_metadata_entries(): u64 { 20 }
public fun max_metadata_value_length(): u64 { 1024 }
public fun min_deadline_duration(): u64 { 3_600_000 }
public fun max_deadline_duration(): u64 { 31_536_000_000 }
public fun min_grace_period(): u64 { 3_600_000 }
public fun default_grace_period(): u64 { 86_400_000 }
public fun current_version(): u64 { 1 }

// === 錯誤碼 ===
public fun e_insufficient_escrow(): u64 { 0 }
public fun e_deadline_too_soon(): u64 { 1 }
public fun e_deadline_too_far(): u64 { 2 }
public fun e_cleanup_bps_too_high(): u64 { 3 }
public fun e_title_too_long(): u64 { 4 }
public fun e_title_empty(): u64 { 5 }
public fun e_description_too_long(): u64 { 6 }
public fun e_bounty_not_open(): u64 { 7 }
public fun e_max_claims_reached(): u64 { 8 }
public fun e_insufficient_stake(): u64 { 9 }
public fun e_deadline_passed(): u64 { 10 }
public fun e_creator_cannot_claim(): u64 { 11 }
public fun e_already_claimed(): u64 { 12 }
public fun e_not_creator(): u64 { 13 }
public fun e_bounty_not_cancellable(): u64 { 14 }
public fun e_insufficient_escrow_for_penalty(): u64 { 15 }
public fun e_invalid_verifier_cap(): u64 { 16 }
public fun e_hunter_not_active(): u64 { 17 }
public fun e_insufficient_escrow_for_reward(): u64 { 18 }
public fun e_not_ticket_owner(): u64 { 19 }
public fun e_grace_period_not_passed(): u64 { 20 }
public fun e_bounty_not_active(): u64 { 21 }
public fun e_max_claims_zero(): u64 { 22 }
public fun e_reward_amount_zero(): u64 { 23 }
public fun e_max_claims_too_high(): u64 { 24 }
public fun e_bounty_not_terminal(): u64 { 25 }
public fun e_ticket_bounty_mismatch(): u64 { 26 }
public fun e_hunter_not_approved(): u64 { 27 }
public fun e_bounty_not_cancelled(): u64 { 28 }
public fun e_hunters_not_withdrawn(): u64 { 29 }
public fun e_abandon_after_deadline(): u64 { 30 }
public fun e_too_many_metadata(): u64 { 31 }
public fun e_metadata_value_too_long(): u64 { 32 }
public fun e_already_approved(): u64 { 33 }
public fun e_overflow(): u64 { 34 }
public fun e_grace_period_too_short(): u64 { 35 }

// === Proof 狀態碼 ===
public fun proof_submitted(): u8 { 10 }
public fun proof_approved(): u8 { 11 }
public fun proof_rejected(): u8 { 12 }
public fun proof_disputed(): u8 { 13 }
public fun proof_resolved_approved(): u8 { 14 }
public fun proof_resolved_rejected(): u8 { 15 }

// === Review period ===
public fun default_review_period(): u64 { 259_200_000 }    // 3 days
public fun min_review_period(): u64 { 3_600_000 }          // 1 hour
public fun max_review_period(): u64 { 604_800_000 }        // 7 days

// === Proof 上限 ===
public fun max_proof_url_length(): u64 { 512 }
public fun max_proof_description_length(): u64 { 2048 }
public fun max_reason_length(): u64 { 1024 }

// === Proof 錯誤碼 ===
public fun e_proof_already_submitted(): u64 { 36 }
public fun e_hunter_not_claimed(): u64 { 37 }
public fun e_no_proof_submitted(): u64 { 38 }
public fun e_proof_not_submitted(): u64 { 39 }
public fun e_proof_not_rejected(): u64 { 40 }
public fun e_proof_not_disputed(): u64 { 41 }
public fun e_review_period_not_expired(): u64 { 42 }
public fun e_already_auto_approved(): u64 { 43 }
public fun e_invalid_review_period(): u64 { 44 }
public fun e_proof_url_empty(): u64 { 45 }
public fun e_proof_url_too_long(): u64 { 46 }
public fun e_rejection_reason_empty(): u64 { 47 }
public fun e_dispute_reason_empty(): u64 { 48 }
public fun e_resubmit_exhausted(): u64 { 49 }
public fun e_reason_too_long(): u64 { 50 }
public fun e_review_window_expired(): u64 { 51 }

// === v4 Arbitrator / Withdraw 錯誤碼 ===
public fun e_not_arbitrator(): u64 { 52 }
public fun e_creator_is_arbitrator(): u64 { 53 }
public fun e_dispute_timeout_too_short(): u64 { 55 }
public fun e_dispute_timeout_too_long(): u64 { 56 }
public fun e_dispute_not_timed_out(): u64 { 57 }
public fun e_hunter_has_active_proof(): u64 { 58 }
public fun e_hunter_is_approved(): u64 { 59 }
public fun e_no_dispute_timestamp(): u64 { 60 }

// === Dispute timeout ===
public fun default_dispute_timeout(): u64 { 604_800_000 }   // 7 days
public fun min_dispute_timeout(): u64 { 86_400_000 }        // 1 day
public fun max_dispute_timeout(): u64 { 2_592_000_000 }     // 30 days

// === v5 Task Types ===
public fun task_type_custom(): u8 { 0 }
public fun task_type_kill(): u8 { 1 }
public fun task_type_delivery(): u8 { 2 }
public fun task_type_build(): u8 { 3 }
public fun task_type_intel(): u8 { 4 }

// === v5 Verification Modes ===
public fun verify_mode_auto(): u8 { 0 }
public fun verify_mode_oracle(): u8 { 1 }
public fun verify_mode_seal(): u8 { 2 }
public fun verify_mode_manual(): u8 { 3 }

// === v5 Intel Limits ===
public fun max_intel_payload_size(): u64 { 4096 }

// === v5 Task Type Error Codes ===
public fun e_invalid_task_type(): u64 { 61 }
public fun e_task_type_already_set(): u64 { 62 }
public fun e_task_type_requires_open(): u64 { 63 }
public fun e_task_type_has_active_claims(): u64 { 64 }
public fun e_wrong_task_type(): u64 { 65 }
public fun e_criteria_already_set(): u64 { 66 }
public fun e_missing_criteria(): u64 { 67 }

// === v5 Kill Verify Error Codes ===
public fun e_not_killer(): u64 { 68 }
public fun e_killmail_too_old(): u64 { 69 }
public fun e_solar_system_mismatch(): u64 { 70 }
public fun e_loss_type_mismatch(): u64 { 71 }
public fun e_killmail_already_used(): u64 { 72 }
public fun e_character_mismatch(): u64 { 73 }

// === v5 Oracle Error Codes ===
public fun e_not_registry_admin(): u64 { 74 }
public fun e_oracle_not_active(): u64 { 75 }
public fun e_oracle_already_registered(): u64 { 76 }
public fun e_invalid_attestation(): u64 { 77 }
public fun e_nonce_already_used(): u64 { 78 }
public fun e_attestation_bounty_mismatch(): u64 { 79 }
public fun e_attestation_hunter_mismatch(): u64 { 80 }

// === v5 Intel Error Codes ===
public fun e_intel_payload_too_large(): u64 { 81 }
public fun e_intel_payload_empty(): u64 { 82 }
public fun e_intel_already_posted(): u64 { 83 }
public fun e_intel_not_posted(): u64 { 84 }
public fun e_not_intel_creator(): u64 { 85 }
public fun e_intel_already_confirmed(): u64 { 86 }

// === v5 Build Verify Error Codes ===
public fun e_not_assembly_owner(): u64 { 87 }

// === v5 Delivery Verify Error Codes ===
public fun e_delivery_quantity_insufficient(): u64 { 88 }
public fun e_delivery_item_mismatch(): u64 { 89 }
public fun e_delivery_target_mismatch(): u64 { 90 }

// === v5 Seal Error Codes ===
public fun e_seal_namespace_too_short(): u64 { 91 }
public fun e_seal_namespace_mismatch(): u64 { 92 }
public fun e_oracle_pubkey_invalid(): u64 { 93 }

// === v7 Error Codes ===
public fun e_victim_mismatch(): u64 { 94 }
public fun e_encrypted_details_already_set(): u64 { 95 }
public fun e_encrypted_details_not_set(): u64 { 96 }
public fun e_encrypted_payload_too_large(): u64 { 97 }
public fun e_criteria_encrypted_manual_only(): u64 { 98 }

// === v7 Limits ===
public fun max_encrypted_details_size(): u64 { 4096 }
