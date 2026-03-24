module bounty_escrow::escrow;

use sui::balance::Balance;
use sui::coin::{Self, Coin};

/// Lock `amount` from `coin` into `balance`. Returns change back as Coin.
public(package) fun lock<T>(
    bal: &mut Balance<T>,
    coin: Coin<T>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    let mut coin_bal = coin.into_balance();
    let locked = coin_bal.split(amount);
    bal.join(locked);
    coin_bal.into_coin(ctx)
}

/// Release `amount` from `balance` and send as Coin to `recipient`.
public(package) fun release_to<T>(
    bal: &mut Balance<T>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::take(bal, amount, ctx);
    transfer::public_transfer(coin, recipient);
}

/// Release entire balance to `recipient`.
public(package) fun release_all<T>(
    bal: &mut Balance<T>,
    recipient: address,
    ctx: &mut TxContext,
) {
    let amount = bal.value();
    if (amount > 0) {
        release_to(bal, amount, recipient, ctx);
    };
}

/// Transfer `amount` from one balance to another.
public(package) fun transfer_between<T>(
    from: &mut Balance<T>,
    to: &mut Balance<T>,
    amount: u64,
) {
    let chunk = from.split(amount);
    to.join(chunk);
}

/// Calculate cleanup reward using u128 intermediate to prevent overflow.
/// Returns max(result, 1) when bps > 0 and total > 0, else 0.
public(package) fun calculate_cleanup_reward(total: u64, bps: u16): u64 {
    if (bps == 0 || total == 0) return 0;
    let result = ((total as u128) * (bps as u128) / 10000u128) as u64;
    if (result == 0) 1 else result
}
