// General purpose functions for converting data types

// Definitions:
// Full-qualified type-name, or just 'type name' for short:
// 0000000000000000000000000000000000000002::devnet_nft::DevNetNFT
// This is <package_id>::<module_name>::<struct_name>
// This does not include the 0x i the package-id, and they are all utf8 strings.
// A 'module address' is just <package_id>::<module_name>

module utils::encode {
    use std::string::{Self, String, utf8};
    use std::vector;
    use std::ascii;
    use std::type_name;
    use sui::vec_map::{Self, VecMap};
    use sui::bcs;

    const EINVALID_TYPE_NAME: u64 = 0;

    // This will fail if there is an odd number of entries in the first vector
    // It will also fail if the bytes are not utf8 strings
    public fun to_string_string_vec_map(bytes: &vector<vector<u8>>): VecMap<String, String> {
        let output = vec_map::empty<String, String>();
        let i = 0;

        while (i < vector::length(bytes)) {
            let key = utf8(*vector::borrow(bytes, i));
            let value = utf8(*vector::borrow(bytes, i + 1));

            vec_map::insert(&mut output, key, value);

            i = i + 2;
        };

        output
    }

    // Ascii bytes are printed incorrectly by debug::print; utf8's are printed correctly, hence
    // we skip using ascii's and go straight to utf8's. Ascii is a subset of Utf8.
    // The string returned is the fully-qualified type name, with no abbreviations or 0x appended to addresses,
    // Examples:
    // 0000000000000000000000000000000000000002::devnet_nft::DevNetNFT
    // 0000000000000000000000000000000000000002::coin::Coin<0000000000000000000000000000000000000002::sui::SUI>
    // 0000000000000000000000000000000000000001::string::String
    public fun type_name<T>(): String {
        let ascii_name = type_name::into_string(type_name::get<T>());
        utf8(ascii::into_bytes(ascii_name))
    }

    public fun type_name_<T>(): (String, String) {
        decompose_type_name(type_name<T>())
    }

    // Accepts a full-qualified type-name strings and decomposes them into the tuple:
    // (package-id, module name, struct name).
    // Example:
    // (0000000000000000000000000000000000000002::devnet_nft, 
    // 0000000000000000000000000000000000000002, devnet_nft, DevNetNFT)
    // Aborts if the string does not conform to the `address::module::type` format
    public fun decompose_type_name(s1: String): (String, String) {
        let delimiter = utf8(b"::");

        let i = string::index_of(&s1, &delimiter);
        assert!(string::length(&s1) > i, EINVALID_TYPE_NAME);

        let s2 = string::sub_string(&s1, i + 2, string::length(&s1));
        let j = string::index_of(&s2, &delimiter);
        assert!(string::length(&s2) > j, EINVALID_TYPE_NAME);

        // let package_id = string::sub_string(&s1, 0, i);
        // let module_name = string::sub_string(&s2, 0, j);

        let module_addr = string::sub_string(&s1, 0, i + j + 2);
        let struct_name = string::sub_string(&s2, j + 2, string::length(&s2));

        (module_addr, struct_name)
    }

    public fun is_same_module<Type1, Type2>(): bool {
        let (module1, _) = type_name_<Type1>();
        let (module2, _) = type_name_<Type2>();

        (module1 == module2)
    }

    public fun is_same_module_(type_name1: String, type_name2: String): bool {
        let (module1, _) = decompose_type_name(type_name1);
        let (module2, _) = decompose_type_name(type_name2);

        (module1 == module2)
    }

    public fun append_struct_name<Type>(struct_name: String): String {
        let (type_name, _) = type_name_<Type>();
        string::append(&mut type_name, utf8(b"::"));
        string::append(&mut type_name, struct_name);
        
        type_name
    }

    // addresses are 20 bytes, whereas the string-encoded version is 40 bytes.
    // Outputted strings do not include the 0x prefix.
    public fun addr_into_string(addr: &address): String {
        let ascii_bytes = vector::empty<u8>();

        let addr_bytes = bcs::to_bytes(addr);
        let i = 0;
        while (i < vector::length(&addr_bytes)) {
            // split the byte into halves
            let low: u8 = *vector::borrow(&addr_bytes, i) % 16u8;
            let high: u8 = *vector::borrow(&addr_bytes, i) / 16u8;
            vector::push_back(&mut ascii_bytes, u8_to_ascii(high));
            vector::push_back(&mut ascii_bytes, u8_to_ascii(low));
            i = i + 1;
        };

        let string = ascii::string(ascii_bytes);
        utf8(ascii::into_bytes(string))
    }

    public fun u8_to_ascii(num: u8): u8 {
        if (num < 10) {
            num + 48
        } else {
            num + 87
        }
    }
}

#[test_only]
module utils::encode_test {
    use std::debug;
    use sui::test_scenario;
    use std::string;
    use sui::object;
    use sui::bcs;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use utils::encode;

    // bcs bytes != utf8 bytes
    #[test]
    #[expected_failure]
    public fun bcs_is_not_utf8() {
        let scenario = test_scenario::begin(@0x5);
        let ctx = test_scenario::ctx(&mut scenario);
        {
            let uid = object::new(ctx);
            let addr = object::uid_to_address(&uid);
            let addr_string = string::utf8(bcs::to_bytes(&addr));
            debug::print(&addr_string);
            object::delete(uid);
        };
        test_scenario::end(scenario);
    }

    #[test]
    public fun addr_into_string() {
        let scenario = test_scenario::begin(@0x5);
        let ctx = test_scenario::ctx(&mut scenario);
        {
            let uid = object::new(ctx);
            let addr = object::uid_to_address(&uid);
            let string = encode::addr_into_string(&addr);
            assert!(string::utf8(b"fdc6d587c83a348e456b034e1e0c31e9a7e1a3aa") == string, 0);
            object::delete(uid);
        };
        test_scenario::end(scenario);
    }

    #[test]
    public fun decompose_sui_coin_type_name() {
        let scenario = test_scenario::begin(@0x77);
        let _ctx = test_scenario::ctx(&mut scenario);
        {
            let name = encode::type_name<Coin<SUI>>();
            let (addr, type) = encode::decompose_type_name(name);
            assert!(string::utf8(b"0000000000000000000000000000000000000002::coin") == addr, 0);
            assert!(string::utf8(b"Coin<0000000000000000000000000000000000000002::sui::SUI>") == type, 0);
        };
        test_scenario::end(scenario);
    }

    #[test]
    public fun match_modules() {
        let scenario = test_scenario::begin(@0x420);
        let _ctx = test_scenario::ctx(&mut scenario);
        {
            assert!(encode::is_same_module<coin::Coin<SUI>, coin::TreasuryCap<SUI>>(), 0);
            assert!(!encode::is_same_module<bcs::BCS, object::ID>(), 0);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = encode::EINVALID_TYPE_NAME)]
    public fun invalid_string() {
        let scenario = test_scenario::begin(@0x69);
        {
            let (_addr, _type) = encode::decompose_type_name(string::utf8(b"123456"));
        };
        test_scenario::end(scenario);
    }
}