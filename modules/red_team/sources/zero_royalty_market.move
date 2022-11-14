// Red Team's objective: produce a market that bypasses' royalty_market's royalty payment

// Method 1: wrap noot::transfer with a custom payment system
// Method 2: take royalty_market::SellOffer, create a private offer with a price of 0 SUI...? (store-wrapping? Private-offer for?)
// Method 3: take royalty_market::SellOffer, and put it for sale with an exotic coin that only your module can supply. This way royalties are meaningless, and you effectively have private offers.

module red_team::zero_royalty_market {
    use noot::royalty_market;
    use noot::noot::Noot;
    use sui::transfer;
    use sui::object;
    use sui::coin::{Self, Coin};

    struct SpecialCoin has drop {}

    struct PrivateSale<phantom C> has key {
        id: object::UID,
        price: u64,
        pay_to: address,
        offer: royalty_market::SellOffer
    }

    struct PurchaseSpec<phantom C> has key {
        id: object::UID,
        for: object::ID,
        seller: address,
        amount: u64
    }

    public fun sell_wrapper<C, T>(noot: Noot<T, royalty_market::Market>, royalty: &Royalty<T>, price: u64, pay_to: address, ctx: &mut TxContext) {
        let sell_offer = royalty_market::create_sell_offer_<C, T>(0, noot, royalty, 0, ctx);
        let private_sale = PrivateSale<C> {
            id: object::new(ctx),
            price,
            pay_to,
            offer: sell_offer
        };
        transfer::share_object(private_sale);
    }

    // Exchange is atomic
    // Noot cannot be taken back
    // 
    public fun fill_private_sale<C, T>(private_sale: &mut PrivateSale, coin: Coin<C>, royalty: &Royalty<T>, shared_wrapper: &mut noot::SharedWrapper<T, royalty_market::Market>, ctx: &mut TxContext) {
        transfer::transfer(coin, private_sale.pay_to);
        let transfer_cap = royalty_market::fill_sell_offer<C, T>(&mut private_sale.offer, coin::empty<C>(), royalty, @0x0, ctx);
        noot::take_with_cap(shared_wrapper, transfer_cap, tx_context::sender(ctx));
    }

    public fun good_sale<C, T>(private_sale: &mut PrivateSale, coin: Coin<C>, royalty: &Royalty<T>, shared_wrapper: &mut noot::SharedWrapper<T, royalty_market::Market>, ctx: &mut TxContext) {
        let transfer_cap = royalty_market::fill_sell_offer<C, T>(&mut private_sale.offer, coin, royalty, @0x0, ctx);
        noot::take_with_cap(shared_wrapper, transfer_cap, tx_context::sender(ctx));
    }

    // quantity is a hash = commitment(v, r)
    // after the noot is transferred, you can reveal its true quantity by revealing v and r for real.
    public fun transfer<T, M>(noot: Noot<T, M>, recipient: address, quantity: vector<u8>, ctx: &mut TxContext) {
        is_valid_committment(quantity);
        let (noot1, noot2) = noot::split(noot, quantity);
        noot1.owner = recipient;
        transfer::transfer(noot1, recipient);

        noot2.owner = tx_context::sender(ctx);
        transfer::transfer(noot2, recipient);
    }

    public fun reveal_quantity<T, M>(noot: Noot<T, M>, value: u64, r: vector<u8>, ctx: &TxContext) {
        check_committment(noot.quantity, value, r);
        noot.quantity = value;
        if (quantity == 0) {
            noot::deconstruct(noot);
        } else {
            transfer::transfer(noot, tx_context::sender(ctx));
        }
    }

    public fun special_coin_wrapper<C, T>(sell_offer: &mut market::SellOffer<SpecialCoin, T>, purchase_spec: &PurchaseSpec<C>, coin: Coin<C>, royalty: &Royalty<T>, ctx: &TxContext) {
        // I can't guarantee that purchase_spec.for == SellOffer.uid, or SellOffer.noot.id, because I cannot
        // inspect SellOffer at all. Therefore, whoever presents this transction can set purchase_spec.seller to
        // be themselves or one of their multiple accounts, and hence steal the SellOffer funds
        transfer::transfer(coin, purchase_spec.seller);
    }

    public fun special_coin_buy(sell_offer: &mut market::SellOffer<SpecialCoin, T>, coin: Coin<SpecialCoin>, royalty: &Royalty<T>, ctx: &TxContext) {
        transfer::transfer(coin, private_sale.pay_to);
        let transfer_cap = royalty_market::fill_sell_offer<C, T>(sell_offer, coin, royalty, @0x0, ctx);
        noot::take_with_cap(shared_wrapper, transfer_cap, tx_context::sender(ctx));
    }
}