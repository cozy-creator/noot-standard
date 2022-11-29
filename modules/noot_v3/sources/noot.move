// Noots: can only be in shared mode
// Can only be one owner at a time
// For DAO ownership, ownership can be linked to an object-id, rather than a keypair
// 

// Destruction: destroy the noot, destroy all data, return the inventory.

// TO DO: We might use dynamic_object_field instead if that really helps with indexing, but having 'drop' is nice

// Try supporting multiple markets at the same time

module noot::noot {
    use std::vector;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::math;
    use sui::dynamic_object_field;
    use sui::dynamic_field;
    use sui::transfer;
    use sui::coin::Coin;

    // enums to specify the vector index for each corresponding permission
    // There must be one, and only one, owner at a time.
    // Owner = can add and remove other authorizations.
    // Transfer = can remove owner and all authorizations, add new owner.
    // 
    // There must be one, and only one, owner at a time. Only the owner can transfer, sell, or store the noot.
    // Plugins: for sale = no withdrwa from inventory, no consumption
    // For sale = no withdrawing from inventory, no consumption
    // Loaned to a friend = no withdraw from inventory, no consumption, no selling, no transfer
    // Borrowed Against = no withdraw from inventory, no consumption, no selling (or sale must be > loan, and repay loan)
    // Loaded into game = no transfer, no selling

    // dyanmic_field::borrow(Noot.plugins, SLOT) = does the object itself have the ability to take this action?
    // SLOT = [ OwnerAuth, TransferAuth<Market>, MarketAuth<Market>, LienAuth, Sell_Offer]
    const TRANSFER: u8 = 1; // wipe existing auths, create a new owner-auth. Adds a reclaim-mark
    const MARKET: u8 = 2;
    const LIEN: u8 = 3; // can use this noot as collateral
    const MARKET_SLOT_1: u8 = 4;
    const MARKET_SLOT_2: u8 = 5;
    const RECLAIMERS: u8 = 6; // where the reclaim-mark vector is stored

    struct TransferAuth<phantom Market> has store { for: ID } // One and only one
    struct MarketAuth<phantom Market> has store { for: ID } // One and only one
    struct LienAuth has store {}
    struct StoreAuth has store {} // Noot can be unshared (stored / put into single-writer mode)

    // Noot.auths[user-address].permissions[SLOT] = does this user have the authority to take this action?
    // SLOT = [ ]
    const ADMIN: u8 = 0; // can add or remove Auths to Noot.auths
    const CONSUME: u64 = 2; // Can deconstruct the noot
    const CREATE_DATA: u64 = 3; // Add data item (namespaced)
    const UPDATE_DATA: u64 = 4; // Get mutable reference to data item (namespaced)
    const DELETE_DATA: u64 = 5; // Remove data item (namespaced)
    const DEPOSIT_INVENTORY: u64 = 6;
    const MUT_INVENTORY: u64 = 7;
    const WITHDRAW_INVENTORY: u64 = 8;
    const PERMISSION_LENGTH: u64 = 9;
    const FULL_PERMISSION: vector<bool> = vector[true, true, true, true, true, true, true, true, true];
    const NO_PERMISSION: vector<bool> = vector[false, false, false, false, false, false, false, false, false];

    // error enums
    const EWRONG_SIZE: u64 = 0;
    const ENO_PERMISSION: u64 = 1;
    const EONLY_ONE_OWNER: u64 = 2;
    const EWRONG_MARKET: u64 = 3;
    const ENO_TRANSFER_AUTH: u64 = 4;
    const ENOT_RENTAL_OWNER: u64 = 5;
    const EINCORRECT_BALANCE: u64 = 6;
    const EWRONG_VAULT: u64 = 7;

    // stored object
    struct Auth has store, drop {
        addr: address,
        permissions: vector<bool>
    }

    struct Plugins has key, store {
        id: UID
    }

    // Can be single-writer, shared, or stored
    struct Noot<phantom W> has key, store {
        id: UID,
        uid: UID, // stable-id; use for indexing
        auths: vector<Auth>,
        plugins: Plugins
    }

