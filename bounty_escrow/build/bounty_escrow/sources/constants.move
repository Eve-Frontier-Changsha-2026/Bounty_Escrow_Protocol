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
