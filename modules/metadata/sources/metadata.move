// Sui's On-Chain Metadata program
// Do we like the term 'Display Data' or 'Metadata' better?

module metadata::metadata {
    use std::string::String;
    use sui::object::{Self, UID};
    use sui::types;
    use sui::tx_context::TxContext;
    use sui::dynamic_field;
    use utils::encode;

    const EBAD_WITNESS: u64 = 0;
    const EMISMATCHED_MODULES: u64 = 1;
    const INCORRECT_TYPE: u64 = 2;

    // T is a one-time witness
    struct Metadata<phantom T> has key, store {
        id: UID,
        module_addr: String,
        module_name: String
    }

    // We use a reference to the witness, rather than its value, so that it can also be
    // used by other modules, such as sui::coin::create_currency. Unfortunately this
    // means this method can be called multiple times within the same init function, so we
    // cannot GUARANTEE that there is no other instance of this.
    // There is probably a better way to create Singleton objects than using a one-time-witness pattern
    public fun create_display_data<T: drop>(witness: &T, ctx: &mut TxContext): Metadata<T> {
        assert!(types::is_one_time_witness(witness), EBAD_WITNESS);
        let (module_addr, module_name, _) = encode::type_name_<T>();

        Metadata {
            id: object::new(ctx),
            module_addr,
            module_name
        }
    }

    // This adds an entry for the specified Object type. Note that the Object must be from the same
    // module as T, or this will abort.
    // This will overwrite an existing display-data for Object
    public fun add_data<T, Object: key, D: store + drop>(display: &mut Metadata<T>, object_display: D) {
        remove_data<T, Object, D>(display);
        let (_, _, key) = encode::type_name_<Object>();
        dynamic_field::add(&mut display.id, key, object_display);
    }

    public entry fun remove_data<T, Object: key, D: store + drop>(display: &mut Metadata<T>) {
        assert!(encode::is_same_module<T, Object>(), EMISMATCHED_MODULES);
        let (_, _, key) = encode::type_name_<Object>();

        // In the future we should use just dynamic_field::exists_, without specifying the type, and
        // assume we can remove and drop it
        if (dynamic_field::exists_with_type<String, D>(&display.id, key)) {
            dynamic_field::remove<String, D>(&mut display.id, key);
        };
    }
}