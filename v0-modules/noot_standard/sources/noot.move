module noot::noot {
    use sui::object::{Self, ID, UID};
    use std::option::{Self, Option};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::vec_map::{Self, VecMap};
    use sui::dynamic_object_field;
    use std::string::{Self, String};
    use std::vector;

    const EBAD_WITNESS: u64 = 0;
    const ENOT_OWNER: u64 = 1;
    const ENO_TRANSFER_PERMISSION: u64 = 2;
    const EWRONG_TRANSFER_CAP: u64 = 3;
    const ETRANSFER_CAP_ALREADY_EXISTS: u64 = 4;
    const EINSUFFICIENT_FUNDS: u64 = 5;
    const EINCORRECT_DATA_REFERENCE: u64 = 6;

    // T is a witness produced by the defining-module, such as 'Minecraft' or 'Outlaw_Sky'
    // M is a witness produced by the market-module, which defines how the noot may be transferred
    struct Noot<phantom T, phantom M> has key, store {
        id: UID,
        quantity: u64,
        owner: option::Option<address>,
        transfer_cap: option::Option<TransferCap<T, M>>,
        default_data_key: vector<u8>,
        // TO DO: after Sui natively supports the ability to enumerate children, remove this field
        child_index: vector<vector<u8>>
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

    struct TransferCap<phantom T, phantom M> has store {
        for: ID
    }

    // One one of these will exist per noot-type, and they will initially be owned by the type creator
    // They will contain dynamic fields indexed by default_data_key, giving noots default data
    struct NootFamilyData<phantom T> has key, store {
        id: UID,
        display: VecMap<String, String>
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
    ): NootFamilyData<T> {
        assert!(sui::types::is_one_time_witness(&one_time_witness), EBAD_WITNESS);

        // TODO: add events
        // event::emit(CollectionCreated<T> {
        // });

        NootFamilyData<T> {
            id: object::new(ctx),
            display: vec_map::empty<String, String>()
        }
    }

    public entry fun craft_<T: drop, M: drop, D: store + copy + drop>(
        witness: T, 
        send_to: address, 
        data: &NootData<T, D>,
        ctx: &mut TxContext) 
    {
        let noot = craft<T, M, D>(witness, option::some(send_to), data, ctx);
        transfer::transfer(noot, send_to);
    }

    public fun craft<T: drop, M: drop, D: store + copy + drop>(
        _witness: T,
        owner: Option<address>,
        data: &NootData<T, D>,
        ctx: &mut TxContext): Noot<T, M> 
    {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);

        Noot {
            id: uid,
            quantity: 1,
            owner: owner,
            transfer_cap: option::some(TransferCap<T, M> {
                for: id
            }),
            default_data_key: b"data",
            child_index: vector::empty<vector<u8>>()
        }
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

    // We do not currently allow noots missing their transfer caps to be deconstructed
    // We only allow the defining-module to perform deconstruction
    // Noots can be deconstructed by someone other than the owner
    //
    // TO DO: enumerate and return child objects
    public fun deconstruct<T: drop, M>(_witness: T, noot: Noot<T, M>) {
        assert!(is_fully_owned(&noot), ENO_TRANSFER_PERMISSION);

        let Noot { id, quantity: _, owner: _, transfer_cap, default_data_key: _, child_index: _ } = noot;
        let TransferCap { for: _ } = option::destroy_some(transfer_cap);
        object::delete(id);
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

    // TODO: when multi-writer objects can be deleted, this function should take noots by
    // value, destroy the shared object, and create it as a single-writer object.
    // Right now it will remain a multi-writer object
    public fun transfer_and_fully_own<T: drop, M: drop>(
        new_owner: address, 
        noot: &mut Noot<T, M>, 
        transfer_cap: TransferCap<T, M>) 
    {
        transfer_with_cap(&transfer_cap, noot, new_owner);
        option::fill(&mut noot.transfer_cap, transfer_cap);
    }

    // transfer_cap does not have key, so this cannot be used as an entry function
    public fun transfer_with_cap<T: drop, M: drop>(
        transfer_cap: &TransferCap<T, M>,
        noot: &mut Noot<T, M>,
        new_owner: address)
    {
        assert!(is_correct_transfer_cap(noot, transfer_cap), ENO_TRANSFER_PERMISSION);
        noot.owner = option::some(new_owner);
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

    // === FamilyData Functions ===

    // NootFamilyData does not have 'store', meaning that external modules cannot use the transfer::transfer
    // polymorphic transfer in order to change ownership. As such this function is necessary
    public entry fun transfer_family_data<T>(family_info: NootFamilyData<T>, send_to: address) {
        transfer::transfer(family_info, send_to);
    }

    public fun borrow_family_data_mut<T: drop>(_witness: T, family_data: &mut NootFamilyData<T>): &mut VecMap<String, String> {
        &mut family_data.display
    }

    public fun add_family_data<T: drop, D: store + copy + drop>(
        witness: T, 
        family_info: &mut NootFamilyData<T>, 
        key: vector<u8>,
        display: VecMap<String, String>,
        data: D,
        ctx: &mut TxContext)
    {
        let noot_data = create_data(witness, display, data, ctx);
        dynamic_object_field::add(&mut family_info.id, key, noot_data)
    }

    public fun borrow_family_data<T, D: store + copy + drop>(family_data: &NootFamilyData<T>, key: vector<u8>): &NootData<T, D> {
        dynamic_object_field::borrow(&family_data.id, key)
    }

    // === Authority Checking Functions ===

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

    // === Data Accessors ===

    public fun borrow_data<T, M, D: store + drop + copy>(
        noot: &Noot<T, M>,
        default_data: &NootData<T, D>): (&VecMap<String, String>, &D)
    {
        if (dynamic_object_field::exists_with_type<vector<u8>, NootData<T, D>>(&noot.id, b"data")) {
            let data = dynamic_object_field::borrow<vector<u8>, NootData<T, D>>(&noot.id, b"data");
            (&data.display, &data.body)
        } else {
            assert!(is_correct_data(noot, default_data), EINCORRECT_DATA_REFERENCE);
            (&default_data.display, &default_data.body)
        }
    }

    public fun borrow_data_mut<T, M, D: store + drop + copy>(
        noot: &mut Noot<T, M>,
        default_data: &NootData<T, D>,
        ctx: &mut TxContext): (&mut VecMap<String, String>, &mut D)
    {
        if (!dynamic_object_field::exists_with_type<vector<u8>, NootData<T, D>>(&noot.id, b"data")) {
            assert!(is_correct_data(noot, default_data), EINCORRECT_DATA_REFERENCE);
            let data_copy = NootData<T, D> {
                id: object::new(ctx),
                display: *&default_data.display,
                body: *&default_data.body    
            };
            dynamic_object_field::add(&mut noot.id, b"data", data_copy);
        };

        let noot_data = dynamic_object_field::borrow_mut<vector<u8>, NootData<T, D>>(&mut noot.id, b"data");
        (&mut noot_data.display, &mut noot_data.body)
    }

    // === Inventory Accessors ===

    struct Key<phantom I> has store, copy, drop {
        inner: vector<u8>
    }

    public fun add_inventory<T, M, Namespace: drop, Value: store>(
        witness: Namespace,
        noot: &mut Noot<T, M>,
        key: vector<u8>,
        value: Value
    ) {
        inventory::add<I>(witness, &mut noot.id, key, value);
    }
}