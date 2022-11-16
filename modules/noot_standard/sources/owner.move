module noot::owner {
    struct Owner has store {
        owners: vector<address>,
        claims: vector<vector<u8>>
    }
}