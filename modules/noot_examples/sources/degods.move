module noot_examples::degods {
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self};
    use sui::transfer;
    use sui::coin::{Coin};
    use sui::sui::SUI;
    use std::string::{Self, String};
    use std::option;
    use std::vector;
    use noot::noot::{Self, Noot};
    use noot::dispenser::{Self, Dispenser, DispenserCap};
    use noot::royalty_market::{Self, Market};

    const EINSUFFICIENT_FUNDS: u64 = 1;
    const EDISPENSER_LOCKED: u64 = 2;

    // One-time-witness; must be all-caps and same-name as the module
    struct DEGODS has drop {}

    // Noot type
    struct Degods has drop {}

    // Noot data type
    struct Traits has store, copy, drop {
        background: String,
        skin: String,
        specialty: String,
        clothes: String,
        neck: String,
        head: String,
        eyes: String,
        mouth: String,
        version: String,
        y00t: bool
    }

    // Give admin capabilities to the address that deployed this module
    fun init(witness: DEGODS, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);

        let type_info = noot::create_type(witness, Degods {}, ctx);
        let royalty_cap = royalty_market::create_royalty_cap(Degods {}, ctx);

        noot::transfer_type_info(type_info, addr);
        transfer::transfer(royalty_cap, addr);

        dispenser::create_<SUI, Traits>(10, tx_context::sender(ctx), ctx);
    }

    // This has to be called once for every noot that will be available in the container
    // So if you have a 10k collection, you must call this 10k times, supplying the noot data
    // each time.
    // You can call noot::dispenser::unload_dispenser along with the corresponding index if you
    // want to remove the data
    public entry fun load_dispenser(
        dispenser_cap: &DispenserCap<SUI, Traits>,
        dispenser: &mut Dispenser<SUI, Traits>,
        traits: vector<vector<u8>>,
        _ctx: &mut TxContext) 
    {
        let body = Traits {
            background: string::utf8(*vector::borrow(&traits, 0)),
            skin: string::utf8(*vector::borrow(&traits, 1)),
            specialty: string::utf8(*vector::borrow(&traits, 2)),
            clothes: string::utf8(*vector::borrow(&traits, 3)),
            neck: string::utf8(*vector::borrow(&traits, 4)),
            head: string::utf8(*vector::borrow(&traits, 5)),
            eyes: string::utf8(*vector::borrow(&traits, 6)),
            mouth: string::utf8(*vector::borrow(&traits, 7)),
            version: string::utf8(*vector::borrow(&traits, 8)),
            y00t: false
        };

        let display = vec_map::empty<String, String>();
        vec_map::insert(&mut display, string::utf8(b"name"), string::utf8(*vector::borrow(&traits, 9)));
        vec_map::insert(&mut display, string::utf8(b"https:png"), string::utf8(*vector::borrow(&traits, 10)));

        dispenser::load(dispenser_cap, dispenser, display, body);
    }

    public entry fun craft_(
        coin: Coin<SUI>,
        send_to: address,
        dispenser: &mut Dispenser<SUI, Traits>,
        ctx: &mut TxContext)
    {
        let noot = craft(coin, send_to, dispenser, ctx);
        noot::transfer(Degods {}, noot, send_to);
    }

    public fun craft(
        coin: Coin<SUI>,
        owner: address,
        dispenser: &mut Dispenser<SUI, Traits>,
        ctx: &mut TxContext): Noot<Degods, Market>
    {
        let (display, body) = dispenser::buy_from(coin, dispenser, ctx);

        let data = noot::create_data<Degods, Traits>(Degods {}, display, body, ctx);

        // TO DO: make sure this line's security works; it might need to be called from within the
        // market module instead
        let noot = noot::craft<Degods, Market, Traits>(Degods {}, option::some(owner), &data, ctx);

        noot::share_data(Degods {}, data);
        noot
    }
}