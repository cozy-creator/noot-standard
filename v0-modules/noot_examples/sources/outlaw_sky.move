module noot_examples::outlaw_sky {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::vec_map;
    use noot::noot::{Self, Noot, NootData};
    use noot::royalty_market::{Self, Market};
    use noot::coin2;
    use std::string::{Self, String};
    use std::option;

    const EINSUFFICIENT_FUNDS: u64 = 1;
    const ENOT_OWNER: u64 = 2;
    const EWRONG_DATA: u64 = 3;

    // One-time witness
    struct OUTLAW_SKY has drop {}

    // Noot-type. I'm kind of changing naming-conventions here by using Outlaw_Sky rather than
    // OutlawSky (camel case)
    struct Outlaw_Sky has drop {}

    // NOTE: this data is meant to be compact, rather than explanative. For the indexer, we'll
    // have to add some sort of file which maps data to human-readable format. Perhaps a simple
    // javascript function?
    struct TraitMap has store, copy, drop {
        traits: vec_map::VecMap<String, Trait>
    }

    struct Trait has store, copy, drop {
        base: u8,
        variant: u8
    }

    struct CraftInfo<phantom C> has key {
        id: UID,
        treasury_addr: address,
        price: u64,
        locked: bool,
        total_supply: u64,
        max_supply: u64
    }

    fun init(one_time_witness: OUTLAW_SKY, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        let noot_type_info = noot::create_type(one_time_witness, Outlaw_Sky {}, ctx);
        let royalty_cap = royalty_market::create_royalty_cap(Outlaw_Sky {}, ctx);

        let craft_info = CraftInfo<SUI> {
            id: object::new(ctx),
            treasury_addr: tx_context::sender(ctx),
            price: 10,
            locked: true,
            total_supply: 0,
            max_supply: 10000
        };

        noot::transfer_type_info(noot_type_info, addr);
        transfer::transfer(royalty_cap, addr);
        transfer::share_object(craft_info);
    }

    public entry fun craft_<C>(
        coin: Coin<C>,
        send_to: address,
        craft_info: &mut CraftInfo<C>,
        ctx: &mut TxContext)
    {
        let noot = craft(coin, send_to, craft_info, ctx);
        noot::transfer(Outlaw_Sky {}, noot, send_to);
    }

    public fun craft<C>(
        coin: Coin<C>, 
        owner: address, 
        craft_info: &mut CraftInfo<C>,
        ctx: &mut TxContext): Noot<Outlaw_Sky, Market> 
    {
        let price = *&craft_info.price;
        assert!(coin::value(&coin) >= price, EINSUFFICIENT_FUNDS);
        coin2::take_coin_and_transfer(craft_info.treasury_addr, &mut coin, price, ctx);
        coin2::refund(coin, ctx);

        let (display, body) = generate_data(ctx);

        let noot_data = noot::create_data(Outlaw_Sky {}, display, body, ctx);
        let noot = noot::craft<Outlaw_Sky, Market, TraitMap>(Outlaw_Sky {}, option::some(owner), &noot_data, ctx);

        noot::share_data(Outlaw_Sky {}, noot_data);
        noot
    }

    public fun generate_data(_ctx: &mut TxContext): (vec_map::VecMap<String, String>, TraitMap) {
        let display = vec_map::empty<String, String>();
        let url = string::utf8(b"https://website.com/some/image1000.png");
        vec_map::insert(&mut display, string::utf8(b"https:png"), url);

        let traits = vec_map::empty<String, Trait>();
        vec_map::insert(&mut traits, string::utf8(b"overlay"), Trait { base: 0, variant: 0 });
        vec_map::insert(&mut traits, string::utf8(b"headwear"), Trait { base: 0, variant: 0 });
        vec_map::insert(&mut traits, string::utf8(b"hair"), Trait { base: 0, variant: 0 });
        vec_map::insert(&mut traits, string::utf8(b"earrings"), Trait { base: 0, variant: 0 });
        
        let body = TraitMap {
            traits
        };

        (display, body)
    }

    // This would allow owners of a noot to modify their data arbitrarily
    public entry fun modify_data<M>(noot: &Noot<Outlaw_Sky, M>, noot_data: &mut NootData<Outlaw_Sky, TraitMap>, key: String, base: u8, variant: u8, ctx: &mut TxContext) {
        // Make sure the transaction sender owns the noot
        assert!(noot::is_owner(tx_context::sender(ctx), noot), ENOT_OWNER);
        // Make sure the data corresponds to the noot
        assert!(noot::is_correct_data(noot, noot_data), EWRONG_DATA);

        let body_ref = noot::borrow_data_body(Outlaw_Sky {}, noot_data);

        if (vec_map::contains(&body_ref.traits, &key)) {
            let (_old_key, old_trait) = vec_map::remove(&mut body_ref.traits, &key);
            let Trait { base: _, variant: _ } = old_trait;
        };

        vec_map::insert(&mut body_ref.traits, key, Trait { base, variant });
    }
}