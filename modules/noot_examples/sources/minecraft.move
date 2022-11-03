// Create stackable noots (wood) and then use it to craft a campfire
// Noots can be used across servers

module noot_examples::minecraft {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::dynamic_object_field;
    use sui::dynamic_field;
    use sui::vec_map;
    use noot::noot::{Self, Noot, NootData, NootFamilyData};
    use noot::royalty_market::Market;
    use std::string::{Self, String};

    const ENOT_SERVER_ADMIN: u64 = 1;

    // Move does not have yet enums
    // enum for specific ithings in inventory
    const WOODEN_SWORD: vector<u8> = b"wooden_sword";
    const DIAMOND_SWORD: vector<u8> = b"diamond_sword";
    const PLANK: vector<u8> = b"plank";
    const STICK: vector<u8> = b"stick";
    const DIAMOND: vector<u8> = b"diamond";

    // enum for data-types (categories)
    const CONSTRUCTION: vector<u8> = b"construction";
    const EQUIPMENT: vector<u8> = b"equipment";
    const ITEM: vector<u8> = b"item";

    // One-time witness
    struct MINECRAFT has drop {}

    // noot-family witness
    struct Minecraft has drop {}

    struct GameConfig has key {
        id: UID
    }

    // Has the right to generate servers
    struct MajongStudiosCap has key, store {
        id: UID
    }

    // Has the right to issue resources from the server
    struct ServerCap has key {
        id: UID,
        for: ID
    }

    struct World has key {
        id: UID,
        name: String,
        seed: u64
    }

    struct WorldResource has store {
        amount: u64
    }

    struct EquipmentData has store, copy, drop { durability: u64 }
    
    struct ItemData has store, copy, drop { }

    struct ConstructionData has store, copy, drop { }

    fun init(one_time_witness: MINECRAFT, ctx: &mut TxContext) {
        let majong = MajongStudiosCap { id: object::new(ctx) };
        transfer::transfer(majong, tx_context::sender(ctx));

        let noot_family = noot::create_family(one_time_witness, Minecraft {}, ctx);
        let family_display = noot::borrow_family_data_mut(Minecraft {}, &mut noot_family);
        vec_map::insert(family_display, string::utf8(b"name"), string::utf8(b"Minecraft"));

        // This is WAY too clunky of a way to store data; consider this just an illustrative
        // placeholder until I come up with something better.

        // Wooden Sword
        let display = vec_map::empty();
        vec_map::insert(&mut display, string::utf8(b"name"), string::utf8(b"Wooden Sword"));
        vec_map::insert(&mut display, string::utf8(b"https:png"), string::utf8(b"https://hosting.com/1234.png"));
        noot::add_family_data(Minecraft {}, 
            &mut noot_family, 
            WOODEN_SWORD,
            display, 
            EquipmentData{ durability: 59 }, 
            ctx);
        
        // Diamond Sword
        let display = vec_map::empty();
        vec_map::insert(&mut display, string::utf8(b"name"), string::utf8(b"Diamond Sword"));
        vec_map::insert(&mut display, string::utf8(b"https:png"), string::utf8(b"https://hosting.com/1234.png"));
        noot::add_family_data(Minecraft {}, 
            &mut noot_family, 
            DIAMOND_SWORD,
            display, 
            EquipmentData{ durability: 1561 }, 
            ctx);

        // Stick
        let display = vec_map::empty();
        vec_map::insert(&mut display, string::utf8(b"name"), string::utf8(b"Stick"));
        vec_map::insert(&mut display, string::utf8(b"https:png"), string::utf8(b"https://hosting.com/1234.png"));
        noot::add_family_data(Minecraft {}, 
            &mut noot_family, 
            STICK,
            display, 
            ItemData{ }, 
            ctx);
        
        // Diamond 
        let display = vec_map::empty();
        vec_map::insert(&mut display, string::utf8(b"name"), string::utf8(b"Diamond"));
        vec_map::insert(&mut display, string::utf8(b"https:png"), string::utf8(b"https://hosting.com/1234.png"));
        noot::add_family_data(Minecraft {}, 
            &mut noot_family, 
            DIAMOND,
            display, 
            ItemData{ }, 
            ctx);

        // Plank
        let display = vec_map::empty();
        vec_map::insert(&mut display, string::utf8(b"name"), string::utf8(b"Plank"));
        vec_map::insert(&mut display, string::utf8(b"https:png"), string::utf8(b"https://hosting.com/1234.png"));
        noot::add_family_data(Minecraft {}, 
            &mut noot_family, 
            PLANK,
            display, 
            ConstructionData{ }, 
            ctx);
        
        transfer::freeze_object(noot_family);
    }

