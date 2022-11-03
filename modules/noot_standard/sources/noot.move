module noot::noot {
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::vec_map::{Self, VecMap};
    use sui::dynamic_object_field;
    use sui::dynamic_field;
    use std::string::{Self, String};
    use std::vector;
    use noot::inventory::{Self, Inventory};

    const EBAD_WITNESS: u64 = 0;
    const ENOT_OWNER: u64 = 1;
    const ENO_TRANSFER_PERMISSION: u64 = 2;
    const EWRONG_TRANSFER_CAP: u64 = 3;
    const ETRANSFER_CAP_ALREADY_EXISTS: u64 = 4;
    const EINSUFFICIENT_FUNDS: u64 = 5;
    const EINCORRECT_DATA_REFERENCE: u64 = 6;
    const EEMPTY_SHARED_WRAPPER: u64 = 7;

    // World is the world from which the noot originates; its native world. This is a witness struct that can be
    // produced only by the module that created the world, such as 'Minecraft' or 'Outlaw_Sky'.
    // M is a witness struct produced by the market-module, which defines how the noot may be transferred
    // Note that Noots must have 'store', otherwise they cannot be added to another noot's inventory, or
    // wrapped inside of a SharedWrapper.
    // Unfortunately, this also enables polymorphic transfer on noots; however polymorphic transfer
    // simply changes the writer (Sui-defined owner) and does not change noot.owner (the module-defined
    // owner), which is what really matters.
    // When Noots are stored in an inventory, their owner becomes option::none
    struct Noot<phantom World, phantom Market> has key, store {
        id: UID,
        owner: option::Option<address>,
        quantity: u64,
        transfer_cap: option::Option<TransferCap<World, Market>>,
        family_key: vector<u8>,
        inventory: Inventory
    }

    // TODO: Replace VecMap with a more efficient data structure once one becomes a available within Sui
    // VecMap only has O(N) lookup time, which is better than an actual map up until about 100 items.
    //
    // These are always stored inside another struct, never left alone outside.
    // Stored Object
    // Should this be typed by World as well?
    struct NootData<Data: store + copy + drop> has store, copy, drop {
        display: VecMap<String, String>,
        body: Data
    }

    // Only one of these will exist per noot family T, and a module can only create one noot family.
    // Every noot family consists of 'members', which can have arbitrary data-types D. 
    // The FamilyConfig acts as a template, specifying the default display and default data for each
    // noot family member.
    // The WorldConfig also stores its own 'display', which can specify various information (name,
    // website, description) about the family as a whole.
    // Can be owned, shared, frozen, or stored. Cannot be deleted.
    // Because of this, the owner can arbitrarily do whatever it wants using sui::transfer
    struct WorldConfig<phantom World> has key, store {
        id: UID,
        display: VecMap<String, String>
    }

    // Does this need a World type?
    struct TransferCap<phantom World, phantom Market> has key, store {
        id: UID,
        for: ID
    }

    // Reserved key, spaced by world, to avoid collisions
    struct DataKey<phantom World> has store, copy, drop {}

    // wraps family_key and adds a world-namespace (a witness type). This prevents key-collisions
    struct Key<phantom World> has store, copy, drop { 
        raw_key: vector<u8>
    }

    // Shared object
    struct SharedWrapper<phantom F, phantom M> has key {
        id: UID,
        noot: Option<Noot<F, M>>
    }

    // === Events ===

    // TODO: add events

    // === Admin Functions, for Noot Creators ===

    // A module will define a noot type, using the witness pattern. This is a droppable
    // type

    // Can only be called with a `one-time-witness` type, ensuring that there will only ever be one WorldConfig
    // per `Family`.
    public fun create_world<W: drop, F: drop>(
        one_time_witness: W,
        _native_family: F,
        ctx: &mut TxContext
    ): WorldConfig<F> {
        assert!(sui::types::is_one_time_witness(&one_time_witness), EBAD_WITNESS);

        // TODO: add events
        // event::emit(CollectionCreated<T> {});

        WorldConfig<F> {
            id: object::new(ctx),
            display: vec_map::empty<String, String>()
        }
    }

    public entry fun craft_<T: drop, M: drop, D: store + copy + drop>(
        witness: T, 
        send_to: address,
        quantity: u64,
        family_key: vector<u8>,
        data: Option<NootData<D>>,
        ctx: &mut TxContext) 
    {
        let noot = craft<T, M, D>(witness, option::some(send_to), quantity, family_key, data, ctx);
        transfer::transfer(noot, send_to);
    }

    public fun craft<T: drop, M: drop, D: store + copy + drop>(
        _witness: T,
        owner: Option<address>,
        quantity: u64,
        family_key: vector<u8>,
        data_maybe: Option<NootData<D>>,
        ctx: &mut TxContext): Noot<T, M> 
    {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);

        let noot = Noot {
            id: uid,
            owner,
            quantity,
            transfer_cap: option::some(TransferCap<T, M> { id: object::new(ctx), for: id }),
            family_key,
            inventory: inventory::empty(ctx)
        };

        if (option::is_some(&data_maybe)) {
            let data = option::destroy_some(data_maybe);
            dynamic_field::add(&mut noot.id, DataKey<T> {}, data);
        } else { option::destroy_none(data_maybe) };

        noot
    }

    public fun create_data<D: store + copy + drop>(display: VecMap<String, String>, body: D): NootData<D> {
        NootData { display, body }
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
    public fun deconstruct<T: drop, M>(_witness: T, noot: Noot<T, M>): Inventory {
        assert!(is_fully_owned(&noot), ENO_TRANSFER_PERMISSION);

        let Noot { id, owner: _, quantity: _, transfer_cap, family_key: _, inventory } = noot;
        object::delete(id);

        let TransferCap { id, for: _ } = option::destroy_some(transfer_cap);
        object::delete(id);

        inventory
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
    public fun extract_transfer_cap<T: drop, M: drop>(
        _witness: M, 
        noot: Noot<T, M>,
        ctx: &mut TxContext
    ): TransferCap<T, M> {
        assert!(is_fully_owned(&noot), ENO_TRANSFER_PERMISSION);

        let transfer_cap = option::extract(&mut noot.transfer_cap);
        let shared_wrapper = SharedWrapper {
            id: object::new(ctx),
            noot: option::some(noot)
        };
        transfer::share_object(shared_wrapper);

        transfer_cap
    }

    // === Transfers restricted to using the Transfer-Cap ===

    // This changes the owner, but does not take possession of it
    public entry fun transfer_with_cap<T: drop, M: drop>(
        transfer_cap: &TransferCap<T, M>,
        shared_wrapper: &mut SharedWrapper<T, M>,
        new_owner: address)
    {
        let noot = option::borrow_mut(&mut shared_wrapper.noot);
        assert!(is_correct_transfer_cap(noot, transfer_cap), ENO_TRANSFER_PERMISSION);
        noot.owner = option::some(new_owner);
    }

    // Noots cannot exist outside of shared_wrapper without their transfer_cap inside of them
    public fun take_with_cap<W, M>(
        shared_wrapper: &mut SharedWrapper<W, M>, 
        transfer_cap: TransferCap<W, M>, 
        new_owner: Option<address>
    ): Noot<W, M> {
        let noot = option::extract(&mut shared_wrapper.noot);
        assert!(is_correct_transfer_cap(&noot, &transfer_cap), EWRONG_TRANSFER_CAP);
        assert!(!is_fully_owned(&noot), ETRANSFER_CAP_ALREADY_EXISTS);
        option::fill(&mut noot.transfer_cap, transfer_cap);
        noot.owner = new_owner;

        noot
    }

    public entry fun take_and_transfer<W, M>(shared_wrapper: &mut SharedWrapper<W, M>, transfer_cap: TransferCap<W, M>, new_owner: address) {
        let noot = take_with_cap(shared_wrapper, transfer_cap, option::some(new_owner));
        transfer::transfer(noot, new_owner);
    }

    // These accessors are necessary while a noot is shared (missing its transfer cap). This allows noots to be used
    // as usual, albeit with an extra wrapping-function around it to get the proper reference
    public fun borrow_shared<W, M>(shared_wrapper: &SharedWrapper<W, M>, ctx: &TxContext): &Noot<W, M> {
        assert!(option::is_some(&shared_wrapper.noot), EEMPTY_SHARED_WRAPPER);
        let noot = option::borrow(&shared_wrapper.noot);

        assert!(is_owner(tx_context::sender(ctx), noot), ENOT_OWNER);
        noot
    }

    public fun borrow_shared_mut<W, M>(shared_wrapper: &mut SharedWrapper<W, M>, ctx: &TxContext): &mut Noot<W, M> {
        assert!(option::is_some(&shared_wrapper.noot), EEMPTY_SHARED_WRAPPER);
        let noot = option::borrow_mut(&mut shared_wrapper.noot);

        assert!(is_owner(tx_context::sender(ctx), noot), ENOT_OWNER);
        noot
    }

    // === Transfers restricted to using a witness ===
    // So long as the defining module keeps its witness private, these functions can only be used
    // by the defining module. No transfer-cap needed.
    // This is a very powerful function, in that it allows modules to transfer their own noots
    // arbitrarily.

    // This transfer function should be used, rather than the polymorphic transfer (sui::transfer)
    // Polymorphic transfer could result in an inconsistent state, where the writer (Sui-defined owner)
    // is not the same as the module-defined owner (noot.owner).
    public fun transfer<W: drop, M: drop>(_witness: M, noot: Noot<W, M>, new_owner: address) {
        assert!(is_fully_owned(&noot), ENO_TRANSFER_PERMISSION);

        noot.owner = option::some(new_owner);
        transfer::transfer(noot, new_owner);
    }

    // Should we allow the world, W, to do this as transfer as well?


    // === FamilyConfig Functions ===

    public fun borrow_world_display<T: drop>(world_config: &WorldConfig<T>): &VecMap<String, String> {
        &world_config.display
    }

    public fun borrow_world_display_mut<T: drop>(_witness: T, world_config: &mut WorldConfig<T>): &mut VecMap<String, String> {
        &mut world_config.display
    }

    // Note that foreign family = F in the case where you're adding members that correspond to this
    // noot family
    public fun add_world_definition<Origin: drop, W: drop, D: store + copy + drop>(
        _witness: W, 
        world_config: &mut WorldConfig<W>, 
        raw_key: vector<u8>,
        display: VecMap<String, String>,
        data: D
    ) {
        let noot_data = create_data(display, data);
        dynamic_field::add(&mut world_config.id, Key<Origin> { raw_key }, noot_data)
    }

    public fun remove_world_definition<Origin: drop, F: drop, D: store + copy + drop>(
        _witness: F, 
        world_config: &mut WorldConfig<F>, 
        raw_key: vector<u8>,
    ): (VecMap<String, String>, D) {
        let noot_data = dynamic_field::remove(&mut world_config.id, Key<Origin> { raw_key });
        let NootData<D> { display, body } = noot_data;
        (display, body)
    }

    public fun borrow_world_definition<Origin: drop, W: drop, D: store + copy + drop>(
        world_config: &WorldConfig<W>, 
        raw_key: vector<u8>,
    ): (&VecMap<String, String>, &D) {
        let noot_data = dynamic_field::borrow<Key<Origin>, NootData<D>>(&world_config.id, Key<Origin> { raw_key });
        (&noot_data.display, &noot_data.body)
    }

    public fun borrow_world_definition_mut<Origin: drop, W: drop, D: store + copy + drop>(
        _witness: W,
        world_config: &mut WorldConfig<W>, 
        raw_key: vector<u8>,
    ): (&mut VecMap<String, String>, &mut D) {
        let noot_data = dynamic_field::borrow_mut<Key<Origin>, NootData<D>>(&mut world_config.id, Key<Origin> { raw_key });
        (&mut noot_data.display, &mut noot_data.body)
    }

    // === NootData Accessors ===

    // Gets the data for a Noot inside of World W
    public fun borrow_data<Origin: drop, W: drop, M, D: store + drop + copy>(
        noot: &Noot<Origin, M>,
        world_config: &WorldConfig<W>
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
        world_config: &WorldConfig<W>
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

    // === Authority Checkers ===

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

    // TO DO: consider adding methods to deposit or remove noots specifically, and
    // set their owner to option::none when that happens
}