    // =========== For World Authors ===============

    public fun craft_noot(ctx: &mut TxContext): Noot {
        Noot {
            id: object::new(ctx),
            uid: object::new(ctx),
            auths: vector::empty<Auth>(),
            plugins: Plugins { id: object::new(ctx) }
        }
    }

    public entry fun deconstruct<W>(noot: Noot<W>) {

    }

    // =========== Switch Noot Modes ===============
    // These operations alter UID unfortunately, so UID is not stable

    public entry fun share_noot<W>(noot: Noot<W>, ctx: &mut TxContext) {
        transfer::share_object(recreate_noot(noot));
    }

    public fun take_noot(noot: Noot<W>, ctx: &TxContext): Noot<W> {
        assert!(check_permission(&noot, ctx, ADMIN), ENO_PERMISSION);

        // We should check for liens or claim-marks
        // We should remove any-share related things: auths, sell-orders

        recreate_noot(noot)
    }

    public entry fun take_and_transfer_noot(noot: Noot<W>, ctx: &TxContext) {
        transfer::transfer(take_noot_(noot, ctx), tx_context::sender(ctx));
    }

    fun recreate_noot<W>(noot: Noot<W>): Noot<W> {
        let Noot { id, auths, plugins } = noot;
        object::delete(id);

        Noot<W> { id: object::new(ctx), auths, plugins}
    }

    // =========== Auth Management ===============

    public entry fun add_authorization(noot: &mut Noot, user: address, permissions: vector<bool>, ctx: &mut TxContext) {
        assert!(vector::length(&permissions) == PERMISSION_LENGTH, EWRONG_SIZE);
        assert!(check_permission(noot, ctx, ADMIN), ENO_PERMISSION);

        // There can only be one owner at a time
        assert!(!*vector::borrow(&permissions, ADMIN), EONLY_ONE_OWNER);

        let (exists, i) = index_of(&noot.auths, user);

        if (!exists) { 
            // No existing authorization found; add one
            let authorization = Auth {
                user,
                permissions
            };
            vector::push_back(&mut noot.auths, authorization);
        } else {
            // Overwrites existing authorization
            let authorization = vector::borrow_mut(&mut noot.auths, i);
            authorization.permissions = permissions;
        }
    }

    public entry fun remove_authorization(noot: &mut Noot, user: address, ctx: &mut TxContext) {
        assert!(check_permission(noot, ctx, ADMIN), ENO_PERMISSION);

        let (exists, i) = index_of(&noot.auths, user);
        if (exists) {
            vector::remove(&mut noot.auths, i);
        }
    }

    // =========== Data Management ===============

    public entry fun add_data(noot: &mut Noot, ctx: &mut TxContext) {
        assert!(check_permission(noot, ctx, CREATE_DATA), ENO_PERMISSION);
        // allow data to be modified
    }

    public fun borrow_data() {
    }

    public fun borrow_data_mut(noot: &mut Noot, ctx: &mut TxContext) {
        assert!(check_permission(noot, ctx, UPDATE_DATA), ENO_PERMISSION);
        // allow data to be modified
    }

    public entry fun remove_data() {
    }

    // ============ Inventory Management =================



    // ============ Royalty Market Plugin =================

    // Market plugin witness
    struct RoyaltyM has drop {}

    struct SellOffer<phantom C> has store, drop {
        price: u64,
        pay_to: address,
        auth: MarketAuth<RoyaltyM>
    }

    struct MarketConfig {
        claims: vector<vector<u8>>
    }

    public entry fun transfer<W>(noot: &mut Noot<W>, new_owner: address, claim: vector<u8>, ctx: &mut TxContext) {
        aassert!(dynamic_field::exists_with_type<u8, MarketAuth<RoyaltyM>>(&noot.plugins.id, TRANSFER), ENO_TRANSFER_AUTH);
        noot.auths = vector[ Auth { user: new_owner, permissions: FULL_PERMISSION }];
        
        let claims = dynamic_field::borrow_mut<u8, vector<vector<u8>>>(&mut noot.plugins.id, MARKET_SLOT_2);
        vector::push_back(claims, claim);
    }

