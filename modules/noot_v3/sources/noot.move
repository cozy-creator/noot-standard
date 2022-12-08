// Noots: can only be in shared mode
// Can only be one owner at a time
// For DAO ownership, ownership can be linked to an object-id, rather than a keypair
// 

// Destruction: destroy the noot, destroy all data, return the inventory.

// TO DO: We might use dynamic_object_field instead if that really helps with indexing, but having 'drop' is nice

// Try supporting multiple markets at the same time

module noot::noot {
    use std::vector;
    use std::string::{String};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::math;
    use sui::dynamic_field;
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::vec_map::{Self, VecMap};
    use utils::encode;
    use noot::inventory::{Self, Inventory};
    use noot::data_store::{Self, DataStore};
    use metadata::metadata::{Self, Metadata};

    // enums to specify the vector index for each corresponding permission
    // There must be one, and only one, owner at a time.
    // Owner = can add and remove other authorizations.
    // Transfer = can remove owner and all authorizations, add new owner.
    // 
    // There must be one, and only one, owner at a time. Only the owner can transfer, sell, or store the noot.
    // Plugins: for sale = no withdrwa from inventory, no consumption
    // For sale = no withdrawing from inventory, no consumption
    // Loaned to a friend = no withdraw from inventory, no consumption, no selling, no transfer
    // Borrowed Against = no withdraw from inventory, no consumption, no selling (or sale must be > loan, and
    // repay loan)
    // Loaded into game = no transfer, no selling

    // These are the keys for dyanmic_field::borrow(Noot.plugins, SLOT) = 
    // does the object itself have the ability to take this action currently?
    // SLOT = [ TransferAuth<Market>, MarketAuth<Market> / SellOffer, LienAuth / LienReceipt, StoreAuth, Reclaimer-vector]
    const TRANSFER: u8 = 1; // Where TransferAuth is stored
    const MARKET: u8 = 2;
    const LIEN: u8 = 3; // can use this noot as collateral
    const STORE_AUTH: u8 = 4;
    const RECLAIMERS: u8 = 5; // where the reclaim-mark vector is stored

    // Transfer = wipe all current auths, add new full-auth. Append claim-mark
    struct TransferAuth<phantom Market> has store { for: ID } // Can be called by module-M (market)
    struct MarketAuth<phantom Market> has store { for: ID } // Can be called by module-M (market)
    struct LienAuth has store {}
    struct StoreAuth has store {} // Noot can be unshared (stored / put into single-writer mode)

    // Noot.auths[user-address].permissions[SLOT] = does this user have the authority to take this action?
    // SLOT = [ Owner, Consume, create-data, update-data, delete-data, deposit inventory, update inventory,
    // withdraw inventory]
    // Owner = must be one, and only one. Can add or remove Auths to Noot.auths.
    // Cannot add a new owner or remove itself; must use MarketAuth or TransferAuth for that.
    // Only Owner can transfer, sell (market), lien.
    const OWNER: u64 = 0; 
    const CONSUME: u64 = 1; // Can deconstruct the noot
    const STORE: u64 = 2; // Can unshare the noot, place it in inventory or wrap it
    const CREATE_DATA: u64 = 3; // Add data item (namespaced)
    const MUT_DATA: u64 = 4; // Get mutable reference to data item (namespaced)
    const DELETE_DATA: u64 = 5; // Remove data item (namespaced)
    const DEPOSIT_INVENTORY: u64 = 6;
    const MUT_INVENTORY: u64 = 7;
    const WITHDRAW_INVENTORY: u64 = 8;
    const PERMISSION_LENGTH: u64 = 9; // how long the vec[bool] permission needs to be
    const FULL_PERMISSION: vector<bool> = vector[true, true, true, true, true, true, true, true, true];
    const NO_PERMISSION: vector<bool> = vector[false, false, false, false, false, false, false, false, false];

