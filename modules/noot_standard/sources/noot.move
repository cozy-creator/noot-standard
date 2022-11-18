module noot::noot {
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::vec_map::{Self, VecMap};
    use sui::dynamic_field;
    use std::string::{String};
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
    // an EntryNoot, or stored in a dynamic object field inventory.
    struct Noot<phantom World, phantom Market> has key, store {
        id: UID,
        quantity: u16,
        type_id: vector<u8>,
        transfer_cap: Option<TransferCap<World, Market>>,
        inventory: Inventory
    }

    // An EntryNoot can never be stored; it's always a root-level object. This gives the noot module strong control
    // over it. An EntryNoot can be in either single-writer or shared modes. The noot must be unwrapped and re-wrapped
    // when switching between single-writer and shared modes.
    struct EntryNoot<phantom World, phantom Market> has key {
        id: UID,
        owner: Option<address>,
        noot: Option<Noot<World, Market>>
    }

    // VecMap is not a real map; it has O(N) lookup time. However this is more efficient than actual map up until
    // about 100 items.
    // We choose not to include a World type here, so that data can be copied between worlds
    struct NootData<Data: store + copy + drop> has store, copy, drop {
        display: VecMap<String, String>,
        body: Data
    }

    // Only one WorldRegistry object may exist per World. A module can only create one World.
    // Every World consists of 'noot types', specified by their noot.type_id.
    // The WorldRegistry acts as a template, specifying the default display and data for each noot type.
    // Each noot type can have arbitrary data.
    // The WorldRegistry also stores its own 'display', which can specify various information (name,
    // website, description) about the World as a whole.
    // Can be owned, shared, frozen, or stored. Can never be deleted.
    // Because of this, the owner can arbitrarily do whatever it wants using sui::transfer
    struct WorldRegistry<phantom World> has key, store {
        id: UID,
        display: VecMap<String, String>
    }

    // Does this need a World type? We include it anyway, for security
    struct TransferCap<phantom World, phantom Market> has key, store {
        id: UID,
        for: ID
    }

    // Reserved key, namespaced by World, to avoid collisions
    struct DataKey<phantom World> has store, copy, drop {}

    // Wraps noot.type_id and adds a world for namespacing, which prevents key-collisions between worlds.
    struct Key<phantom World> has store, copy, drop { 
        raw_key: vector<u8>
    }

    // === Events ===

    // TODO: add events

    // === Admin Functions, for Noot Creators ===

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
        // event::emit(CollectionCreated<T> {});

        WorldRegistry<World> {
            id: object::new(ctx),
            display: vec_map::empty<String, String>()
        }
    }

    public fun craft<W: drop, M: drop, D: store + copy + drop>(
        _witness: W,
        owner: Option<address>,
        quantity: u16,
        type_id: vector<u8>,
        data_maybe: Option<NootData<D>>,
        ctx: &mut TxContext): EntryNoot<W, M> 
    {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);

        let noot = Noot {
            id: uid,
            quantity,
            type_id,
            transfer_cap: option::some(TransferCap<W, M> { id: object::new(ctx), for: id }),
            inventory: inventory::empty(ctx)
        };

        if (option::is_some(&data_maybe)) {
            let data = option::destroy_some(data_maybe);
            dynamic_field::add(&mut noot.id, DataKey<W> {}, data);
        } else { option::destroy_none(data_maybe) };

        EntryNoot { id: object::new(ctx), owner, noot: option::some(noot) }
    }

    // Destroy the noot and return its inventory
    //
    // We do not currently allow noots missing their transfer caps to be deconstructed
    // Only the defining-module to perform deconstruction, enforced here with a witness
    //
    // For flexibility, we allow noots to be deconstructed by someone other than the owner.
    // Defining modules should check owner permissions prior to calling this function.
    //
    // Note that all attached data will be lost unless it was copied prior to this
    //
    // In the future, when it's possible to delete shared objects this will fully consume the
    // EntryNoot and destroy it as well. Here we assume the EntryNoot is shared, and simply leave it empty
    // forever.
    public fun deconstruct<W: drop, M>(_witness: W, entry_noot: &mut EntryNoot<W, M>): Inventory {
        let noot = option::extract(&mut entry_noot.noot);
        assert!(is_fully_owned(&noot), ENO_TRANSFER_PERMISSION);

        let Noot { id, quantity: _, transfer_cap, type_id: _, inventory } = noot;
        object::delete(id);

        let TransferCap { id, for: _ } = option::destroy_some(transfer_cap);
        object::delete(id);

        inventory
    }

    public fun create_data<D: store + copy + drop>(display: VecMap<String, String>, body: D): NootData<D> {
        NootData { display, body }
    }

    // === Market Functions, for Noot marketplaces ===

    // Only the corresponding market-module, the module that can produce the witness M, can
    // extract the owner cap. As long as the market-module keeps the transfer_cap in its
    // possession, no other module can use it.
    //
    // The market should run its own check to make sure the transaction sender is the owner,
    // otherwise it could allow theft. We do not check here, to allow for the market to define
    // it's own permissioning-system
    // assert!(is_owner(tx_context::sender(ctx), &noot), ENOT_OWNER);
    public fun extract_transfer_cap<W: drop, M: drop>(
        _witness: M, 
        entry_noot: &mut EntryNoot<W, M>,
        ctx: &mut TxContext
    ): TransferCap<W, M> {
        let noot = option::borrow_mut(&mut entry_noot.noot);
        assert!(is_fully_owned(noot), ENO_TRANSFER_PERMISSION);
        option::extract(&mut noot.transfer_cap)

        // TO DO: check if the EntryNoot is shared, and if it's not, share it
        // We'll have to consume the EntryNoot to share it
        // The EntryNoot MUST be shared while the transfer_cap is missing
    }

    // === Transfers restricted to using the Transfer-Cap ===

    // This changes the owner, but does not take possession of it
    public entry fun transfer_with_cap<W: drop, M: drop>(
        transfer_cap: &TransferCap<W, M>,
        entry_noot: &mut EntryNoot<W, M>,
        new_owner: address)
    {
        let noot = option::borrow_mut(&mut entry_noot.noot);
        assert!(is_correct_transfer_cap(noot, transfer_cap), ENO_TRANSFER_PERMISSION);
        entry_noot.owner = option::some(new_owner);
    }

    // Noots cannot exist outside of entry_noot without their transfer_cap inside of them
    public fun take_with_cap<W, M>(
        entry_noot: &mut EntryNoot<W, M>, 
        transfer_cap: TransferCap<W, M>, 
        new_owner: Option<address>
    ): Noot<W, M> {
        let noot = option::extract(&mut entry_noot.noot);
        assert!(is_correct_transfer_cap(&noot, &transfer_cap), EWRONG_TRANSFER_CAP);
        assert!(!is_fully_owned(&noot), ETRANSFER_CAP_ALREADY_EXISTS);
        option::fill(&mut noot.transfer_cap, transfer_cap);
        noot.owner = new_owner;

        noot
    }

    public entry fun take_and_transfer<W, M>(entry_noot: &mut EntryNoot<W, M>, transfer_cap: TransferCap<W, M>, new_owner: address) {
        let noot = take_with_cap(entry_noot, transfer_cap, option::some(new_owner));
        transfer::transfer(noot, new_owner);
    }

    // === NootEntry Accessors ===

    // Currently, we're allowing any EntryNoot to be borrowed mutably
    // What are the security implications of this? Good or bad idea?
    public fun entry_borrow<W, M>(entry_noot: &EntryNoot<W, M>, ctx: &TxContext): &Noot<W, M> {
        assert!(option::is_some(&entry_noot.noot), EEMPTY_ENTRY_NOOT);
        let noot_ref = option::borrow(&entry_noot.noot);

        // assert!(is_owner(tx_context::sender(ctx), noot_ref), ENOT_OWNER);
        noot_ref
    }

    public fun entry_borrow_mut<W, M>(entry_noot: &mut EntryNoot<W, M>, ctx: &TxContext): &mut Noot<W, M> {
        assert!(option::is_some(&entry_noot.noot), EEMPTY_ENTRY_NOOT);
        let noot_ref = option::borrow_mut(&mut entry_noot.noot);
        assert!(is_owner(tx_context::sender(ctx), noot_ref), ENOT_OWNER);
        noot_ref
    }

    // === Transfers restricted to using a witness ===

    // So long as the market module keeps its witness private, these functions can only be used
    // by the market module. No transfer-cap needed.
    // This is a very powerful function, in that it allows market modules to transfer their own noots
    // arbitrarily.

    // This transfer function should be used, rather than the polymorphic transfer (sui::transfer)
    public fun transfer<W: drop, M: drop>(_witness: M, entry_noot: EntryNoot<W, M>, new_owner: address) {
        let noot = option::borrow_mut(&mut entry_noot.noot);
        assert!(is_fully_owned(noot), ENO_TRANSFER_PERMISSION);

        entry_noot.owner = option::some(new_owner);

        // TO DO; this will have to be consumed by value, and we'll have to tell if an object is shared or not yet
        // Right now we're assuming it's an owned-object
        transfer::transfer(entry_noot, new_owner);
    }

    // Should we allow the world module, W, to do this as transfer as well?
    // World modules should not be allowed to change ownership; only market modules can.


    // === WorldRegistry Functions ===

    public fun borrow_world_display<T: drop>(world_config: &WorldRegistry<T>): &VecMap<String, String> {
        &world_config.display
    }

    public fun borrow_world_display_mut<T: drop>(_witness: T, world_config: &mut WorldRegistry<T>): &mut VecMap<String, String> {
        &mut world_config.display
    }

    // Note that foreign family = F in the case where you're adding members that correspond to this
    // noot family
    public fun add_world_definition<Origin: drop, W: drop, D: store + copy + drop>(
        _witness: W, 
        world_config: &mut WorldRegistry<W>, 
        raw_key: vector<u8>,
        display: VecMap<String, String>,
        data: D
    ) {
        let noot_data = create_data(display, data);
        dynamic_field::add(&mut world_config.id, Key<Origin> { raw_key }, noot_data)
    }

    public fun remove_world_definition<Origin: drop, F: drop, D: store + copy + drop>(
        _witness: F, 
        world_config: &mut WorldRegistry<F>, 
        raw_key: vector<u8>,
    ): (VecMap<String, String>, D) {
        let noot_data = dynamic_field::remove(&mut world_config.id, Key<Origin> { raw_key });
        let NootData<D> { display, body } = noot_data;
        (display, body)
    }

    public fun borrow_world_definition<Origin: drop, W: drop, D: store + copy + drop>(
        world_config: &WorldRegistry<W>, 
        raw_key: vector<u8>,
    ): (&VecMap<String, String>, &D) {
        let noot_data = dynamic_field::borrow<Key<Origin>, NootData<D>>(&world_config.id, Key<Origin> { raw_key });
        (&noot_data.display, &noot_data.body)
    }

    public fun borrow_world_definition_mut<Origin: drop, W: drop, D: store + copy + drop>(
        _witness: W,
        world_config: &mut WorldRegistry<W>, 
        raw_key: vector<u8>,
    ): (&mut VecMap<String, String>, &mut D) {
        let noot_data = dynamic_field::borrow_mut<Key<Origin>, NootData<D>>(&mut world_config.id, Key<Origin> { raw_key });
        (&mut noot_data.display, &mut noot_data.body)
    }

    // === NootData Accessors ===

    // Gets the data for a Noot inside of World W
    public fun borrow_data<Origin: drop, W: drop, M, D: store + drop + copy>(
        noot: &Noot<Origin, M>,
        world_config: &WorldRegistry<W>
    ): (&VecMap<String, String>, &D) {
        if (dynamic_field::exists_with_type<DataKey<W>, NootData<D>>(&noot.id, DataKey<W> {})) {
            let data = dynamic_field::borrow<DataKey<W>, NootData<D>>(&noot.id, DataKey<W> {});
            (&data.display, &data.body)
        } else {
            borrow_world_definition<Origin, W, D>(world_config, noot.family_key)
        }
    }

    // Only a world can modify its data attached to a noot
    public fun borrow_data_mut<Origin: drop, W: drop, M, D: store + drop + copy>(
        _witness: W,
        noot: &mut Noot<Origin, M>,
        world_config: &WorldRegistry<W>
    ): &mut D {
        if (!dynamic_field::exists_with_type<DataKey<W>, NootData<D>>(&noot.id, DataKey<W> {})) {
            let (display, body) = borrow_world_definition<Origin, W, D>(world_config, noot.family_key);
            let data_copy = create_data(*display, *body);
            dynamic_field::add(&mut noot.id, DataKey<W> {}, data_copy);
        };

        let noot_data = dynamic_field::borrow_mut<DataKey<W>, NootData<D>>(&mut noot.id, DataKey<W> {});
        &mut noot_data.body
    }

    // === Inventory Accessors ===

    public fun borrow_inventory<T, M>(noot: &Noot<T, M>): &Inventory {
        &noot.inventory
    }

    public fun borrow_inventory_mut<T, M>(noot: &mut Noot<T, M>): &mut Inventory {
        &mut noot.inventory
    }

    // These are special accessors for storing noots inside of inventories, that make sure the owner
    // field is correctly set. They can be bypassed as well obviously
    public fun deposit_noot<W, M, Namespace: drop>(
        witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>,
        noot: Noot<W, M>
    ) {
        noot.owner = option::none();
        inventory::add(witness, inventory, raw_key, noot);
    }

    public fun withdraw_noot<W, M, Namespace: drop>(
        witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>,
        new_owner: Option<address>
    ): Noot<W, M> {
        let noot = inventory::remove<Namespace, Noot<W, M>>(witness, inventory, raw_key);
        noot.owner = new_owner;
        noot
    }

    // === Ownership Checkers ===

    public fun is_owner<T, M>(addr: address, noot: &Noot<T, M>): bool {
        if (option::is_some(&noot.owner)) {
            *option::borrow(&noot.owner) == addr
        } else {
            true
        }
    }

    public fun is_fully_owned<T, M>(noot: &Noot<T, M>): bool {
        option::is_some(&noot.transfer_cap)
    }

    public fun is_correct_transfer_cap<T, M>(noot: &Noot<T, M>, transfer_cap: &TransferCap<T, M>): bool {
        transfer_cap.for == object::id(noot)
    }
}