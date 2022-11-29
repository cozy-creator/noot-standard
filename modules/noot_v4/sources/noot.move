// The fundamental problem with this setup is that there is no way for a project to restrict what vaults
// a Noot can be stored inside of. You could have a 'royalty market' noot, but the user could simply remove
// the noot from that, and place it in a 'royalty-free market' without the project having any say in the matter.

module noot::noot {

    struct Auth has store, drop {
        addr: address,
        permissions: vector<bool>
    }

    struct Plugins has key, store {
        id: UID
    }

    // Stored object
    struct Noot<phantom W> has key, store {
        id: UID,
        plugins: Plugins
    }

    // Shared or single-writer
    struct EntryNoot has key {
        id: UID,
        auths: vector<Auth>
    }

    struct Vault has key {
        id: UID,
        auths: vector<Auth>
    }

    // This just isn't a great system tbh
    // If a Vault stores multiple noots, we need to specify the key; that's already 4 objects!
    public entry fun use_noot<Auth>(entry_noot: &mut EntryNoot, auth: Option<Auth>, ctx: &mut TxContext) {

    }
}