    // error enums
    const EWRONG_SIZE: u64 = 0;
    const ENO_PERMISSION: u64 = 1;
    const EONLY_ONE_OWNER: u64 = 2;
    const EWRONG_MARKET: u64 = 3;
    const ENO_TRANSFER_AUTH: u64 = 4;
    const ENOT_RENTAL_OWNER: u64 = 5;
    const EWRONG_VAULT: u64 = 6;
    const EWRONG_HOT_POTATO: u64 = 7;
    const EAUTH_OBJECT_NOT_FOUND: u64 = 8;
    const EWRONG_WORLD: u64 = 9;
    const EINSUFFICIENT_BALANCE: u64 = 10;
    const EINCORRECT_COIN_TYPE: u64 = 11;
    const EUNPAID_OUTSTANDING_LOAN: u64 = 12;
    const EBAD_WITNESS: u64 = 13;

    struct Plugins has key, store {
        id: UID
    }

    struct WorldConfig<phantom Genesis> has key, store {
        id: UID,
        world: String, // witness type string
        data: DataStore
    }

    struct WorldKey has store {
        world: String, // witness type string
        raw_key: vector<u8>
    }

    // Can be single-writer, shared, or stored
    // We could potentially add a second UID, a stable UID, since this id can change
    struct Noot has key, store {
        id: UID,
        world_key: WorldKey,
        auths: VecMap<address, vector<bool>>,
        quantity: u16,
        data: DataStore,
        inventory: Inventory,
        plugins: Plugins
    }

    // =========== For World Authors ===============

    public fun create_world<GENESIS: drop, World: drop>(
        one_time_witness: GENESIS,
        _witness: World,
        ctx: &mut TxContext
    ): (WorldConfig<GENESIS>, Metadata<GENESIS>) {
        assert!(sui::types::is_one_time_witness(&one_time_witness), EBAD_WITNESS);
        let metadata = metadata::create(one_time_witness, ctx);

        let world_config = WorldConfig<GENESIS> {
            id: object::new(ctx),
            world: encode::type_name<World>(),
            data: data_store::empty(ctx)
        };

        (world_config, metadata)
    }

    public fun craft_noot<World: drop>(_witness: World, raw_key: vector<u8>, ctx: &mut TxContext): Noot {
        let world_key = WorldKey {
            world: encode::type_name<World>(),
            raw_key
        };

        Noot {
            id: object::new(ctx),
            world_key,
            auths: vec_map::empty<address, vector<bool>>(),
            quantity: 1,
            data: data_store::empty(ctx),
            inventory: inventory::empty(ctx),
            plugins: Plugins { id: object::new(ctx) }
        }
    }

    public fun deconstruct<World: drop>(_witness: World, noot: Noot): Inventory {
        assert!(dynamic_field::exists_with_type<u8, LienAuth>(&noot.plugins.id, LIEN), EUNPAID_OUTSTANDING_LOAN);

        let Noot { id, world_key, auths: _, quantity: _, data, inventory, plugins } = noot;
        object::delete(id);

        // Only the world that crafted this noot can deconstruct it
        let WorldKey { world, raw_key: _ } = world_key;
        assert!(world == encode::type_name<World>(), EWRONG_WORLD);

        // This is not properly implemented yet; will abort unless data is empty
        data_store::destroy(data);

        destroy_plugins(plugins);

        inventory
    }

    // TO DO: this should iterate over available plugin slots and delete them to recover storage space
    fun destroy_plugins(plugins: Plugins) {
        let Plugins { id } = plugins;
        object::delete(id);
    }

    // =========== Switch Noot Modes ===============
    // These operations alter UID unfortunately, so UID is not stable

    public entry fun share_noot(noot: Noot, ctx: &mut TxContext) {
        transfer::share_object(recreate_noot(noot, ctx));
    }

    public fun take_noot(noot: Noot, ctx: &mut TxContext): Noot {
        assert!(check_permission(&noot, ctx, OWNER), ENO_PERMISSION);

        // We should check for liens or claim-marks
        // We should remove any-share related plugins: auths, sell-orders

        recreate_noot(noot, ctx)
    }

