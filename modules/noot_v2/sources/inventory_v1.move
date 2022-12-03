// Note that all keys are typed, which provides namespacing to prevent key-collisions
// across modules.
// Furthermore, all read and write operations require a witness struct, which serves as an
// access-control mechanism to prevent other modules from using another module's namespace.

// This module acts as a wrapper around dynamic_object_field. It adds an index, so that it's possible
// to enumerate over all child objects within a given namespace, and also safely delete the parent
// storing the inventory without losing access to its children. Inventories are modular and can
// be transferred between objects that hold them.

// Note that for the regular object fields, when the parent is deleted, the children are
// not dropped, they are 'orphaned; they become permanently inaccessible within Sui's memory.
// This could mistakenly result in the loss of value.

// Note that we do not expose inventory.id externally, so it's impossible to use dynamic_object_field
// directly on an inventory to bypass the safety mechanisms we've built into this module.

// FUTURE:
// In order to build Inventory as generically as possible, we need:
// (1) to be able to remove object fields generically (not knowing what type they are). Right now
// every type must be known at compile time in Move, so this would have to be a native-MoveVM function.
//
// (2) a heterogenous vector that can store keys as arbitrary types (with copy + drop + store).
// Right now vectors can only contain homogenous types

// For the first constraint, we simply abort if a module tries to overwrite an existing item in its
// inventory (key collision), rather than rather than trying to remove the unknown type already
// using that key.
//
// For the second constraint, we assume all keys (formerly called 'names') are vector<u8>

// Maybe in the future, the index could also store the types of the values as well, once type
// introspection is possible.

module noot::inventory_v1 {
    use sui::dynamic_object_field;
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use std::vector;

    const EFIELD_ALREADY_EXISTS: u64 = 0;
    const EFIELD_DOES_NOT_EXIST: u64 = 1;
    const EFIELD_TYPE_MISMATCH: u64 = 2;
    const ENAMESPACE_ALREADY_EXISTS: u64 = 3;

    struct Inventory has key, store {
        id: UID,
    }

    struct Index<phantom Namespace: drop> has key, store {
        id: UID,
        inner: vector<Key<Namespace>>
    }

    struct Key<phantom Namespace: drop> has store, copy, drop {
        raw_key: vector<u8>
    }
    
    // this is a reserved key, to prevent name-collisions with Key
    struct IndexKey<phantom Namespace: drop> has store, copy, drop {}

    public fun empty(ctx: &mut TxContext): Inventory {
        Inventory { id: object::new(ctx) }
    }

