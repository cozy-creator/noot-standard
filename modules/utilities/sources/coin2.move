// These convenience functions will eventually be added to the sui::coin module
// For now I'm keeping them here

module noot::coin2 {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    public fun take_from_coin<C>(coin: &mut Coin<C>, value: u64, ctx: &mut TxContext): Coin<C> {
        let balance_mut = coin::balance_mut(coin);
        let sub_balance = balance::split(balance_mut, value);
        coin::from_balance(sub_balance, ctx)
    }

    public entry fun take_coin_and_transfer<C>(receiver: address, coin: &mut Coin<C>, value: u64, ctx: &mut TxContext) {
        if (value > 0) {
            let split_coin = take_from_coin<C>(coin, value, ctx);
            transfer::transfer(split_coin, receiver);
        }
    }

    // Refund the sender any extra balance they paid, or destroy the empty coin
    public entry fun refund<C>(coin: Coin<C>, ctx: &mut TxContext) {
        if (coin::value(&coin) > 0) { 
            transfer::transfer(coin, tx_context::sender(ctx));
        } else {
            coin::destroy_zero(coin);
        };
    }
    
    public entry fun refund_balance<T>(balance: Balance<T>, ctx: &mut TxContext) {
        if (balance::value(&balance) > 0) {
            transfer::transfer(coin::from_balance(balance, ctx), tx_context::sender(ctx));
        } else {
            balance::destroy_zero(balance);
        }
    }

    // Split coin `self` into multiple coins, each with balance specified
    // in `split_amounts`. Remaining balance is left in `self`.
    // public fun split_to_coin_vec<C>(self: &mut Coin<C>, split_amounts: vector<u64>, ctx: &mut TxContext): vector<Coin<C>> {
    //     let split_coin = vector::empty<Coin<C>>();
    //     let i = 0;
    //     let len = vector::length(&split_amounts);
    //     while (i < len) {
    //         let coin = take_from_coin(self, *vector::borrow(&split_amounts, i), ctx);
    //         vector::push_back(&mut split_coin, coin);
    //         i = i + 1;
    //     };
    //     split_coin
    // }
}