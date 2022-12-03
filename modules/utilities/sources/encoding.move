// General purpose functions for converting data types

module utils::encode {
    use std::string::{Self, String};
    use std::vector;
    use std::ascii;
    use std::type_name;
    use sui::vec_map::{Self, VecMap};
    use sui::bcs;
    use utils::rand;

    // This will fail if there is an odd number of entries in the first vector
    // It will also fail if the bytes are not utf8 strings
    public fun to_string_string_vec_map(bytes: &vector<vector<u8>>): VecMap<String, String> {
        let output = vec_map::empty<String, String>();
        let i = 0;

        while (i < vector::length(bytes)) {
            let key = string::utf8(*vector::borrow(bytes, i));
            let value = string::utf8(*vector::borrow(bytes, i + 1));

            vec_map::insert(&mut output, key, value);

            i = i + 2;
        };

        output
    }

    // Raw ascii strings are printed incorrectly by debug::print; utf8's are printed correctly
    public fun type_name<T>(): String {
        let ascii_name = type_name::into_string(type_name::get<T>());
        string::utf8(ascii::into_bytes(ascii_name))
    }

    public fun addr_into_string(addr: &address): String {
        let ascii_bytes = vector::empty<u8>();

        let addr_bytes = bcs::to_bytes(addr);
        let i = 0;
        while (i < vector::length(&addr_bytes)) {
            // split the byte into halves
            let low: u8 = rand::mod_u8(*vector::borrow(&addr_bytes, i), 16u8);
            let high: u8 = *vector::borrow(&addr_bytes, i) / 16u8;
            vector::push_back(&mut ascii_bytes, u8_to_ascii(high));
            vector::push_back(&mut ascii_bytes, u8_to_ascii(low));
            i = i + 1;
        };

        let string = ascii::string(ascii_bytes);
        string::utf8(ascii::into_bytes(string))
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
    use utils::encode;
    use sui::object;
    use std::string;
    use sui::bcs;
    use std::ascii;

    #[test]
    public fun test1() {
        let scenario = test_scenario::begin(@0x5);
        let ctx = test_scenario::ctx(&mut scenario);
        {
            let uid = object::new(ctx);
            let addr = object::uid_to_address(&uid);
            let string = encode::addr_into_ascii(&addr);
            debug::print(&string);
            object::delete(uid);
        };
        test_scenario::end(scenario);
    }

    // bcs bytes != utf8 bytes
    #[test]
    #[expected_failure]
    public fun test2() {
        let scenario = test_scenario::begin(@0x5);
        let ctx = test_scenario::ctx(&mut scenario);
        {
            let uid = object::new(ctx);
            let addr = object::uid_to_address(&uid);
            debug::print(&string::utf8(bcs::to_bytes(&addr)));
            object::delete(uid);
        };
        test_scenario::end(scenario);
    }

    // bcs bytes != ascii bytes
    #[test]
    #[expected_failure]
    public fun test3() {
        let scenario = test_scenario::begin(@0x5);
        let ctx = test_scenario::ctx(&mut scenario);
        {
            let uid = object::new(ctx);
            let addr = object::uid_to_address(&uid);
            debug::print(&ascii::string(bcs::to_bytes(&addr)));
            object::delete(uid);
        };
        test_scenario::end(scenario);
    }
}