    /// Adds a dynamic field to `inventory: &mut Inventory`.
    /// Aborts with `EFIELD_ALREADY_EXISTS` if the object already has that field with that name.
    public fun add<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>,
        value: Value,
        ctx: &mut TxContext
    ) {
        let key = Key<Namespace> { raw_key };
        add_internal(inventory, key, value, ctx);
    }

    /// Aborts with `EFIELD_DOES_NOT_EXIST` if the object does not have a field with that name.
    /// Aborts with `EFIELD_TYPE_MISMATCH` if the field exists, but the value object does not have the
    /// specified type.
    // This currently requires a witness, but we could relax this constraint in the future; this
    // would make all inventory items publicly readable.
    public fun borrow<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &Inventory,
        raw_key: vector<u8>
    ): &Value {
        dynamic_object_field::borrow(&inventory.id, Key<Namespace> { raw_key })
    }

    public fun borrow_mut<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>
    ): &mut Value {
        dynamic_object_field::borrow_mut(&mut inventory.id, Key<Namespace> { raw_key })
    }

    /// Removes the `object`s dynamic object field with the name specified by `name: Name` and returns
    /// the bound object.
    /// Aborts with `EFIELD_DOES_NOT_EXIST` if the object does not have a field with that name.
    /// Aborts with `EFIELD_TYPE_MISMATCH` if the field exists, but the value object does not have the
    /// specified type.
    public fun remove<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &mut Inventory,
        raw_key: vector<u8>,
        ctx: &mut TxContext
    ): Value {
        let index = borrow_index_mut_internal<Namespace>(inventory, ctx);

        let key = Key<Namespace> { raw_key };
        let (object_exists, i) = vector::index_of(&index.inner, &key);
        assert!(object_exists, EFIELD_DOES_NOT_EXIST);

        vector::remove(&mut index.inner, i);
        dynamic_object_field::remove(&mut inventory.id, key)
    }

    /// Returns true if and only if the `inventory` has a dynamic field with the name specified by
    /// `key: vector<u8>`.
    // Requires a witness, but we could relax this constraint
    public fun exists_<Namespace: drop>(
        _witness: Namespace,
        inventory: &Inventory,
        raw_key: vector<u8>,
    ): bool {
        if (!index_exists<Namespace>(inventory)) { return false };

        let index = dynamic_object_field::borrow<IndexKey<Namespace>, Index<Namespace>>(&inventory.id, IndexKey<Namespace> {});
        vector::contains(&index.inner, &Key<Namespace> { raw_key })
    }

    /// Returns true if and only if the `inventory` has a dynamic field with the name specified by
    /// `key: vector<u8>` with an assigned value of type `Value`.
    public fun exists_with_type<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &Inventory,
        raw_key: vector<u8>,
    ): bool {
        dynamic_object_field::exists_with_type<Key<Namespace>, Value>(&inventory.id, Key<Namespace> { raw_key })
    }

    public fun length<Namespace: drop>(inventory: &Inventory): u64 {
        if (!index_exists<Namespace>(inventory)) { return 0 };

        let index = dynamic_object_field::borrow<IndexKey<Namespace>, Index<Namespace>>(&inventory.id, IndexKey<Namespace> {});
        vector::length(&index.inner)
    }

    // Borrows the namespaced index and converts it back to bytes (vector<u8>). The module receiving this index
    // can then enumerate over each item in the index
    public fun copy_index<Namespace: drop>(
        _witness: Namespace,
        inventory: &Inventory
    ): vector<vector<u8>> {
        let raw_index = vector::empty<vector<u8>>();

        if (index_exists<Namespace>(inventory)) { 
            let index = dynamic_object_field::borrow<IndexKey<Namespace>, Index<Namespace>>(&inventory.id, IndexKey<Namespace> {});
            let i = 0;

            while (i < vector::length(&index.inner)) {
                vector::push_back(&mut raw_index, *&vector::borrow(&index.inner, i).raw_key);
                i = i + 1;
            };
        };

        raw_index
    }

    // Takes an `Inventory`, removes the namespaced portion specified, attaches that namespace to a new inventory,
    // and returns the new inventory.
    // Note that this ONLY works if all `Value` types are the same, and are known to the function calling this.
    //
    // FUTURE: make dynamic_object_field::remove more generic so that types do not need to be known
    public fun eject<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        inventory: &mut Inventory,
        ctx: &mut TxContext
    ): Inventory {
        let new_inventory = empty(ctx);

        if (index_exists<Namespace>(inventory)) {
            let index = dynamic_object_field::remove<IndexKey<Namespace>, Index<Namespace>>(&mut inventory.id, IndexKey<Namespace> {});

            let i = 0;

            while (i < vector::length(&index.inner)) {
                let key = vector::borrow(&index.inner, i);
                let value = dynamic_object_field::remove<Key<Namespace>, Value>(&mut inventory.id, *key);
                add_internal<Namespace, Value>(&mut new_inventory, *key, value, ctx);
                i = i + 1;
            };

            let Index { id, inner: _ } = index;
            object::delete(id);
        };

        new_inventory
    }

    // Aborts if there are key collisions within the namespace. The second inventory will be destroyed,
    // and any fields left inside of it will be orphaned.
    public fun merge<Namespace: drop, Value: key + store>(
        _witness: Namespace,
        self: &mut Inventory,
        inventory: Inventory,
        ctx: &mut TxContext
    ) {
        if (index_exists<Namespace>(&inventory)) {
            let index = dynamic_object_field::remove<IndexKey<Namespace>, Index<Namespace>>(&mut inventory.id, IndexKey<Namespace> {});

            let i = 0;

            while (i < vector::length(&index.inner)) {
                let key = vector::borrow(&index.inner, i);
                let value = dynamic_object_field::remove<Key<Namespace>, Value>(&mut inventory.id, *key);
                add_internal<Namespace, Value>(self, *key, value, ctx);
                i = i + 1;
            };

            let Index { id, inner: _ } = index;
            object::delete(id);
        };

        destroy(inventory);
    }

    // Any dyamic fields still inside of the destroyed inventory will become orphaned and be permanently
    // inaccessible. Use `eject` to remove any namespaces you want to save prior to destroying an inventory
    public entry fun destroy(inventory: Inventory) {
        let Inventory { id } = inventory;
        object::delete(id);
    }

    // === Internal functions ===

    fun add_internal<Namespace: drop, Value: key + store>(
        inventory: &mut Inventory,
        key: Key<Namespace>,
        value: Value,
        ctx: &mut TxContext
    ) {
        let index = borrow_index_mut_internal<Namespace>(inventory, ctx);
        assert!(!vector::contains(&index.inner, &key), EFIELD_ALREADY_EXISTS);

        vector::push_back(&mut index.inner, copy key);
        dynamic_object_field::add(&mut inventory.id, key, value);
    }

    // Ensures that an index always exists for the given namespace
    fun borrow_index_mut_internal<Namespace: drop>(inventory: &mut Inventory, ctx: &mut TxContext): &mut Index<Namespace> {
        if (!index_exists<Namespace>(inventory)) {
            dynamic_object_field::add(
                &mut inventory.id, 
                IndexKey<Namespace> {}, 
                Index { id: object::new(ctx), inner: vector::empty<Key<Namespace>>() }
            );
        };
        dynamic_object_field::borrow_mut<IndexKey<Namespace>, Index<Namespace>>(&mut inventory.id, IndexKey<Namespace> {})
    }

    fun index_exists<Namespace: drop>(inventory: &Inventory): bool {
        dynamic_object_field::exists_with_type<IndexKey<Namespace>, Index<Namespace>>(&inventory.id, IndexKey<Namespace> {})
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
    //         assert!(false, EFIELD_TYPE_MISMATCH);
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