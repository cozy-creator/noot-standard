module noot::inventory {
    use sui::dynamic_object_field;
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
    struct Inventory has key, store {
        id: UID,
        namespaces: vector<String>,
        index: vector<vector<vector<u8>>>
    }

    public fun empty(ctx: &mut TxContext): Inventory {
        Inventory { id: object::new(ctx), namespaces: vector::empty(), index: vector::empty() }
    }

    /// Adds a dynamic field to `inventory: &mut Inventory`.
    /// Aborts with `EITEM_ALREADY_EXISTS` if the object already has that field with that name.
    public fun add<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>,
        value: Value
    ) {
        add_internal<Namespace, Value>(inventory, raw_key, value);
    }

    // In case you don't want to specify the key, the object's ID will be used as the raw_key instead
    public fun add_<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &mut Inventory,
        value: Value
    ) {
        let raw_key = object::id_to_bytes(&object::id(&value));
        add_internal<Namespace, Value>(inventory, raw_key, value);
    }

    // Used internally to bypass the `witness` requirement
    fun add_internal<Namespace: drop, Value: key + store>(
        inventory: &mut Inventory,
        raw_key: vector<u8>,
        value: Value
    ) {
        add_to_index<Namespace>(inventory, raw_key);
        let key = into_key<Namespace>(&raw_key);
        dynamic_object_field::add(&mut inventory.id, key, value);
    }

    /// Removes the `object`s dynamic object field with the name specified by `name: Name` and returns
    /// the bound object.
    /// Aborts with `EITEM_DOES_NOT_EXIST` if the object does not have a field with that name.
    /// Aborts with `EWRONG_ITEM_TYPE` if the field exists, but the value object does not have the
    /// specified type.
    public fun remove<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>
    ): Value {
        remove_internal<Namespace, Value>(inventory, raw_key)
    }

    // Used internally to bypass the witness requirement
    fun remove_internal<Namespace: drop, Value: key + store>(
        inventory: &mut Inventory,
        raw_key: vector<u8>
    ): Value {
        remove_from_index<Namespace>(inventory, raw_key);
        let key = into_key<Namespace>(&raw_key);
        dynamic_object_field::remove(&mut inventory.id, key)
    }

    public fun swap<Namespace: drop, ValueIn: key + store, ValueOut: key + store>(
        _witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>,
        value_in: ValueIn
    ): Option<ValueOut> {
        let value_out = option::none<ValueOut>();

        if (exists_with_type<Namespace, ValueOut>(inventory, raw_key)) {
            option::fill(&mut value_out, remove_internal<Namespace, ValueOut>(inventory, raw_key));
        } else if (exists_<Namespace>(inventory, raw_key)) {
            assert!(false, EWRONG_ITEM_TYPE);
        };

        add_internal<Namespace, ValueIn>(inventory, raw_key, value_in);

        value_out
    }

    /// Aborts with `EITEM_DOES_NOT_EXIST` if the object does not have a field with that name.
    /// Aborts with `EWRONG_ITEM_TYPE` if the field exists, but the value object does not have the
    /// specified type.
    // This currently requires a witness, but we could relax this constraint in the future; this
    // would make all inventory items publicly readable.
    public fun borrow<Namespace: drop, Value: key + store>(
        inventory: &Inventory,
        raw_key: vector<u8>
    ): &Value {
        let key = into_key<Namespace>(&raw_key);
        dynamic_object_field::borrow(&inventory.id, key)
    }

    public fun borrow_mut<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>
    ): &mut Value {
        let key = into_key<Namespace>(&raw_key);
        dynamic_object_field::borrow_mut(&mut inventory.id, key)
    }

    /// Returns true if and only if the `inventory` has a dynamic field with the name specified by
    /// `key: vector<u8>`.
    // Requires a witness, but we could relax this constraint
    public fun exists_<Namespace: drop>(
        inventory: &Inventory,
        raw_key: vector<u8>,
    ): bool {
        let key = into_key<Namespace>(&raw_key);
        dynamic_object_field::exists_(&inventory.id, key)
    }

    /// Returns true if and only if the `inventory` has a dynamic field with the name specified by
    /// `key: vector<u8>` with an assigned value of type `Value`.
    public fun exists_with_type<Namespace: drop, Value: key + store>(
        inventory: &Inventory,
        raw_key: vector<u8>,
    ): bool {
        let key = into_key<Namespace>(&raw_key);
        dynamic_object_field::exists_with_type<vector<u8>, Value>(&inventory.id, key)
    }

    public fun namespace_exists(inventory: &Inventory, namespace: &ascii::String): bool {
        vector::contains(&inventory.namespaces, namespace)
    }

    public fun namespace_exists_<Namespace>(inventory: &Inventory): bool {
        vector::contains(&inventory.namespaces, &encode::type_name_ascii<Namespace>())
    }

    // Returns all namespaces, so that they can be enumerated over
    public fun namespaces(inventory: &Inventory): vector<String> {
        inventory.namespaces
    }

    // Retrieves the index for the specified namespace so that it can be enumerated over
    public fun index<Namespace>(inventory: &Inventory): vector<vector<u8>> {
        let namespace = encode::type_name_ascii<Namespace>();
        let (exists, i) = vector::index_of(&inventory.namespaces, &namespace);
        if (!exists) {
            vector::empty()
        } else {
            *vector::borrow(&inventory.index, i)
        }
    }

    // Returns the total number of items stored in the inventory, across all namespaces
    public fun size(inventory: &Inventory): u64 {
        let size = 0;
        let i = 0;
        while (i < vector::length(&inventory.namespaces)) {
            size = size + vector::length(vector::borrow(&inventory.index, i));
            i = i + 1;
        };
        size
    }

    // Takes an `Inventory`, removes the namespaced portion specified, attaches that namespace to a new inventory,
    // and returns the new inventory.
    // Note that this ONLY works if all `Value` types in that neamespace are the same, and must be known
    // and specified by the function calling this. Does not work for hetergenous types.
    //
    // FUTURE: make dynamic_object_field::remove more generic so that `Value` type does not need to be known
    // and need not be hetergenous
    public fun split<Namespace: drop, Value: key + store>(
        witness: Namespace,
        inventory: &mut Inventory,
        ctx: &mut TxContext
    ): Inventory {
        let new_inventory = empty(ctx);
        join<Namespace, Value>(witness, &mut new_inventory, inventory);
        new_inventory
    }

    // For the specified namespace, this strips out everything from the second-inventory, and places it inside
    // of the first inventory. Aborts if there are key collisions within the namespace.
    public fun join<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        self: &mut Inventory,
        inventory: &mut Inventory
    ) {
        let index = index<Namespace>(inventory);
        let i = 0;
        while (i < vector::length(&index)) {
            let raw_key = vector::borrow(&index, i);
            let value = remove_internal<Namespace, Value>(inventory, *raw_key);
            add_internal<Namespace, Value>(self, *raw_key, value);
            i = i + 1;
        };
    }

    // We enforce a 'zero emissions' policy of leaving now wasted data behind. If Inventory were deleted
    // while still containing objects, those objects would be orphaned (rendered permanently inaccessible),
    // and remain in Sui's global storage wasting space forever.
    public entry fun destroy(inventory: Inventory) {
        let Inventory { id, namespaces, index: _ } = inventory;
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

    fun add_to_index<Namespace>(inventory: &mut Inventory, raw_key: vector<u8>) {
        let namespace = encode::type_name_ascii<Namespace>();
        let (exists, i) = vector::index_of(&inventory.namespaces, &namespace);

        // If this namespace doesn't exist yet, we create it now
        if (!exists) {
            i = vector::length(&inventory.namespaces);
            vector::push_back(&mut inventory.namespaces, namespace);
            vector::append(&mut inventory.index, vector::empty());
        };

        let index = vector::borrow_mut(&mut inventory.index, i);
        assert!(!vector::contains(index, &raw_key), EITEM_ALREADY_EXISTS);
        vector::push_back(index, raw_key);
    }

    fun remove_from_index<Namespace>(inventory: &mut Inventory, raw_key: vector<u8>) {
        let namespace = encode::type_name_ascii<Namespace>();
        let (exists, i) = vector::index_of(&inventory.namespaces, &namespace);

        assert!(exists, ENAMESPACE_DOES_NOT_EXIST);

        let index = vector::borrow_mut(&mut inventory.index, i);
        let (item_exists, j) = vector::index_of(index, &raw_key);
        
        assert!(item_exists, EITEM_DOES_NOT_EXIST);

        vector::remove(index, j);

        // The namespace is now empty so we delete its entry in the index
        if (vector::length(index) == 0) {
            vector::remove(&mut inventory.index, i);
            vector::remove(&mut inventory.namespaces, i);
        }
    }

    // This is not possible yet
    // public fun borrow_mut_safe<Name: copy + drop + store>(
    //     object: &mut UID,
    //     name: Name,
    //     ctx: &mut TxContext
    // ): &mut Bag {
    //     if (dynamic_object_field::exists_with_type<Name, Bag>(object, name)) {
    //         return dynamic_object_field::borrow_mut(object, name)
    //     }
    //     else if (dynamic_object_field::exists_(object, name)) {
    //         assert!(false, EWRONG_ITEM_TYPE);
    //         // Sui Move currently is not expressive enough to allow us to remove an arbitrary
    //         // object and then get rid of it by transfering it to the transaction sender
    //         // We need to know the type at compile-time, which we cannot do here
    //         //
    //         // let wrong_type = dynamic_object_field::remove(object, name);
    //         // transfer::transfer(wrong_type, tx_context::sender(ctx));
    //     };

    //     dynamic_object_field::add(object, name, bag::new(ctx));
    //     dynamic_object_field::borrow_mut(object, name)
    // }
}