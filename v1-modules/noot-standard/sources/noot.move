module noot::noot {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::TxContext;
    use sui::vec_map::{Self, VecMap};
    use std::string::String;
    use std::option::{Option};

    const EBAD_WITNESS: u64 = 0;
    const ENOT_OWNER: u64 = 1;
    const ENO_TRANSFER_PERMISSION: u64 = 2;
    const EWRONG_TRANSFER_CAP: u64 = 3;
    const ETRANSFER_CAP_ALREADY_EXISTS: u64 = 4;
    const EINSUFFICIENT_FUNDS: u64 = 5;

    struct Noot<phantom T> has store {
        id: UID,
        owner: Option<address>,
        data_id: ID
    }

    struct NootData<phantom T, D: store + copy + drop> has key {
        id: UID,
        display: VecMap<String, String>,
        body: D
    }

    struct WrappedNoot<phantom M, phantom T> has key, store {
        id: UID,
        noot: Noot<T>,
        transfer_cap: Option<TransferCap<T>>
    }

    struct TransferCap<phantom T> has store {
        for: ID
    }

    // One one of these will exist per noot-type, and they will initially be owned by the type creator
    struct NootTypeInfo<phantom T> has key {
        id: UID,
        display: VecMap<String, String>
    }

    // This can only be called once per type, inside of the `init` function of the defining module
    public fun create_type<W: drop, T: drop>(
        one_time_witness: W,
        _type_witness: T,
        ctx: &mut TxContext
    ): NootTypeInfo<T> {
        assert!(sui::types::is_one_time_witness(&one_time_witness), EBAD_WITNESS);

        // TODO: add events
        // event::emit(NootTypeCreated<T> {
        // });

        NootTypeInfo<T> {
            id: object::new(ctx),
            display: vec_map::empty<String, String>()
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

    // Because of _witness, this can only be called by the module that defines T, or by a module
    // that obtains _witness: T from that module.
    public fun craft<T: drop, D: store + copy + drop>(_witness: T, owner: Option<address>, noot_data: &NootData<T, D>, ctx: &mut TxContext): (Noot<T>, TransferCap<T>) {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);

        let noot = Noot {
            id: uid,
            owner,
            data_id: object::id(noot_data),
        };

        let transfer_cap = TransferCap {
            for: id
        };

        (noot, transfer_cap)
    }
}