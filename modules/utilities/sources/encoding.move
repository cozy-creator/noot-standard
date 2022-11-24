// General purpose functions for converting data types

module utils::encode {
    use std::string::{Self, String};
    use std::vector;
    use std::ascii;
    use std::type_name;
    use sui::vec_map::{Self, VecMap};

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

    public fun type_name<T>(): String {
        let ascii_name = type_name::into_string(type_name::get<T>());
        string::utf8(ascii::into_bytes(ascii_name))
    }

    public fun type_name_ascii<T>(): ascii::String {
        type_name::into_string(type_name::get<T>())
    }
}