    public entry fun create_sell_offer<W, C>(noot: &mut Noot, price: u64, ctx: &mut TxContext) {
        assert!(dynamic_field::exists_with_type<u8, MarketAuth<W>>(&noot.plugins.id, MarketAuth), EWRONG_MARKET);
        let market_auth = MarketAuth<RoyaltyM> { for: object::id(noot) };

        let sell_offer = SellOffer<C> {
            id: object::new(ctx),
            price,
            pay_to: tx_context::sender(ctx),
            auth: market_auth
        };

        // Drop existing sell offer, if any
        if (dynamic_field::exists_with_type<u8, SellOffer<RoyaltyM>>(&noot.plugins.id, MARKET_SLOT_1)) {
            dynamic_field::remove<u8, SellOffer<RoyaltyM>>(&mut noot.plugins.id, MARKET_SLOT_1);
        }

        // Add new sell offer
        dynamic_field::add(&mut noot.plugins.id, MARKET_SLOT_1, sell_offer);
    }

    public entry fun fill_sell_offer<W, C>(noot: &mut Noot, coin: Coin<C>, ctx: &mut TxContext) {
        let sell_offer = dynamic_field::remove<u8, SellOffer<C>>(&mut noot.plugins.id, MARKET_SLOT_1);
        let SellOffer { price: _, pay_to, auth: _ } = sell_offer;
        object::delete(id);

        // Assert coin value
        transfer::transfer(coin, pay_to);

        remove_claims(noot);
        noot.auths = vector[ Auth { user: tx_context::sender(ctx), permissions: FULL_PERMISSION }];
    }

    public entry fun cancel_sell_offer() {}

    public entry fun create_buy_offer() {}

    public entry fun fill_buy_offer() {}

    public entry fun cancel_buy_offer() {}

    // Remove outstanding claim-marks
    fun remove_claims<W>(noot: &mut Noot<W>) {
        *dynamic_field::borrow_mut<u8, vector<vector<u8>>(&mut noot.plugins.id, RECLAIMERS) = vector::empty<vector<u8>>();
    }

    // ============ Rental Plugin =================

    struct RentalOffer<phantom C, M> has store, drop {
        pay_to: address,
        price: u64,
        market_auth: MarketAuth<M>,
        lien_auth: LienAuth
    }

    struct RentalReceipt<M> has store {
        owner: address,
        market_auth: MarketAuth<M>,
        lien_auth: LienAuth,
        reclaim_marks: vector<vector<u8>>
    }

    // Locks market-selling and lien methods
    public entry fun create_rental_offer<C, W, M>(noot: &mut Noot<W>, price: u64, ctx: &mut TxContext) {
        let rental_offer = RentalOffer<C, M> {
            pay_to: tx_context::sender(ctx),
            price,
            market_auth = dynamic_field::remove<u8, MarketAuth<M>>(&mut noot.plugins.id, MARKET);
            lien_auth = dynamic_field::remove<u8, LienAuth>(&mut noot.plugins.id, LIEN);
        };
        dynamic_field::add(&mut.plugins.id, LIEN, rental_offer);
    }

    public entry fun cancel_rental_offer() {

    }

    public entry fun fill_rental_offer<W, C, M>(noot: &mut Noot<W>, coin: Coin<C>, ctx: &mut TxContext) {
        let rental_offer = dynamic_field::remove<u8, RentalOffer<C>>(&mut noot.plugins.id, LIEN);
        let RentalOffer { pay_to, price: _, market_auth, lien_auth } = rental_offer;
        // assert price
        transfer::transfer(coin, pay_to);

        let addr = tx_context::sender(ctx);
        noot.auths = vector[ Auth { addr, permisisons: vector[true, true, true, true, true, true, false] }];

        let rental_receipt = RentalReceipt {
            owner: pay_to,
            market_auth,
            lien_auth,
            reclaim_marks: *dynamic_field::borrow<u8, vector<vector<u8>>(&noot.plugins.id, RECLAIMERS)
        };
        dynamic_field::add(&mut.plugins.id, LIEN, rental_receipt);
    }

