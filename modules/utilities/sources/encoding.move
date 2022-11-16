// General purpose functions for converting data types

module utils::encode {
    use sui::vec_map::{Self, VecMap};
    use std::string::{Self, String};
    use std::vector;

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
}