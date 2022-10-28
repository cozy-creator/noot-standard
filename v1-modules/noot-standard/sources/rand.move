// This should eventually be in the sui framework

module noot::rand {
    const EBAD_RANGE: u64 = 0;

    // Generates an integer from the range [min, max), not inclusive of max
    // TODO: implement actual randomness
    public fun rng(min: u64, max: u64): u64 {
        assert!(max > min, EBAD_RANGE);
        min
    }
}