    public entry fun take_and_transfer_noot(noot: Noot, ctx: &mut TxContext) {
        transfer::transfer(take_noot(noot, ctx), tx_context::sender(ctx));
    }

    fun recreate_noot(noot: Noot, ctx: &mut TxContext): Noot {
        let Noot { id, world_key, auths, quantity, data, inventory, plugins } = noot;
        object::delete(id);

        Noot { id: object::new(ctx), world_key, auths, quantity, data, inventory, plugins}
    }

    // =========== Auth Management ===============

    public entry fun add_auth(noot: &mut Noot, user: address, permissions: vector<bool>, ctx: &mut TxContext) {
        assert!(vector::length(&permissions) == PERMISSION_LENGTH, EWRONG_SIZE);
        assert!(check_permission(noot, ctx, OWNER), ENO_PERMISSION);

        // There can only be one owner at a time
        assert!(!*vector::borrow(&permissions, OWNER), EONLY_ONE_OWNER);

        if (vec_map::contains(&noot.auths, &user)) { 
            // No existing authorization found; add one
            vec_map::insert(&mut noot.auths, user, permissions);
        } else {
            // Overwrites existing authorization
            let old_permissions = vec_map::get_mut(&mut noot.auths, &user);
            *old_permissions = permissions;
        };
    }

    public entry fun remove_auth(noot: &mut Noot, user: address, ctx: &mut TxContext) {
        assert!(check_permission(noot, ctx, OWNER), ENO_PERMISSION);
        remove_auth_internal(noot, user);
    }

    fun remove_auth_internal(noot: &mut Noot, user: address) {
        if (vec_map::contains(&noot.auths, &user)) {
            vec_map::remove(&mut noot.auths, &user);
        }
    }

    fun reset_auths_internal(noot: &mut Noot, user: address, permission: vector<bool>) {
        noot.auths = vec_map::empty<address, vector<bool>>();
        vec_map::insert(&mut noot.auths, user, permission);
    }

    // =========== Auth Flashloan ===============

    // Suppose we want to attach ownership to an object Obj, rather than an address abc123.
    // Having to present Obj for every function-call as authorization would be unwieldly!
    // Instead, we leave an auth record, object::id(Obj) = permisions associated with that object
    // When the owner of Obj wants to use their noot, they will call borrow_auth(noot, obj)
    // In the auth-record we will then replace the object-id with the sender's address
    // The sender will then be able to pass all permissions recorded for that object
    // Finally, to conclude the transaction the user must return the hot-potato, which sets
    // the auth-address back to the object-id.

    struct HotPotato { noot_id: ID, user_addr: address, obj_addr: address }

    // This needs to be thought through a little more; what if someone borrows authority with
    // Obj; are they able to delete Obj from the auths list then?
    public fun borrow_auth<Obj: key>(
        noot: &mut Noot,
        obj: &Obj,
        ctx: &mut TxContext
    ): HotPotato {
        let obj_addr = object::id_address(obj);
        let user_addr = tx_context::sender(ctx);
        assert!(vec_map::contains(&noot.auths, &obj_addr), EAUTH_OBJECT_NOT_FOUND);

        // Vec_map does not have a swap-key function...
        let (_key, permissions) = vec_map::remove(&mut noot.auths, &obj_addr);
        vec_map::insert(&mut noot.auths, user_addr, permissions);

        HotPotato { noot_id: object::id(noot), user_addr, obj_addr  }
    }

    public fun return_auth(noot: &mut Noot, hot_potato: HotPotato) {
        let HotPotato { noot_id, user_addr, obj_addr } = hot_potato;
        assert!(noot_id == object::id(noot), EWRONG_HOT_POTATO);
        assert!(vec_map::contains(&noot.auths, &user_addr), EAUTH_OBJECT_NOT_FOUND);

        let (_key, permissions) = vec_map::remove(&mut noot.auths, &user_addr);
        vec_map::insert(&mut noot.auths, obj_addr, permissions);
    }

    // =========== Data Management ===============

