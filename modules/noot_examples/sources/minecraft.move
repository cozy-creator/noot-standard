// Create stackable noots (wood) and then use it to craft a campfire
// Noots can be used across servers

module noot_examples::minecraft {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use noot::noot::{Self, Noot, NootData, NootFamilyData};
    use noot::royalty_market::Market;
    use std::string::{Self, String};
    use sui::dynamic_object_field;
    use sui::vec_map;

    const ENOT_SERVER_ADMIN: u64 = 1;

    // One-time witness
    struct MINECRAFT has drop {}

    // witness
    struct Minecraft has drop {}

    struct Server has key {
        id: UID
    }

    struct Wood {}

    // Has the right to issue resources from the server
    struct ServerCap has key {
        id: UID,
        for: ID
    }

    // Has the right to generate servers
    struct MajongStudiosCap has key, store {
        id: UID
    }

    struct WorldResource has key, store {
        id: UID,
        name: String,
        amount: u64
    }

    struct GameConfig has key {
        id: UID
    }

    struct WoodData has store, copy, drop {
        durability_remaining: u64
    }

    fun init(one_time_witness: MINECRAFT, ctx: &mut TxContext) {
        let majong = MajongStudiosCap { id: object::new(ctx) };
        transfer::transfer(majong, tx_context::sender(ctx));

        let noot_family = noot::create_family(one_time_witness, Minecraft {}, ctx);
        let family_display = noot::borrow_family_data_mut(Minecraft {}, &mut noot_family);
        vec_map::insert(family_display, string::utf8(b"name"), string::utf8(b"Minecraft"));

        // First wood type
        let display = vec_map::empty();
        vec_map::insert(&mut display, string::utf8(b"name"), string::utf8(b"oak"));
        noot::add_family_data(Minecraft {}, 
            &mut noot_family, 
            b"oak_data",
            display, 
            WoodData { durability_remaining: 100 }, 
            ctx);
        
        // Second wood type
        let display = vec_map::empty();
        vec_map::insert(&mut display, string::utf8(b"name"), string::utf8(b"spruce"));
        noot::add_family_data(Minecraft {}, 
            &mut noot_family, 
            b"spruce_data",
            display, 
            WoodData { durability_remaining: 70 }, 
            ctx);

        transfer::freeze_object(noot_family);
    }

    // Only Majong can create a server on behalf of an owner
    public fun create_server(_majong: &MajongStudiosCap, owner: address, ctx: &mut TxContext) {
        let server_uid = object::new(ctx);
        let server_id = object::uid_to_inner(&server_uid);
        let server = Server { id: server_uid };

        let key = string::utf8(b"oak");
        dynamic_object_field::add(&mut server.id, key, WorldResource {
            id: object::new(ctx),
            name: key,
            amount: 64
        });

        let key = string::utf8(b"spruce");
        dynamic_object_field::add(&mut server.id, key, WorldResource {
            id: object::new(ctx),
            name: key,
            amount: 64
        });

        let server_admin = ServerCap { id: object::new(ctx), for: server_id };

        transfer::share_object(server);
        transfer::transfer(server_admin, owner);
    }

    // Only the server can generate wood and give it a player
    public entry fun craft_wood(
        server_admin: &ServerCap,
        server: &mut Server,
        amount: u64,
        family_data: &NootFamilyData<Minecraft>,
        for: address,
        ctx: &mut TxContext)
    {
        assert!(is_correct_server_cap(server_admin, server), ENOT_SERVER_ADMIN);
        let spruce_resource = dynamic_object_field::borrow_mut<String, WorldResource>(&mut server.id, string::utf8(b"oak"));

        // Will abort if amount > spruce_resource.amount remaining
        spruce_resource.amount = spruce_resource.amount - amount;

        let oak_data_ref = noot::borrow_family_data(family_data, b"oak");

        noot::craft_<Minecraft, Market, WoodData>(Minecraft {}, for, oak_data_ref, ctx);
    }

    // Only a user can damage their own wood
    public entry fun damage_wood(
        wood: Noot<Minecraft, Market>,
        game_config: &GameConfig,
        damage: u64,
        ctx: &mut TxContext)
    {
        let default_data = dynamic_object_field::borrow<vector<u8>, NootData<Minecraft, WoodData>>(&game_config.id, b"spruce_data");
        let (_display, body) = noot::borrow_data_mut(&mut wood, default_data, ctx);

        // destroy wood
        if (damage >= body.durability_remaining) {
            noot::deconstruct(Minecraft {}, wood);
        } else {
            body.durability_remaining = body.durability_remaining - damage;
            transfer::transfer(wood, tx_context::sender(ctx));
        };
    }

    public fun is_correct_server_cap(server_admin: &ServerCap, server: &Server): bool {
        (server_admin.for == object::uid_to_inner(&server.id))
    }
}