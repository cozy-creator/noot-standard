module noot::noot {
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::vec_map::{Self, VecMap};
    use sui::dynamic_field;
    use std::string::{String};
    use std::vector;
    use noot::inventory::{Self, Inventory};

    const EBAD_WITNESS: u64 = 0;
    const ENOT_OWNER: u64 = 1;
    const ENO_TRANSFER_PERMISSION: u64 = 2;
    const EWRONG_TRANSFER_CAP: u64 = 3;
    const ETRANSFER_CAP_ALREADY_EXISTS: u64 = 4;
    const EINSUFFICIENT_FUNDS: u64 = 5;
    const EINCORRECT_DATA_REFERENCE: u64 = 6;
    const EEMPTY_ENTRY_NOOT: u64 = 7;

    // World is the world from which the noot originates; its native world. This is a witness struct that can be
    // produced only by the module that created the world, such as 'Minecraft' or 'Outlaw_Sky'.
    // M is a witness struct produced by the market-module, which defines how the noot may be transferred.
    //
    // Noots have key + store so that they can be stored inside of a dynamic object field, and so they have a
    // unique, stable id which can be tracked for indexing purposes.
    //
    // Noots are never allowed to be 'naked', or stored at the root level. They can only ever be wrapped inside of
    // an EntryNoot, or stored in a dynamic object field inventory of another noot.
    struct Noot<phantom World> has key, store {
        id: UID,
        quantity: u16,
        type_id: vector<u8>,
        // Data ???
        inventory: Inventory
    }

    // An EntryNoot acts like an access-wrapper for a Noot. If we didn't have this, when we pass another function
    // a noot they'd have to constantly be checking `is_owner(noot, ctx)`, which is cumbersome and prone to
    // errors. In Sui Move, it is generally assumed that if someone can obtain a mutable reference to an object,
    // or pass it by value, that they must own that object, meaning that no further permission-checking needs to
    // be done. This permission-checking is done by the Sui-runtime itself usually when an object is brought into
    // memory. We have our custom notion of ownership however.
    //
    // Unfortunately this also complicates the API a bit; if you want to get ahold of a Noot, you have to find
    // its EntryNoot first, and then call a borrow or borrow_mut function to get the actual Noot out.
    //
    // An EntryNoot is always shared and can never be stored; it's always a shared root-level object. This gives
    // the noot module strong ownership control.
    // Once shared-objects can be deleted, noot will no longer be optional here.
    struct EntryNoot<phantom World, phantom Market> has key {
        id: UID,
        owners: vector<address>,
        noot: Option<Noot<World>>,
        transfer_cap: Option<TransferCap<World, Market>>,
    }

    // A struct used to store noots in inventory
    struct NootStore<phantom World, phantom Market> has key, store {
        id: UID,
        noot: Noot<World>,
        transfer_cap: TransferCap<World, Market>,
    }

    // VecMap is not a real map; it has O(N) lookup time. However this is more efficient than actual map up until
    // about 100 items.
    // We do not bind NootData to a World type here; this allows data to be copied between worlds
    // Data is attached to this object using a dynamic field.
    struct NootData<Data: store + copy + drop> has store, copy, drop {
        display: VecMap<String, String>,
        body: Data
    }

    // Only one WorldRegistry object may exist per World. A module can only create one World.
    // Specifically, a 'World' is a witness-type object created by the world-module.
    //
    // A WorldRegistery defines a collection of 'noot types', index by their noot.type_id.
    //
    // The WorldRegistry acts as a data template, specifying the default display and data for each noot type.
    // Each noot type can have arbitrary data.
    // The WorldRegistry also stores its own `display`, which can specify various information (name, logo,
    // website, description) about the World as a whole.
    //
    // Data is attached to this using a dynamic field.
    //
    // Can be owned, shared, frozen, or stored. Can never be deleted.
    struct WorldRegistry<phantom World> has key, store {
        id: UID,
        display: VecMap<String, String>
    }

    // We bind TransferCaps to their world-types as well, to make sure that the World-module consents to
    // a noot being migrated between markets.
    struct TransferCap<phantom World, phantom Market> has key, store {
        id: UID,
        for: ID,
        claims: vector<vector<u8>>
    }

    // Reserved key, namespaced by World, to avoid collisions
    struct DataKey<phantom World> has store, copy, drop {}

    // Wraps noot.type_id and adds a world for namespacing, which prevents key-collisions between worlds.
    struct Key<phantom World> has store, copy, drop { 
        raw_key: vector<u8>
    }

    // === Events ===

    // TODO: add events

    // === Admin Functions, for World Creators ===

    // A module will define a noot type, using the witness pattern. This is a droppable
    // type

    // Can only be called with a `one-time-witness` type, ensuring that there will only ever be one WorldRegistry
    // per `Family`.
    public fun create_world<WORLD_GENESIS: drop, World: drop>(
        one_time_witness: WORLD_GENESIS,
        _witness: World,
        ctx: &mut TxContext
    ): WorldRegistry<World> {
        assert!(sui::types::is_one_time_witness(&one_time_witness), EBAD_WITNESS);

        // TODO: add events
        // event::emit(WorldCreated<T> {});

        WorldRegistry<World> {
            id: object::new(ctx),
            display: vec_map::empty<String, String>()
        }
    }

    public fun craft<World: drop, Market: drop, D: store + copy + drop>(
        _witness: World,
        owners: vector<address>,
        quantity: u16,
        type_id: vector<u8>,
        data_maybe: Option<NootData<D>>,
        ctx: &mut TxContext): EntryNoot<World, Market> 
    {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);

        let noot = Noot {
            id: uid,
            quantity,
            type_id,
            inventory: inventory::empty(ctx)
        };

        let new_noot = &mut noot;

        if (option::is_some(&data_maybe)) {
            let data = option::destroy_some(data_maybe);
            dynamic_field::add(&mut noot.id, DataKey<World> {}, data);
        } else { option::destroy_none(data_maybe) };

        EntryNoot { 
            id: object::new(ctx),
            owners,
            noot: option::some(noot),
            transfer_cap: option::some( TransferCap<World, Market> { 
                    id: object::new(ctx),
                    for: id,
                    claims: vector::empty<vector<u8>>() 
                }
            )
        }
    }

    // Destroy the noot and return its inventory
    //
    // We do not allow EntryNoots missing their transfer caps to be deconstructed
    // Only the defining-module to perform deconstruction, enforced here with a witness
    // You must also be the owner of a noot to deconstruct it.
    //
    // Note that all attached data will be lost unless it was copied prior to this
    //
    // In the future, when it's possible to delete shared objects this will fully consume the
    // EntryNoot and destroy it as well. Here we simply leave it empty forever.
    public fun deconstruct<W: drop, M>(_witness: W, entry_noot: &mut EntryNoot<W, M>, ctx: &TxContext): Inventory {
        assert!(is_fully_owned(entry_noot), ENO_TRANSFER_PERMISSION);
        assert!(is_owner(entry_noot, ctx), ENOT_OWNER);

        let (noot, transfer_cap) = extract(entry_noot);
        
        let Noot { id, quantity: _, type_id: _, inventory } = noot;
        object::delete(id);

        let TransferCap { id, for: _, claims: _ } = transfer_cap;
        object::delete(id);

        inventory
    }
    
    // === NootEntry Accessors ===

    // Aborts if the EntryNoot is empty
    // Anyone is allowed to borrow a read-reference, regardless of ownership
    public fun borrow<W, M>(entry_noot: &EntryNoot<W, M>, _ctx: &TxContext): &Noot<W> {
        option::borrow(&entry_noot.noot)
    }

    // Aborts if the EntryNoot is empty
    public fun borrow_mut<W, M>(entry_noot: &mut EntryNoot<W, M>, ctx: &TxContext): &mut Noot<W> {
        assert!(is_owner(entry_noot, ctx), ENOT_OWNER);
        option::borrow_mut(&mut entry_noot.noot)
    }

    // Private function; we do not want Noots to exist outside of EntryNoots, otherwise we could
    // lose control of their functionality.
    // In the future, this will consume the EntryNoot and deconstruct it
    fun extract<W, M>(entry_noot: &mut EntryNoot<W, M>): (Noot<W>, TransferCap<W, M>) {
        let noot = option::extract(&mut entry_noot.noot);
        let transfer_cap = option::extract(&mut entry_noot.transfer_cap);

        (noot, transfer_cap)
    }

    // This would be like a noot flash-loan; the noot must be returned to the EntryNoot by the
    // end of the transaction. I'm not sure how secure or useful this would be though?
    public fun borrow_by_value() {}

    // === Market Functions, for Noot marketplaces ===

    // Only the corresponding market-module, the module that can produce the witness M, can
    // extract the owner cap. As long as the market-module keeps the transfer_cap in its
    // possession, no other module can use it.
    public fun extract_transfer_cap<W: drop, Market: drop>(
        _witness: Market, 
        entry_noot: &mut EntryNoot<W, Market>,
        ctx: &mut TxContext
    ): TransferCap<W, Market> {
        assert!(is_owner(entry_noot, ctx), ENOT_OWNER);
        assert!(is_fully_owned(entry_noot), ENO_TRANSFER_PERMISSION);

        option::extract(&mut entry_noot.transfer_cap)
    }

    // === Transfers restricted to using the Transfer-Cap ===

    // This changes the owner and wipes any claim-marks that were on the transfer_cap
    public entry fun transfer_with_cap<W: drop, M: drop>(
        transfer_cap: &mut TransferCap<W, M>,
        entry_noot: &mut EntryNoot<W, M>,
        new_owners: vector<address>)
    {
        let noot = option::borrow_mut(&mut entry_noot.noot);
        assert!(is_correct_transfer_cap(noot, transfer_cap), ENO_TRANSFER_PERMISSION);
        entry_noot.owners = new_owners;
        transfer_cap.claims = vector::empty();
    }

    public entry fun fill_transfer_cap<W, M>(entry_noot: &mut EntryNoot<W, M>, transfer_cap: TransferCap<W, M>) {
        assert!(is_correct_transfer_cap(option::borrow(&entry_noot.noot), &transfer_cap), ENO_TRANSFER_PERMISSION);
        option::fill(&mut entry_noot.transfer_cap, transfer_cap);
    }

    // Should we allow the world module, W, to do this as transfer as well?
    // World modules should not be allowed to change ownership; only market modules can.


    // === WorldRegistry Functions ===

    public fun borrow_world_display<T: drop>(world_registry: &WorldRegistry<T>): &VecMap<String, String> {
        &world_registry.display
    }

    public fun borrow_world_display_mut<T: drop>(_witness: T, world_registry: &mut WorldRegistry<T>): &mut VecMap<String, String> {
        &mut world_registry.display
    }

    // World's can define noot-types for Worlds outside of their own:
    // Example: for the Outlaw_sky WorldRegistry, we can grant Fortnite noots their own custom display + data.
    // In this case, the foreign-world (Origin) would be Fortnite, while our World is Outlaw_Sky.
    // The WorldRegistry provides default display and data for any noot we wish
    public fun add_noot_type<Origin: drop, World: drop, D: store + copy + drop>(
        _witness: World, 
        world_registry: &mut WorldRegistry<World>, 
        raw_key: vector<u8>,
        display: VecMap<String, String>,
        data: D
    ) {
        let noot_data = create_data(display, data);
        dynamic_field::add(&mut world_registry.id, Key<Origin> { raw_key }, noot_data)
    }

    public fun remove_noot_type<Origin: drop, World: drop, D: store + copy + drop>(
        _witness: World, 
        world_registry: &mut WorldRegistry<World>, 
        raw_key: vector<u8>,
    ) {
        dynamic_field::remove<Key<Origin>, D>(&mut world_registry.id, Key<Origin> { raw_key });
    }

    public fun borrow_noot_type<Origin: drop, W: drop, D: store + copy + drop>(
        world_registry: &WorldRegistry<W>, 
        raw_key: vector<u8>,
    ): (&VecMap<String, String>, &D) {
        let noot_data = dynamic_field::borrow<Key<Origin>, NootData<D>>(&world_registry.id, Key<Origin> { raw_key });
        (&noot_data.display, &noot_data.body)
    }

    public fun borrow_noot_type_mut<Origin: drop, W: drop, D: store + copy + drop>(
        _witness: W,
        world_registry: &mut WorldRegistry<W>, 
        raw_key: vector<u8>,
    ): (&mut VecMap<String, String>, &mut D) {
        let noot_data = dynamic_field::borrow_mut<Key<Origin>, NootData<D>>(&mut world_registry.id, Key<Origin> { raw_key });
        (&mut noot_data.display, &mut noot_data.body)
    }

    // === NootData Accessors ===

    public fun create_data<D: store + copy + drop>(display: VecMap<String, String>, body: D): NootData<D> {
        NootData { display, body }
    }

    // Gets the data for a Noot inside of World W
    public fun borrow_data<Origin: drop, W: drop, D: store + drop + copy>(
        noot: &Noot<Origin>,
        world_registry: &WorldRegistry<W>
    ): (&VecMap<String, String>, &D) {
        if (dynamic_field::exists_with_type<DataKey<W>, NootData<D>>(&noot.id, DataKey<W> {})) {
            let data = dynamic_field::borrow<DataKey<W>, NootData<D>>(&noot.id, DataKey<W> {});
            (&data.display, &data.body)
        } else {
            borrow_noot_type<Origin, W, D>(world_registry, noot.type_id)
        }
    }

    // Only a world can modify its data attached to a noot
    public fun borrow_data_mut<Origin: drop, W: drop, D: store + drop + copy>(
        _witness: W,
        noot: &mut Noot<Origin>,
        world_registry: &WorldRegistry<W>
    ): &mut D {
        if (!dynamic_field::exists_with_type<DataKey<W>, NootData<D>>(&noot.id, DataKey<W> {})) {
            let (display, body) = borrow_noot_type<Origin, W, D>(world_registry, noot.type_id);
            let data_copy = create_data(*display, *body);
            dynamic_field::add(&mut noot.id, DataKey<W> {}, data_copy);
        };

        let noot_data = dynamic_field::borrow_mut<DataKey<W>, NootData<D>>(&mut noot.id, DataKey<W> {});
        &mut noot_data.body
    }

    // === Inventory Accessors ===

    public fun borrow_inventory<W>(noot: &Noot<W>): &Inventory {
        &noot.inventory
    }

    public fun borrow_inventory_mut<W>(noot: &mut Noot<W>): &mut Inventory {
        &mut noot.inventory
    }

    // These are special accessors for storing noots inside of inventories, that make sure the owner
    // field is correctly set.
    // These need to be thought out and rewritten
    public fun deposit_noot<W, M, Namespace: drop>(
        witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>,
        entry_noot: &mut EntryNoot<W, M>,
        ctx: &mut TxContext
    ) {
        let (noot, transfer_cap) = extract(entry_noot);
        let noot_store = NootStore { id: object::new(ctx), noot, transfer_cap };
        inventory::add(witness, inventory, raw_key, noot_store, ctx);
    }

    public fun withdraw_noot<W, M, Namespace: drop>(
        witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>,
        new_owners: vector<address>,
        ctx: &mut TxContext
    ) {
        let noot_store = inventory::remove<Namespace, NootStore<W, M>>(witness, inventory, raw_key, ctx);
        let NootStore { id, noot, transfer_cap } = noot_store;
        object::delete(id);

        let entry_noot = EntryNoot {
            id: object::new(ctx),
            owners: new_owners,
            noot: option::some(noot),
            transfer_cap: option::some(transfer_cap)
        };

        transfer::share_object(entry_noot);
    }

    // === Ownership Checkers ===

    public fun is_owner_addr<World, M>(entry_noot: &EntryNoot<World, M>, addr: &address): bool {
        if (vector::length(&entry_noot.owners) == 0) { return true };
        vector::contains(&entry_noot.owners, addr)
    }

    // Once multiple addresses can sign a transaction, this function will be more complex
    // If we can attach memos to the transaction-context, that would be awesome too
    public fun is_owner<World, M>(entry_noot: &EntryNoot<World, M>, ctx: &TxContext): bool {
        is_owner_addr(entry_noot, &tx_context::sender(ctx))
    }

    public fun is_fully_owned<W, M>(entry_noot: &EntryNoot<W, M>): bool {
        option::is_some(&entry_noot.transfer_cap)
    }

    public fun is_correct_transfer_cap<W, M>(noot: &Noot<W>, transfer_cap: &TransferCap<W, M>): bool {
        transfer_cap.for == object::id(noot)
    }
}