    public entry fun add_data<Namespace: drop, Value: store + copy + drop>(
        witness: Namespace,
        noot: &mut Noot,
        raw_key: vector<u8>,
        value: Value,
        ctx: &mut TxContext
    ) {
        assert!(check_permission(noot, ctx, CREATE_DATA), ENO_PERMISSION);

        data_store::add(witness, &mut noot.data, raw_key, value);
    }

    public fun borrow_data<G, World: drop, Value: store + copy + drop>(
        noot: &Noot, 
        world_config: &WorldConfig<G>, 
        raw_key: vector<u8>
    ): &Value {
        assert!(world_config.world == encode::type_name<World>(), EWRONG_WORLD);

        data_store::borrow_with_default<World, Value>(&noot.data, raw_key, &world_config.data)
    }

    public fun borrow_data_mut<G, World: drop, Value: store + copy + drop>(
        witness: World,
        noot: &mut Noot,
        world_config: &WorldConfig<G>,
        raw_key: vector<u8>,
        ctx: &mut TxContext
    ): &mut Value {
        assert!(world_config.world == encode::type_name<World>(), EWRONG_WORLD);
        assert!(check_permission(noot, ctx, MUT_DATA), ENO_PERMISSION);

        data_store::borrow_mut_with_default<World, Value>(witness, &mut noot.data, raw_key, &world_config.data)
    }

    public entry fun remove_data() {

    }

    // =========== View Functions ===============
    // Used by external processes to deserialize names, descriptions, images, files, etc.



    // ============ Inventory Management =================



    // ============ Royalty Market Plugin =================

    // Market plugin witness
    struct RoyaltyM has drop {}

    // This is storing an item of value, and hence cannot be dropped
    struct SellOffer has store {
        coin_type: String,
        price: u64,
        pay_to: address,
        market_auth: MarketAuth<RoyaltyM>
    }

    // Not currently used
    struct MarketConfig {
        claims: vector<vector<u8>>
    }

    // TO DO: check permissions
    public entry fun transfer(noot: &mut Noot, new_owner: address, claim: vector<u8>, _ctx: &mut TxContext) {
        assert!(dynamic_field::exists_with_type<u8, TransferAuth<RoyaltyM>>(&noot.plugins.id, TRANSFER), ENO_TRANSFER_AUTH);

        reset_auths_internal(noot, new_owner, FULL_PERMISSION);
        
        let claims = dynamic_field::borrow_mut<u8, vector<vector<u8>>>(&mut noot.plugins.id, RECLAIMERS);
        vector::push_back(claims, claim);
    }

    // Should MarketAuth be a stamp, creating as many market-auths as it wants, or should it be
    // a single permission object that gets removed?
    public entry fun create_sell_offer<C>(noot: &mut Noot, price: u64, ctx: &mut TxContext) {
        if (dynamic_field::exists_with_type<u8, SellOffer>(&noot.plugins.id, MARKET)) {
            cancel_sell_offer(noot, ctx);
        };

        // Should we assert that market-auth ID matches noot id as well?
        assert!(dynamic_field::exists_with_type<u8, MarketAuth<RoyaltyM>>(&noot.plugins.id, MARKET), EWRONG_MARKET);

        let market_auth = dynamic_field::remove<u8, MarketAuth<RoyaltyM>>(&mut noot.plugins.id, MARKET);
        let sell_offer = SellOffer {
            coin_type: encode::type_name<Coin<C>>(),
            price,
            pay_to: tx_context::sender(ctx),
            market_auth
        };

        // Add new sell offer
        dynamic_field::add(&mut noot.plugins.id, MARKET, sell_offer);
    }

