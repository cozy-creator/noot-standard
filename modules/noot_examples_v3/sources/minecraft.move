// Create stackable noots (wood) and then use it to craft a campfire
// Noots can be used across servers

module noot_examples::minecraft {
    use noot::noot;

    // One-time witness
    struct MINECRAFT has drop {}

    // noot-family witness
    struct Minecraft has drop {}

    struct MajongAuth has key, store {
        id: UID
    }

    fun init(one_time_witness: MINECRAFT, ctx: &mut TxContext) {
        private_function()
        let majong = MajongAuth { id: object::new(ctx) };
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


}