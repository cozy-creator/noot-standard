module noot_examples::outlaw_sky {
    use std::string::{utf8, String};
    use std::option::{Self, Option};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use metadata::metadata;
    use noot::noot;

    // One-time witness
    struct OUTLAW_SKY has drop {}
    
    // Guardian witness
    struct Outlaw_Sky has drop {}

    // To do: replace Strings with URL types; improve URL to use utf8 not ascii
    struct ProjectData has store, drop {
        name: String,
        description: String,
        logo: String,
        interface: Option<String>,
        homepage: Option<String>
    }

    public fun craft() {

    }

    // =========== Admin Functions ===========

    fun init(one_time_witness: OUTLAW_SKY, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);
        let craft_cap = noot::create_world(one_time_witness, Outlaw_Sky {}, ctx);
        noot::destroy_craft_cap(craft_cap);
    }

    public entry fun set_metadata(metadata: &mut Metadata<OUTLAW_SKY>, _project-bytes: vector<u8>) {
        let project_data = ProjectData {
            name: utf8(b"Outlaw Sky"),
            description: utf8(b"Welcome to the meta future"),
            logo: utf8(b"https://pbs.twimg.com/profile_images/1569727324081328128/7sUnJvRg_400x400.jpg"),
            interface: option::none<String>(),
            homepage: option::some(utf8(b"https://twitter.com/outlaw_sky"))
        };

        metadata::add_type<OUTLAW_SKY, OUTLAW_SKY, ProjectData>(metadata, project_data);
    }
}