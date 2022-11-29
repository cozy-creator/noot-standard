// Noots can have their ownership linked to these objects rather than a keypair address
// Noot Worlds should charge to create these, and they can optionally expiry after a set number period of time
// In the future we may want to stop using epochs as a measure of time, and hence drop ctx as an argument of
// everything. Ideally we'd have a more precise measure of time, like timestamps

// The security model is that an immutable reference to this allows for read / write access to the Noot,
// while a mutable reference to this allows you to change who the owner is by transferring it, either
// peer-to-peer with a transfer-cap

module noot::owner_object {
    use std::option::{Self, Option};
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};

    struct OwnerObject<phantom World> has key, store {
        id: UID,
        expiry_epoch: Option<u64>
    }

    // Duration is measured in epochs; 0 means it will end at the end of the current epoch
    // duration = 1 means that if the current epoch is 200, then at the end of epoch 201 this permission will end
    // option::none means that the permission never expires
    public fun issue_permission<World: drop>(_witness: World, duration: Option<u64>, ctx: &mut TxContext): OwnerObject<World> {
        OwnerObject {
            id: object::new(ctx),
            expiry_epoch: get_expiry_epoch(duration, ctx)
        }
    }

    public fun renew_permission<World: drop>(_witness: World, permission: &mut OwnerObject<World>, duration: Option<u64>, ctx: &TxContext) {
        permission.expiry_epoch = get_expiry_epoch(duration, ctx);
    }

    public fun destroy_permission<World: drop>(permission: OwnerObject<World>) {
        let OwnerObject { id, expiry_epoch: _ } = permission;
        object::delete(id);
    }

    public fun get_expiry_epoch(duration: Option<u64>, ctx: &TxContext): Option<u64> {
        if (option::is_none(&duration)) {
            option::none()
        } else { 
            option::some(tx_context::epoch(ctx) + option::destroy_some(duration)) 
        }
    }

    public fun is_expired<W>(permission: &OwnerObject<W>, ctx: &TxContext): bool {
        if (option::is_none(&permission.expiry_epoch)) { return false };

        *option::borrow(&permission.expiry_epoch) < tx_context::epoch(ctx)
    }
}