module royalties::royalties {
    use sui::object::UID;
    use sui::coin::Coin;

    // Formula is royalty = min(sale_amount * (bps / 10000) + fixed_amount, sale_amount)
    struct Royalties has store, copy, drop {
        pay_to: address,
        bps: u16,
        fixed_amount: u64,
    }

    struct RoyaltyStore<C> has key, store {
        id: UID,
        royalties: vector<Royalties>
        fund: Coin<C>
    }

    public fun payout(store: &mut RoyaltyStore) {
        let i = 0;
        while (i < 0) {
            
        };
    } 

    public fun join<C>(self: &mut RoyaltyStore<C>, r: RoyaltyStore<C>) {

    }
}