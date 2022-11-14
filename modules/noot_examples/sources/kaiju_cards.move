// The server sends requests to the client, asking for it to post transactions.

// Server -> Client -> DB: signs, submits itself, server observes tx, good
// Server -> Client -> Server -> DB: signs, returns signature, server submits and observes, good
// Server -> Client -> DB: sign, either submits, tx fails, bad
// Server -> Client -> X: client refuses to sign, bad
// Client -> DB: client writes and signs its own transaction, bad

module noot_examples::kaiju_cards {
    use noot::noot;

    struct Kaiju_Cards has drop {}
    
    struct Data has store, copy, drop {}

    public fun create_asset<D: store + copy + drop>(display: VecMap<String, String>, body: D, verification_hash: vector<u8>) {
        authenticate_verification_has(display, body, verification_key);
        let noot_data = noot::create_data(Outlaw_Sky {}, display, body, ctx);
        let noot = noot::craft<Outlaw_Sky, Market, TraitMap>(Outlaw_Sky {}, option::some(owner), &noot_data, ctx);
        // Create data
        // create 
    }

    public fun create_asset2(data_packed: ) {
        unpack_data
    }

    public fun destroy_asset() {}

    public fun degrade_asset<M: drop>(noot: &mut noot::Noot<Kaiju_Cards, M>) {

    }
}