    // Majong generates a server and grants its server_admin priviliges to a machine, not
    // the end-user. The end-user interacts with the server, and the server updates the
    // game-state saved on-chain by posting transactions.
    public fun create_server(_majong: &MajongStudiosCap, owner: address, ctx: &mut TxContext) {
        let server_uid = object::new(ctx);
        let server_id = object::uid_to_inner(&server_uid);
        let server = World { id: server_uid, name: string::utf8(b"Bedrock"), seed: 0};
        let server_admin = ServerCap { id: object::new(ctx), for: server_id };

        // Create the world resources
        dynamic_field::add(&mut server.id, b"plank", WorldResource { amount: 500 });
        dynamic_field::add(&mut server.id, b"stick", WorldResource { amount: 100 });
        dynamic_field::add(&mut server.id, b"diamond", WorldResource { amount: 7 });

        transfer::share_object(server);
        transfer::transfer(server_admin, owner);
    }

    // Only the server can generate resources
    public entry fun generate_resource(
        server_admin: &ServerCap,
        server: &mut World,
        key: vector<u8>,
        amount: u64,
        family_data: &NootFamilyData<Minecraft>,
        for: address,
        ctx: &mut TxContext)
    {
        assert!(is_correct_server_cap(server_admin, server), ENOT_SERVER_ADMIN);
        let resource = dynamic_field::borrow_mut<vector<u8>, WorldResource>(&mut server.id, key);

        // Will abort if amount > resource.amount remaining
        resource.amount = resource.amount - amount;

        let type = key_to_type(key);

        // This also transfers the noot to the new owner 'for'
        if (type == EQUIPMENT) {
            let data_ref = noot::borrow_family_data(family_data, key);
            noot::craft_<Minecraft, Market, EquipmentData>(Minecraft {}, for, data_ref, ctx);
        } else if (type == CONSTRUCTION) {
            let data_ref = noot::borrow_family_data(family_data, key);
            noot::craft_<Minecraft, Market, ConstructionData>(Minecraft {}, for, data_ref, ctx);
        } else {
            let data_ref = noot::borrow_family_data(family_data, key);
            noot::craft_<Minecraft, Market, ItemData>(Minecraft {}, for, data_ref, ctx);
        };
    }

    // Helper function
    public fun key_to_type(key: vector<u8>): vector<u8> {
        if (key == WOODEN_SWORD || key == DIAMOND_SWORD) {
            EQUIPMENT
        } else if (key == PLANK) {
            CONSTRUCTION
        } else {
            ITEM
        }
    }

    public entry fun craft_sword() {

    }

    public fun damage_sword(
        sword: Noot<Minecraft, Market>,
        game_config: &GameConfig,
        damage: u64,
        ctx: &mut TxContext
    ) {
        let default_data = dynamic_object_field::borrow<vector<u8>, NootData<Minecraft, EquipmentData>>(&game_config.id, b"spruce_data");
        let (_display, body) = noot::borrow_data_mut(&mut sword, default_data, ctx);

        // destroy wood
        if (damage >= body.durability) {
            let inventory = noot::deconstruct(Minecraft {}, sword);
            transfer::transfer(inventory, tx_context::sender(ctx));
        } else {
            body.durability = body.durability - damage;
            transfer::transfer(sword, tx_context::sender(ctx));
        };
    }

    public fun is_correct_server_cap(server_admin: &ServerCap, server: &World): bool {
        (server_admin.for == object::uid_to_inner(&server.id))
    }
}