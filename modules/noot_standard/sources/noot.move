module noot::noot {
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::vec_map::{Self, VecMap};
    use sui::dynamic_object_field;
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

    // Move does not yet support enums
    const DATA_KEY: vector<u8> = b"data";

    // T is the noot-family; a witness struct produced by the module creating the family, such as 
    // 'Minecraft' or 'Outlaw_Sky'
    // M is a witnes struct produced by the market-module, which defines how the noot may be transferred
    // Note that Noots must have 'store', otherwise they cannot be added to another noots inventory.
    // Unfortunately, this also enables polymorphic transfer on noots; however polymorphic transfer
    // simply changes the writer (Sui-defined owner) and does not change noot.owner (the module-defined
    // owner).
    // When Noots are stored in an inventory, their owner becomes option::none
    struct Noot<phantom T, phantom M> has key, store {
        id: UID,
        owner: option::Option<address>,
        quantity: u64,
        transfer_cap: option::Option<TransferCap<T, M>>,
        family_key: vector<u8>,
        inventory: Inventory
    }

    // TODO: Replace VecMap with a more efficient data structure once one becomes a available within Sui
    // VecMap only has O(N) lookup time, which is better than an actual map up until about 100 items.
    //
    // We do not allow the deleting of NootData after creation; we have no way of guaranteeing that there
    // isn't Noot pointing to this NootData ID. If we allowed for NootData deletion, those Noots could
    // be left pointing to null-data.
    struct NootData<phantom T, D: store + copy + drop> has key, store {
        id: UID,
        display: VecMap<String, String>,
        body: D
    }

    // Only one of these will exist per noot family T, and a module can only create one noot family.
    // Every noot family consists of 'members', which can have arbitrary data-types D. 
    // The FamilyConfig acts as a template, specifying the default display and default data for each
    // noot family member.
    // The NootFamilyConfig also stores its own 'display', which can specify various information (name,
    // website, description) about the family as a whole.
    struct NootFamilyConfig<phantom T> has key, store {
        id: UID,
        display: VecMap<String, String>
    }

    struct TransferCap<phantom T, phantom M> has store {
        for: ID
    }

    // === Events ===

    // TODO: add events

    // === Admin Functions, for Noot Creators ===

    // A module will define a noot type, using the witness pattern. This is a droppable
    // type

    // Create a new collection type `T` and return the `CraftingCap` and `RoyaltyCap` for
    // `T` to the caller. Can only be called with a `one-time-witness` type, ensuring
    // that there will only ever be one of each cap per `T`.
    public fun create_family<W: drop, T: drop>(
        one_time_witness: W,
        _type_witness: T,
        ctx: &mut TxContext
    ): NootFamilyConfig<T> {
        assert!(sui::types::is_one_time_witness(&one_time_witness), EBAD_WITNESS);

        // TODO: add events
        // event::emit(CollectionCreated<T> {});

        NootFamilyConfig<T> {
            id: object::new(ctx),
            display: vec_map::empty<String, String>()
        }
    }

    public entry fun craft_<T: drop, M: drop, D: store + copy + drop>(
        witness: T, 
        send_to: address, 
        data: Option<NootData<T, D>>,
        ctx: &mut TxContext) 
    {
        let noot = craft<T, M, D>(witness, option::some(send_to), 1, b"something", data, ctx);
        transfer::transfer(noot, send_to);
    }

    public fun craft<T: drop, M: drop, D: store + copy + drop>(
        _witness: T,
        owner: Option<address>,
        quantity: u64,
        family_key: vector<u8>,
        data_maybe: Option<NootData<T, D>>,
        ctx: &mut TxContext): Noot<T, M> 
    {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);

        let noot = Noot {
            id: uid,
            owner,
            quantity,
            transfer_cap: option::some(TransferCap<T, M> {
                for: id
            }),
            family_key,
            inventory: inventory::empty(ctx)
        };

        if (option::is_some(&data_maybe)) {
            let data = option::destroy_some(data_maybe);
            dynamic_object_field::add(&mut noot.id, DATA_KEY, data);
        } else { option::destroy_none(data_maybe) };

        noot
    }

    public fun create_data<T: drop, D: store + copy + drop>(
        _witness: T,
        display: VecMap<String, String>,
        body: D,
        ctx: &mut TxContext): NootData<T, D> 
    {
        NootData {
            id: object::new(ctx),
            display,
            body
        }
    }

    // Destroy the noot and return its inventory
    //
    // We do not currently allow noots missing their transfer caps to be deconstructed
    // Only the defining-module to perform deconstruction, enforced here with a witness
    //
    // For flexibility, we allow noots to be deconstructed by someone other than the owner.
    // Defining modules should check owner permissions prior to calling this function.
    public fun deconstruct<T: drop, M>(_witness: T, noot: Noot<T, M>): Inventory {
        assert!(is_fully_owned(&noot), ENO_TRANSFER_PERMISSION);

        let Noot { id, owner: _, quantity: _, transfer_cap, family_key: _, inventory } = noot;
        let TransferCap { for: _ } = option::destroy_some(transfer_cap);
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
        noot: Noot<T, M>): TransferCap<T, M>
    {
        assert!(is_fully_owned(&noot), ENO_TRANSFER_PERMISSION);

        let transfer_cap = option::extract(&mut noot.transfer_cap);
        transfer::share_object(noot);

        transfer_cap
    }

    // In the future, when Sui supports destroying multi-writer objects, this function will completely
    // consume the noot, destroy it, then re-create it as a single-writer object, which will be fully-owned
    // because the transfer_cap is now present inside of it again. At which point the single-writer noot
    // will be returned by this transaction or sent to the sender of this transaction
    public fun fill_transfer_cap<T: drop, M: drop>(noot: &mut Noot<T, M>, transfer_cap: TransferCap<T, M>) {
        assert!(is_correct_transfer_cap(noot, &transfer_cap), EWRONG_TRANSFER_CAP);
        assert!(!is_fully_owned(noot), ETRANSFER_CAP_ALREADY_EXISTS);
        option::fill(&mut noot.transfer_cap, transfer_cap);
    }

    // === Transfers restricted to using the Transfer-Cap ===

    // transfer_cap does not have key, so this cannot be used as an entry function
    public fun transfer_with_cap<T: drop, M: drop>(
        transfer_cap: &TransferCap<T, M>,
        noot: &mut Noot<T, M>,
        new_owner: address)
    {
        assert!(is_correct_transfer_cap(noot, transfer_cap), ENO_TRANSFER_PERMISSION);
        noot.owner = option::some(new_owner);
    }

    // TODO: when multi-writer objects can be deleted, this function should take noots by
    // value, destroy the shared object, and create it as a single-writer object.
    // Right now it will remain a multi-writer object
    public fun transfer_and_fully_own<T: drop, M: drop>(
        new_owner: address, 
        noot: &mut Noot<T, M>, 
        transfer_cap: TransferCap<T, M>) 
    {
        transfer_with_cap(&transfer_cap, noot, new_owner);
        fill_transfer_cap(noot, transfer_cap);
    }

    // === Transfers restricted to using a witness ===
    // So long as the defining module keeps its witness private, these functions can only be used
    // by the defining module. No transfer-cap needed.

    // Polymorphic transfer (transfer::transfer) cannot be used on noots becaus they do not have 'store'.
    // This prevents an inconsistent state; if the noot is in single-writer mode, an polymorphic transfer
    // could transfer the noot such that noot.owner is not the same as its Sui-defined owner
    public fun transfer<T: drop, M: drop>(_witness: T, noot: Noot<T, M>, new_owner: address) {
        noot.owner = option::some(new_owner);
        transfer::transfer(noot, new_owner);
    }

    public fun transfer_data<T: drop, D: store + copy + drop>(
        _witness: T,
        noot_data: NootData<T, D>, 
        new_owner: address)
    {
        transfer::transfer(noot_data, new_owner);
    }

    public fun share_data<T: drop, D: store + copy + drop>(_witness: T, noot_data: NootData<T, D>) {
        transfer::share_object(noot_data);
    }

    // === FamilyConfig Functions ===

    // NootFamilyConfig does not have 'store', meaning that external modules cannot use the transfer::transfer
    // polymorphic transfer in order to change ownership. As such this function is necessary
    public entry fun transfer_family_config<T>(family_config: NootFamilyConfig<T>, send_to: address) {
        transfer::transfer(family_config, send_to);
    }

    public fun borrow_family_display<T: drop>(family_config: &NootFamilyConfig<T>): &VecMap<String, String> {
        &family_config.display
    }

    public fun borrow_family_display_mut<T: drop>(_witness: T, family_config: &mut NootFamilyConfig<T>): &mut VecMap<String, String> {
        &mut family_config.display
    }

    public fun add_family_member<T: drop, D: store + copy + drop>(
        witness: T, 
        family_config: &mut NootFamilyConfig<T>, 
        key: vector<u8>,
        display: VecMap<String, String>,
        data: D,
        ctx: &mut TxContext)
    {
        let noot_data = create_data(witness, display, data, ctx);
        dynamic_object_field::add(&mut family_config.id, key, noot_data)
    }

    public fun remove_family_member<T: drop, D: store + copy + drop>(
        _witness: T, 
        family_config: &mut NootFamilyConfig<T>, 
        key: vector<u8>,
    ): D {
        let noot_data = dynamic_object_field::remove(&mut family_config.id, key);
        let NootData<T, D> { id, display, body } = noot_data;
        object::delete(id);
        body
    }

    public fun borrow_family_member<T: drop, D: store + copy + drop>(
        family_config: &NootFamilyConfig<T>, 
        key: vector<u8>,
    ): &NootData<T, D> {
        dynamic_object_field::borrow<vector<u8>, NootData<T, D>>(&family_config.id, key)
    }

    public fun borrow_family_member_mut<T: drop, D: store + copy + drop>(
        _witness: T,
        family_config: &mut NootFamilyConfig<T>, 
        key: vector<u8>,
    ): &mut NootData<T, D> {
        dynamic_object_field::borrow_mut<vector<u8>, NootData<T, D>>(&mut family_config.id, key)
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

    // === NootData Accessors ===

    public fun borrow_data<T: drop, M, D: store + drop + copy>(
        noot: &Noot<T, M>,
        family_config: &NootFamilyConfig<T>
    ): &D {
        if (dynamic_object_field::exists_with_type<vector<u8>, NootData<T, D>>(&noot.id, DATA_KEY)) {
            let data = dynamic_object_field::borrow<vector<u8>, NootData<T, D>>(&noot.id, DATA_KEY);
            &data.body
        } else {
            let default_data = borrow_family_member(family_config, noot.family_key);
            &default_data.body
        }
    }

    // Only the Noot-defining module can borrow the data mutably
    public fun borrow_data_mut<T: drop, M, D: store + drop + copy>(
        _witness: T,
        noot: &mut Noot<T, M>,
        family_config: &NootFamilyConfig<T>,
        ctx: &mut TxContext
    ): &mut D {
        if (!dynamic_object_field::exists_with_type<vector<u8>, NootData<T, D>>(&noot.id, DATA_KEY)) {
            let default_data = borrow_family_member<T, D>(family_config, noot.family_key);
            let data_copy = NootData<T, D> {
                id: object::new(ctx),
                display: *&default_data.display,
                body: *&default_data.body
            };
            dynamic_object_field::add(&mut noot.id, DATA_KEY, data_copy);
        };

        let noot_data = dynamic_object_field::borrow_mut<vector<u8>, NootData<T, D>>(&mut noot.id, DATA_KEY);
        &mut noot_data.body
    }

    // === Inventory Accessors ===

    public fun borrow_inventory<T, M>(noot: &Noot<T, M>): &Inventory {
        &noot.inventory
    }

    public fun borrow_inventory_mut<T, M>(noot: &mut Noot<T, M>): &mut Inventory {
        &mut noot.inventory
    }

    // TO DO: consider adding methods to deposit or remove noots specifically, and
    // set their owner to option::none when that happens
}