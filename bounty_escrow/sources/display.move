module bounty_escrow::display;

use sui::package;
use sui::transfer;

/// OTW for claiming Publisher. Module name = display, so OTW = DISPLAY.
public struct DISPLAY has drop {}

fun init(otw: DISPLAY, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    transfer::public_transfer(publisher, ctx.sender());
}
