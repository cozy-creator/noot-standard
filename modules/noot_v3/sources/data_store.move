module noot::data_store {
    use sui::dynamic_field;
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use std::vector;
    use std::ascii::{Self, String};
    use std::hash;
    use std::option::{Self, Option};
    use utils::encode;

    const EITEM_ALREADY_EXISTS: u64 = 0;
    const EITEM_DOES_NOT_EXIST: u64 = 1;
    const EWRONG_ITEM_TYPE: u64 = 2;
    const ENAMESPACE_ALREADY_EXISTS: u64 = 3;
    const ENAMESPACE_DOES_NOT_EXIST: u64 = 4;
    const EINVENTORY_NOT_EMPTY: u64 = 5;
    const EMERGE_WILL_ORPHAN_ITEMS: u64 = 6;

    // For the index, the first vector is namespace, the second vector is a list of raw_keys which
    // serve as keys, and <vector<u8>> simply means an array of bytes.
    // Namespace[0] is the name for index[0]
    struct DataStore has key, store {
        id: UID,
        namespaces: vector<String>,
        index: vector<vector<vector<u8>>>
    }

    public fun empty(ctx: &mut TxContext): DataStore {
        DataStore { id: object::new(ctx), namespaces: vector::empty(), index: vector::empty() }
    }

    /// Adds a dynamic field to `data_store: &mut DataStore`.
    /// Aborts with `EITEM_ALREADY_EXISTS` if the object already has that field with that name.
    public fun add<Namespace: drop, Value: store + copy + drop>(
        _witness: Namespace,
        data_store: &mut DataStore,
        raw_key: vector<u8>,
        value: Value
    ) {
        add_internal<Namespace, Value>(data_store, raw_key, value);
    }

    // Used internally to bypass the `witness` requirement
    fun add_internal<Namespace: drop, Value: store + copy + drop>(
        data_store: &mut DataStore,
        raw_key: vector<u8>,
        value: Value
    ) {
        add_to_index<Namespace>(data_store, raw_key);
        let key = into_key<Namespace>(&raw_key);
        dynamic_field::add(&mut data_store.id, key, value);
    }

    /// Aborts with `EITEM_DOES_NOT_EXIST` if the object does not have a field with that name.
    /// Aborts with `EWRONG_ITEM_TYPE` if the field exists, but the value object does not have the
    /// specified type.
    public fun remove<Namespace: drop, Value: store + copy + drop>(
        _witness: Namespace,
        data_store: &mut DataStore,
        raw_key: vector<u8>
    ): Value {
        remove_internal<Namespace, Value>(data_store, raw_key)
    }

    // Used internally to bypass the witness requirement
    fun remove_internal<Namespace: drop, Value: store + copy + drop>(
        data_store: &mut DataStore,
        raw_key: vector<u8>
    ): Value {
        remove_from_index<Namespace>(data_store, raw_key);
        let key = into_key<Namespace>(&raw_key);
        dynamic_field::remove(&mut data_store.id, key)
    }

    // Dynamic fields are not generic enough to do this yet; you have to specify the value ahead
    // of time, even though it already has 'drop' and we're just dropping it.
    // fun drop(
    //     data_store: &mut DataStore,
    //     namespace: ascii::String,
    //     raw_key: vector<u8>
    // ) {
    //     dynamic_field::drop()
    // }

    public fun swap<Namespace: drop, ValueIn: store + copy + drop, ValueOut: store + copy + drop>(
        _witness: Namespace,
        data_store: &mut DataStore,
        raw_key: vector<u8>,
        value_in: ValueIn
    ): Option<ValueOut> {
        let value_out = option::none<ValueOut>();

        if (exists_with_type<Namespace, ValueOut>(data_store, raw_key)) {
            option::fill(&mut value_out, remove_internal<Namespace, ValueOut>(data_store, raw_key));
        } else if (exists_<Namespace>(data_store, raw_key)) {
            assert!(false, EWRONG_ITEM_TYPE);
        };

        add_internal<Namespace, ValueIn>(data_store, raw_key, value_in);

        value_out
    }

    /// Aborts with `EITEM_DOES_NOT_EXIST` if the object does not have a field with that name.
    /// Aborts with `EWRONG_ITEM_TYPE` if the field exists, but the value object does not have the
    /// specified type.
    // This currently requires a witness, but we could relax this constraint in the future; this
    // would make all data_store items publicly readable.
    public fun borrow<Namespace: drop, Value: store + copy + drop>(
        data_store: &DataStore,
        raw_key: vector<u8>
    ): &Value {
        let key = into_key<Namespace>(&raw_key);
        dynamic_field::borrow(&data_store.id, key)
    }

    public fun borrow_mut<Namespace: drop, Value: store + copy + drop>(
        _witness: Namespace,
        data_store: &mut DataStore,
        raw_key: vector<u8>
    ): &mut Value {
        let key = into_key<Namespace>(&raw_key);
        dynamic_field::borrow_mut(&mut data_store.id, key)
    }

    public fun borrow_with_default<Namespace: drop, Value: store + copy + drop>(
        data_store: &DataStore,
        raw_key: vector<u8>,
        default_data: &DataStore
    ): &Value {
        if (exists_with_type<Namespace, Value>(data_store, raw_key)) {
            borrow<Namespace, Value>(data_store, raw_key)
        } else {
            borrow<Namespace, Value>(default_data, raw_key)
        }
    }

    // Copy-on-write behavior, with default as the initial value
    public fun borrow_mut_with_default<Namespace: drop, Value: store + copy + drop>(
        witness: Namespace,
        data_store: &mut DataStore,
        raw_key: vector<u8>,
        default_data: &DataStore
    ): &mut Value { 
        if (!exists_with_type<Namespace, Value>(data_store, raw_key)) {
            let value = *borrow<Namespace, Value>(default_data, raw_key);
            add_internal<Namespace, Value>(data_store, raw_key, value);
        };

        borrow_mut<Namespace, Value>(witness, data_store, raw_key)
    }

    /// Returns true if and only if the `data_store` has a dynamic field with the name specified by
    /// `key: vector<u8>`.
    // Requires a witness, but we could relax this constraint
    public fun exists_<Namespace: drop>(
        data_store: &DataStore,
        raw_key: vector<u8>,
    ): bool {
        let index = index<Namespace>(data_store);
        let (exists, i) = vector::index_of(&index, &raw_key);
        exists
    }

    /// Returns true if and only if the `data_store` has a dynamic field with the name specified by
    /// `key: vector<u8>` with an assigned value of type `Value`.
    public fun exists_with_type<Namespace: drop, Value: store + copy + drop>(
        data_store: &DataStore,
        raw_key: vector<u8>,
    ): bool {
        let key = into_key<Namespace>(&raw_key);
        dynamic_field::exists_with_type<vector<u8>, Value>(&data_store.id, key)
    }

    public fun namespace_exists<Namespace>(data_store: &DataStore): bool {
        vector::contains(&data_store.namespaces, &encode::type_name_ascii<Namespace>())
    }

    public fun namespace_exists_(data_store: &DataStore, namespace: &ascii::String): bool {
        vector::contains(&data_store.namespaces, namespace)
    }

    // Returns all namespaces, so that they can be enumerated over
    public fun namespaces(data_store: &DataStore): vector<String> {
        data_store.namespaces
    }

    // Retrieves the index for the specified namespace so that it can be enumerated over
    public fun index<Namespace>(data_store: &DataStore): vector<vector<u8>> {
        let namespace = encode::type_name_ascii<Namespace>();
        index_(data_store, namespace)
    }

    public fun index_(data_store: &DataStore, namespace: ascii::String): vector<vector<u8>> {
        let (exists, i) = vector::index_of(&data_store.namespaces, &namespace);
        if (!exists) {
            vector::empty()
        } else {
            *vector::borrow(&data_store.index, i)
        }
    }

    // Returns the total number of items stored in the data_store, across all namespaces
    public fun size(data_store: &DataStore): u64 {
        let size = 0;
        let i = 0;
        while (i < vector::length(&data_store.namespaces)) {
            size = size + vector::length(vector::borrow(&data_store.index, i));
            i = i + 1;
        };
        size
    }

    public fun size_<Namespace>(data_store: &DataStore): u64 {
        let index = index<Namespace>(data_store);
        vector::length(&index)
    }

    // Takes an `DataStore`, removes the namespaced portion specified, attaches that namespace to a new data_store,
    // and returns the new data_store.
    // Note that this ONLY works if all `Value` types in that neamespace are the same, and must be known
    // and specified by the function calling this. Does not work for hetergenous types.
    //
    // FUTURE: make dynamic_field::remove more generic so that `Value` type does not need to be known
    // and need not be hetergenous
    public fun split<Namespace: drop, Value: store + copy + drop>(
        witness: Namespace,
        data_store: &mut DataStore,
        ctx: &mut TxContext
    ): DataStore {
        let new_data_store = empty(ctx);
        join<Namespace, Value>(witness, &mut new_data_store, data_store);
        new_data_store
    }

    // For the specified namespace, this strips out everything from the second-data_store, and places it inside
    // of the first data_store. Aborts if there are key collisions within the namespace.
    public fun join<Namespace: drop, Value: store + copy + drop>(
        _witness: Namespace,
        self: &mut DataStore,
        data_store: &mut DataStore
    ) {
        let index = index<Namespace>(data_store);
        let i = 0;
        while (i < vector::length(&index)) {
            let raw_key = vector::borrow(&index, i);
            let value = remove_internal<Namespace, Value>(data_store, *raw_key);
            add_internal<Namespace, Value>(self, *raw_key, value);
            i = i + 1;
        };
    }

    // Dynamic Fields are not flexible enough to let this happen; ideally we want to be able to implement
    // a 'drop' behavior, even if the object value is unknown
    // public entry fun destroy(data_store: DataStore) {
    //     let i = 0;
    //     while (i < vector::length(&namespaces)) {
    //         let index = index_(&data_store, namespace);
    //         let j = 0;
    //         while (j < vector::length(&index)) {
    //             let raw_key = *vector::borrow(&index, j);
    //             drop(&mut data_store, raw_key);
    //         };
    //     };

    //     let DataStore { id, namespaces: _, index: _ } = data_store;
    //     object::delete(id);
    // }

    // We enforce a 'zero emissions' policy of leaving now wasted data behind. Because every item in a
    // data store has 'drop', we can enumerate through and drop all of them
    // TO DO: implement this such that we can iterate over all data and drop it
    public entry fun destroy(data_store: DataStore) {
        let DataStore { id, namespaces, index: _ } = data_store;
        assert!(vector::length(&namespaces) == 0, EINVENTORY_NOT_EMPTY);
        object::delete(id);
    }

    // Keys = hash(namespace + | + raw_key (as bytes))
    // The hash keeps the keys all a constant size, regardless of the length of the namespace or raw_key
    public fun into_key<Namespace: drop>(raw_key: &vector<u8>): vector<u8> {
        let namespace = encode::type_name_ascii<Namespace>();
        let key_preimage = ascii::into_bytes(namespace);
        // prevents collissions caused by a namespace that is a prefix of another namespace
        vector::push_back(&mut key_preimage, 124u8);
        vector::append(&mut key_preimage, *raw_key);
        hash::sha2_256(key_preimage)
    }

    // === Internal functions ===

    fun add_to_index<Namespace>(data_store: &mut DataStore, raw_key: vector<u8>) {
        let namespace = encode::type_name_ascii<Namespace>();
        let (exists, i) = vector::index_of(&data_store.namespaces, &namespace);

        // If this namespace doesn't exist yet, we create it now
        if (!exists) {
            i = vector::length(&data_store.namespaces);
            vector::push_back(&mut data_store.namespaces, namespace);
            vector::append(&mut data_store.index, vector::empty());
        };

        let index = vector::borrow_mut(&mut data_store.index, i);
        assert!(!vector::contains(index, &raw_key), EITEM_ALREADY_EXISTS);
        vector::push_back(index, raw_key);
    }

    fun remove_from_index<Namespace>(data_store: &mut DataStore, raw_key: vector<u8>) {
        let namespace = encode::type_name_ascii<Namespace>();
        let (exists, i) = vector::index_of(&data_store.namespaces, &namespace);

        assert!(exists, ENAMESPACE_DOES_NOT_EXIST);

        let index = vector::borrow_mut(&mut data_store.index, i);
        let (item_exists, j) = vector::index_of(index, &raw_key);
        
        assert!(item_exists, EITEM_DOES_NOT_EXIST);

        vector::remove(index, j);

        // The namespace is now empty so we delete its entry in the index
        if (vector::length(index) == 0) {
            vector::remove(&mut data_store.index, i);
            vector::remove(&mut data_store.namespaces, i);
        }
    }
}