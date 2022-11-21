// Fill this in later

module market::lending {
    use sui::object::UID;
    use noot::noot::TransferCap;

    struct ReclaimCapability<phantom T, phantom M> has key, store {
        id: UID,
        transfer_cap: TransferCap<T, M>
    }
}