    public entry fun fill_sell_offer<C>(noot: &mut Noot, coin: Coin<C>, ctx: &mut TxContext) {
        let sell_offer = dynamic_field::remove<u8, SellOffer>(&mut noot.plugins.id, MARKET);
        let SellOffer { coin_type, price, pay_to, market_auth } = sell_offer;
        dynamic_field::add(&mut noot.plugins.id, MARKET, market_auth);

        assert!(coin_type == encode::type_name<Coin<C>>(), EINCORRECT_COIN_TYPE);
        assert!(coin::value(&coin) >= price, EINSUFFICIENT_BALANCE);
        transfer::transfer(coin, pay_to);

        remove_claims(noot);
        reset_auths_internal(noot, tx_context::sender(ctx), FULL_PERMISSION);
    }

    // TO DO: check permissions
    public entry fun cancel_sell_offer(noot: &mut Noot, _ctx: &mut TxContext) {
        let sell_offer = dynamic_field::remove<u8, SellOffer>(&mut noot.plugins.id, MARKET);
        let SellOffer { coin_type: _, price: _, pay_to: _, market_auth } = sell_offer;
        dynamic_field::add(&mut noot.plugins.id, MARKET, market_auth);
    }

    public entry fun create_buy_offer() {}

    public entry fun fill_buy_offer() {}

    public entry fun cancel_buy_offer() {}

    // Remove outstanding claim-marks
    fun remove_claims(noot: &mut Noot) {
        *dynamic_field::borrow_mut<u8, vector<vector<u8>>>(&mut noot.plugins.id, RECLAIMERS) = vector::empty<vector<u8>>();
    }

    public fun into_price(sell_offer: &SellOffer): (u64, String) {
        (sell_offer.price, sell_offer.coin_type)
    }

    // ============ Rental Plugin =================

    struct RentalOffer<phantom C, phantom M> has store {
        pay_to: address,
        price: u64,
        market_auth: MarketAuth<M>,
        lien_auth: LienAuth
    }

    struct RentalReceipt<phantom M> has store {
        owner: address,
        market_auth: MarketAuth<M>,
        lien_auth: LienAuth,
        reclaim_marks: vector<vector<u8>>
    }

    // Locks market-selling and lien methods
    public entry fun create_rental_offer<C, M>(noot: &mut Noot, price: u64, ctx: &mut TxContext) {
        let rental_offer = RentalOffer<C, M> {
            pay_to: tx_context::sender(ctx),
            price,
            market_auth: dynamic_field::remove<u8, MarketAuth<M>>(&mut noot.plugins.id, MARKET),
            lien_auth: dynamic_field::remove<u8, LienAuth>(&mut noot.plugins.id, LIEN),
        };
        dynamic_field::add(&mut noot.plugins.id, LIEN, rental_offer);
    }

    public entry fun cancel_rental_offer() {

    }

    public entry fun fill_rental_offer<C, M>(noot: &mut Noot, coin: Coin<C>, ctx: &mut TxContext) {
        let rental_offer = dynamic_field::remove<u8, RentalOffer<C, M>>(&mut noot.plugins.id, LIEN);
        let RentalOffer { pay_to, price, market_auth, lien_auth } = rental_offer;

        assert!(coin::value(&coin) >= price, EINSUFFICIENT_BALANCE);
        transfer::transfer(coin, pay_to);

        let addr = tx_context::sender(ctx);
        reset_auths_internal(noot, addr, vector[true, true, true, true, true, true, false]);

        let rental_receipt = RentalReceipt {
            owner: pay_to,
            market_auth,
            lien_auth,
            reclaim_marks: *dynamic_field::borrow<u8, vector<vector<u8>>>(&noot.plugins.id, RECLAIMERS)
        };
        dynamic_field::add(&mut noot.plugins.id, LIEN, rental_receipt);
    }

    public entry fun reclaim_rental<C, M>(noot: &mut Noot, ctx: &mut TxContext) {
        let rental_receipt = dynamic_field::remove<u8, RentalReceipt<M>>(&mut noot.plugins.id, LIEN);
        let RentalReceipt { owner, market_auth, lien_auth, reclaim_marks } = rental_receipt;

        let addr = tx_context::sender(ctx);
        assert!(owner == addr, ENOT_RENTAL_OWNER);

        dynamic_field::add(&mut noot.plugins.id, MARKET, market_auth);
        dynamic_field::add(&mut noot.plugins.id, LIEN, lien_auth);

        // Restore the reclaim-marks to their previous state
        *dynamic_field::borrow_mut<u8, vector<vector<u8>>>(&mut noot.plugins.id, RECLAIMERS) = reclaim_marks;

        reset_auths_internal(noot, addr, FULL_PERMISSION);
    }