    public entry fun reclaim_rental<W, C>(noot: &mut Noot<W>, ctx: &mut TxContext) {
        let rental_receipt = dynamic_field::remove<u8, RentalReceipt>(&mut.plugins.id, LIEN);
        let RentalReceipt { owner, market_auth, lien_auth, reclaim_marks } = rental_receipt;

        let addr = tx_context::sender(ctx);
        assert!(owner == addr, ENOT_RENTAL_OWNER);

        dynamic_field::add(&mut noot.plugins.id, MARKET, market_auth);
        dynamic_field::add(&mut noot.plugins.id, LIEN, lien_auth);

        // Restore the reclaim-marks to their previous state
        *dynamic_field::borrow_mut<u8, vector<vector<u8>>(&mut noot.plugins.id, RECLAIMERS) = reclaim_marks;

        noot.auths = vector[ Auth { addr, permisisons: FULL_PERMISSION }];
    }

    // ============ Collateralized Loan Plugin =================

    struct Vault<C> has key, store {
        id: UID,
        coins: Coin<C>
    }

    struct LienReceipt has store {
        pay_to: address
        amount_owed: u64,
        lien_auth: LienAuth,
    }

    public entry fun collateralize<W>(noot: &mut Noot<W>, vault: &mut Vault<C>, amount: u64, ctx: &mut TxContext) {
        let addr = tx_context::sender(ctx);
        let coin = coin::split(&mut vault.coins, amount, ctx);
        transfer::transfer(coin, addr);

        let LienReceipt = {
            pay_to: object::id(vault),
            amount_owed: amount,
            lien_auth: dynamic_field::remove<u8, LienAuth>(&mut noot.plugins.id, LIEN)
        };
    }

    public entry fun pay_back_loan<C, W>(noot: &mut Noot<W>, vault: &mut Vault<C>, coin: Coin<C>, ctx: &mut TxContext) {
        let lien_receipt = dynamic_field::remove<u8, LienReceipt>(&mut noot.plugins.id, LIEN);
        let LienReceipt { pay_to, amount_owed, lien_auth };

        assert!(coin::balance(&coin) >= amount_owed, EINCORRECT_BALANCE);
        assert!(object::id(vault) == pay_to, EWRONG_VAULT);
        coin::join(&mut vault.coins, coin);

        dynamic_field::add(&mut noot.plugins.id, LIEN, lien_auth);
    }

    // Anyone with the funds to repay the loan can repo
    public entry fun repo_noot<C, W>(noot: &mut Noot<W>, vault: &mut Vault<C>, coin: Coin<C>, ctx: &mut TxContext) {
        pay_back_loan(noot, vault, coin, ctx);

        // Take full possession of the noot 
        remove_claims(noot);
        noot.auths = vector[ Auth { tx_context::sender(ctx), permisisons: FULL_PERMISSION }];
    }

    // ============ Permission Checker Functions =================

    public fun check_permission(noot: &Noot, ctx: &mut TxContext, index: u64): bool {
        let addr = tx_context::sender(ctx);
        let (exists, i) = index_of(&noot.auths, addr);
        if (!exists) { false }
        else {
            let authorization = vector::borrow(&noot.auths, i);
            if (!*vector::borrow(&noot.lock.permissions, index)) { false }
            else { *vector::borrow(&authorization.permissions, index) }
        }
    }

    public fun get_permission(noot: &Noot, ctx: &TxContext): vector<bool> {
        let addr = tx_context::sender(ctx);
        let (exists, i) = index_of(&noot.auths, addr);
        if (!exists) { NO_PERMISSION }
        else {
            logical_and_join(&noot.lock.permissions, &vector::borrow(&noot.auths, i).permissions)
        }
    }

    // ============ Helper functions =================

    public fun index_of(v: &vector<Auth>, addr: address): (bool, u64) {
        let i = 0;
        let len = vector::length(v);
        while (i < len) {
            if (vector::borrow(v, i).user == addr) return (true, i);
            i = i + 1;
        };
        (false, 0)
    }

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