    // ============ Collateralized Loan Plugin =================

    struct Vault<phantom C> has key, store {
        id: UID,
        coins: Coin<C>
    }

    struct LienReceipt has store {
        pay_to: address,
        amount_owed: u64,
        lien_auth: LienAuth,
    }

    // In this noot's plugins, we swap the LienAuth for a LineReceipt
    public entry fun collateralize<C>(noot: &mut Noot, vault: &mut Vault<C>, amount: u64, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);
        let coin = coin::split(&mut vault.coins, amount, ctx);
        transfer::transfer(coin, addr);

        let lien_receipt = LienReceipt {
            pay_to: object::id_address(vault),
            amount_owed: amount,
            lien_auth: dynamic_field::remove<u8, LienAuth>(&mut noot.plugins.id, LIEN)
        };

        dynamic_field::add<u8, LienReceipt>(&mut noot.plugins.id, LIEN, lien_receipt);
    }

    // TO DO: check permissions
    public entry fun pay_back_loan<C>(noot: &mut Noot, vault: &mut Vault<C>, coin: Coin<C>, _ctx: &mut TxContext) {
        let lien_receipt = dynamic_field::remove<u8, LienReceipt>(&mut noot.plugins.id, LIEN);
        let LienReceipt { pay_to, amount_owed, lien_auth } = lien_receipt;

        assert!(coin::value(&coin) >= amount_owed, EINSUFFICIENT_BALANCE);
        assert!(object::id_address(vault) == pay_to, EWRONG_VAULT);
        coin::join(&mut vault.coins, coin);

        dynamic_field::add(&mut noot.plugins.id, LIEN, lien_auth);
    }

    // Anyone with the funds to repay the loan can repo
    public entry fun repo_noot<C>(noot: &mut Noot, vault: &mut Vault<C>, coin: Coin<C>, ctx: &mut TxContext) {
        pay_back_loan(noot, vault, coin, ctx);

        // Take full possession of the noot 
        remove_claims(noot);
        reset_auths_internal(noot, tx_context::sender(ctx), FULL_PERMISSION);
    }

    // ============ Permission Checker Functions =================

    public fun check_permission(noot: &Noot, ctx: &TxContext, index: u64): bool {
        let addr = tx_context::sender(ctx);
        if (!vec_map::contains(&noot.auths, &addr)) { false }
        else {
            let authorization = vec_map::get(&noot.auths, &addr);
            *vector::borrow(authorization, index)
        }
    }

    public fun get_permission(noot: &Noot, ctx: &TxContext): vector<bool> {
        let addr = tx_context::sender(ctx);
        if (!vec_map::contains(&noot.auths, &addr)) { NO_PERMISSION }
        else {
            *vec_map::get(&noot.auths, &addr)
        }
    }

    // ============ Helper functions =================

    // public fun index_of(v: &vector<Auth>, addr: address): (bool, u64) {
    //     let i = 0;
    //     let len = vector::length(v);
    //     while (i < len) {
    //         if (vector::borrow(v, i).user == addr) return (true, i);
    //         i = i + 1;
    //     };
    //     (false, 0)
    // }

    // The longer vector will be kept, and its values that do not overlap with the shorter vector will not be modified 
    public fun logical_and_join(v1: &vector<bool>, v2: &vector<bool>): vector<bool> {
        let len1 = vector::length(v1);
        let len2 = vector::length(v2);
        let length = math::min(len1, len2);

        let v = vector::empty<bool>();

        let i = 0;
        while (i < length) {
            vector::push_back(&mut v, *vector::borrow(v1, i) && *vector::borrow(v2, i));
            i = i + 1;
        };

        v
    }
}