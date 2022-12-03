![Move_VM](./static/move_vm_factory.png 'Sui Move Factory')

**Noot:** a programmable unit of ownership. (plural: noots)

### Why We Built This

**1. Genericness:** Move does not allow dynamic dispatch, or rather, calling into unknown code. That is, you can only write a module that calls into functions that are already defined by an existing module, not some hypothetical future module. Let's suppose we create a module, deployed at `openrails::outlaw_sky`, that has tradeable resources, like `Outlaw`. Clutchy is working on an asset marketplace, and they want to create a market for these outlaw_sky assets. In that case, they must build a module that calls into `openrails::outlaw_sky::transfer(outlaw: Outlaw)`. Great. Next Rushdown Revolt decides to come to Sui. Now Clutchy must write a new module for their asset maketplace, that calls into `rushdown_revolt::characters::transfer(fighter: Fighter)`. And so on and so forth; Clutchy is going to have write new code for every new asset-collection that comes out; that's a lot of work!

Instead, we define a more generic interface, such as `noot::market::transfer<T>(noot: Noot<T>)`. Both Outlaw Sky and Rushdown Revolt can define their assets as noots, and Clutchy can take advantage of this by writing all their module code for `noot::market` functions, which will work for all past noot-collections and all future noot-collections. Plus noot-collection creators will be able to plug into the noot-standard, and have 90% of the on-chain code taken care of for them. Much easier for everyone.

Eventually we'd like to allow creators to deploy their works without writing ANY on-chain code at all.

**2. Off-chain displays:** Wallets and explorers will be reading the Sui blockchain and being like 'what is this resource? How do I display it to a user?'. By having a standard way to store links to off-chain data (.png, .mov, .fbx, .html...) wallets and explorers will be able to build their applications expecting what data to show.

### Why Drop the Term 'NFT'?

Noots are the successor to NFTs. They are a rebranding and a reimagination of what NFTs could have been.

Why are we still talking about "tokens"? Are we still on Ethereum here? And what does it matter if a token is not-fungible? Any token I've seen in real life is 100% fungible. And most NFTs are treated as basically fungible anyway. Non-fungibility is probably the LEAST interesting part of an NFT.

What are their interesting parts? They're digital assets that exist in a giant crytographic decentralized network. Their ownership can be verified and transfered. They hold on-chain state that can be read and modified. (...or in the case of Solana, they're mere pointers to a JSON file stored on an AWS server lol.)

I like the term 'property', because that's really what we're going for here. Instead of legal property, they're cryptographic property.

**Tokenized Property:** real-world property whose legal ownership has been turned into a digital representation.

**Digital Property:** property with no corresponding real-world component.

The ownership of this property is enforced through blockchain contracts, rather than through courts and lawyers. Suggested terms: Ownership As Code (OaC), Property As Code (PaC)

Oh also; gamers HATE the term 'NFT'; there;s a lot of negative stigma around the term. It's worth noting that neither Reddit nor Facebook use the term 'NFT', instead preferring to call them 'digital collectible'. Mark Zuckerburg calls them 'virtual goods'.

### Data Storage

**Data:** We can take two approaches to storing NFT data (1) embedded data, in which the data is stored within the NFT struct itself, or (2) pointer data, in which each NFT merely stores a pointer to an object-id that contains the NFT data. I believe Origin Byte referred to this as "embedded" versus "loosely" packed data. The second approach, pointer-data, is clearly superior, because:

1. **Saves Space:** Many NFTs can point to the same data, saving on expensive on-chain storage. Imagine a use-case where Magic The Gathering wants to issue 100 identical cards; they can create 100 NFTs, and give them out to 100 people, but every NFT points to the same NFTData object, saving on 100x data-duplication, and allowing Magic The Gathering to make any changes to that card in one place. Imagine also an NFT which is a blank-canvas when it's first minted; every user will start out with their NFT pointing to the same blank NFTData object, but as soon as they being to change it, a new NFTData object will be created specifically for them, which the NFT will point to.

2. **Composibility:** The NFT itself is mostly concerned with access-control (who owns what, who can do what) and markets (selling, borrowing / lending), while the NFTData is mostly concerned with saving on-chain state and linking to off-chain state. This creates a separation of concerns that allows for ownership and data to be modified separately.

### Crafting

**Mint-time Data Generation:** -

**Pre-Mint:** -

**Lazy Minting:** In thise case, everyone receives the same identical NFT, and then a 'reveal' step happens, where each NFT's data is determined.

### Royalties

**Royalty Address:** In the Metaplex standard on Solana, creators specify a list of royalty addresses and their respective split. For simplicity and composibility, we chose to use only one royalty address; the plan is that later we can create 'fan out' accounts, which will be module-controlled accounts (as opposed to private-key controlled accounts) that will automatically forward funds received to their constituents (i.e., the individual creators in a project). Aptos and Solana already have these, but I'm not sure how to implement this in Sui yet, because of the absence of signer_caps and resource accounts on Sui compared to Aptos.

Now that I think of it, the Metaplex royalty system is pretty dumb; on Solana all royalty-data is duplicated and stored on-chain individually for EVERY NFT (that's 10,000x the storage requirements lol).

**Variable Royalties:** -

### Experimental Ideas:

- Why not split royalty payments between both a seller and a buyer? I.e., if an NFT is for sale for 40 SUI, and the royalty is 10%, then the buyer should pay 42 SUI, and the seller should receive 38 SUI, for a total fee of 4 SUI going to the creators.

### To Do

- Come up with a new type of coin; it'll probably be a vault-sonly coin (not free-floating) and it'll have a market-confounding mechanism and freeze built in
- Think through the market-sales + leins + loaning-to-people. Can you have multiple sales across multiple markets?
- How does cross-world default data work? I imagine that if Minecraft creates an item, and we want to read the data for that item, the default-data for that item could be defined by either Minecraft World-Config or Zelda World-Config. In this case, Zelda-config should take precidence. That is, each WorldConfig defines (1) what its item's data should be, and (2) what foreign items coming into this world's data should be. It cannot define what its data should be in someone else's world. So MinecraftWorldConfig would define (1) data for Minecraft items, and (2) data for Zelda-items; it CANNOT define what the data should be for Minecraft items in Zelda.
- Does transfer_cap need to be bound to a specific world?
- Should the transfer_cap be inside of the Noot, or the EntryNoot?
- Idea: for the EntryNoot, we could add a boolean field 'readable' which, when set to false, stops a noot from borrowed immutably.
- For the deconstruct function, we may want to check ownership in some way, just in case.
- Consider moving the transfer_cap to the EntryNoot, rather than the noot.
- For borrowing a noot from a shared wrapper, do we need to assert that the transaction-sender is the owner? Note that because 'noots' have store, a user can (1) polymorphic-transfer the noot to someone else, allowing them to get a reference to the noot, or even full possession of it, while not owning it, or (2) store the noot in a custom struct, share it, and then allow anyone to get a reference to it, or take it by value. That's why it's important function-creators check is_owner for a noot, although if they want lots of people to be able to write to it or read from it, they can.
- Consider using 'economy' rather than 'market'
- Add a separate 'gating mechanism' for the noot dispenser (white list, price adjustment, etc.)
- Consider typing NootData with the world that it corresponds to
- Should I switch inventory to dynamic_object_field instead?
- Consider wrapping the 'family data' return values with options, in case the data they want to borrow doesn't exist, or its the wrong type.
- Remove `store` from Noots, and instead use an intermediary noot-store struct, along with special functions for storing and borrowing stored noots.
- Test to see how `vector<u8>` looks within an explorer; is it human readable? Should we use strings instead?
- Check how stored dynamic fields look on-chain in the explorer; can you still find them?
- Create-family should start off with passing a vector-map
- Inventory-adding functions
- Stackable noots
- Figure out how to get all the package-addresses to match up at the same time
- Begin on V1, which will incorporate dynamic fields / dynamic objects where possible. I still think the data-object should be a separate object (not owned by the noot itself)
- Come up with many-to-one noot -> data relationship
- Come up with actual data-editing abilities
- Break into packages: standard, crafting, data, market, examples
- Add the 'Buy offer' functionality
- Abstract Outlaw Sky to be an inventory-generator
- Show example implementation with different royalties
- Think about auctions
- Build an open-market
- Implement actual randomness
- Perhaps the market should define the transfer cap of a noot?
- The Sui core includes a url standard with has commits of content; that could be useful. Perhaps integrate that
- See if we can transfer a Noot from being part of market-A to market-B. This would be ideal for closing or opening transfer abilities of a noot (even within the same type).
- For extract_owner_cap, perhaps we should drop the is_owner requirement; what if we want some markets to be able to take transfer_caps, even without the owner's consent???
- Perhaps type-info should have 'store', so that it can be shared as well? It might be useful to give type-info to programs so that they can edit type-info arbitrarily; for example, suppose type-info is being controlled by a module rather than a person (keypair)

### Problems to Solve

- On-chain metadata should be compact. However, how do we turn that metadata into a human-readable format? My suggestion is to have some sort of ancilliary off-chain functions (typescript perhaps) that map on-chain data into human-readable strings

### Exploits to Avoid

We should make sure these are not possible.

- **Skipping Royalties:** the concept is that someone deploys a module which wraps a noot transfer function with their own custom marketplace function, so that either marketplace royalties are not paid, or they are paid to the wrong party. For soem marketplaces, we want to enforce this as strictly as possible.

- **Skipping Randomness:** the concept is that someone deploys a module which crafts a randomly-generated noot, and then checks to see if that noot has the desired property that they're farming for; if it doesn't, then they abort the transaction. The net result is that they can do thousands of transactions for just the cost of gas until they manage to get the desired noot, regardless of how improbably rare that noot is.

### Terminology:

**Craft:** accepts inputs, creates and returns a noot.

**Deconstruct:** accepts a noot, destroys it, and then returns any residual output.

**Noot Data:** data pointed to by a Noot.

**Noot DNA:** consists of a display and body.

**Transfer Cap:** a capability scoped to a specific noot. Whoever possess this can take possession of that noot. There is always one and only one transfer_cap per noot.

**Fully Owned Noot:** a noot is 'fully owned' if its transfer_cap is stored inside itself. The noot CANNOT be claimed by any external process.

**Partially Owned Noot:** a noot is 'partially owned' if its transfer_cap is outside of itself. The noot CAN be claimed by an external process.

**Noot Dispenser:** a module that is pre-loaded with a fixed supply of NootDNA. It accepts coins, and returns NootDNA, which is used to craft a Noot.

### Problem with this

Suppose you want to have composable noots, like you have 5 noots that combine into being one noot. How can we do that?

- We can't store the 5 piece noots, because they do not have 'store'. If they did have store, they'd be arbitrarily transferable (on Sui, not on module-ownership). So we could solve his by saying 'fuck it' and adding 'store' to noots, and leaning on module-ownership and ignoring Sui-ownership.
- Child-objects are not possible, because again, the same reason as above.
- We could take the transfer caps out of each of the noots, and then lock them inside of the combined-noot. We'd effectively just allow the component-noots to continue to exist, but you couldn't sell or transfer them, but you could still continue to use them individually if you wanted, which would be a little weird; or maybe we could stop that by putting the owner as 'bricked' or value essentially meaning it no longer exists. If you did sell the combined-noot, whoever has it could take out the transfer caps and reclaim the other noots.
-

### Thoughts:

- Should noot.data_id be optional? Would we want to create a noot which DOESN'T have corresponding data? In that case it would be impossible to display it; it would be kind of an incomplete Noot.
-

### Aptos Token Standard:

- Is 1,400 lines long, complex, and redundant. Property maps is another 250. And this is just for the base standard; it doesn't include markets, auctions, or launchpads. The scope is small; just creating a collection, creating a token, modifying collection or token data, and transferring tokens; that's it. It took them 1,750 lines of code to specify that.
- overfits for the pfp-collection use case, and doesn't really work for much else; i.e., has a 'max supply', and 'royalty' field built in at the base-level.
- Has runtime mutability configuration checking, which makes editing fields depends upon fetching a global resource and checking it every time.
- Has no on-chain metadata; instead its simply linked to using a URI. TokenData is just royalty information, name, and uri.
- Transfers require two signatures (sender and receiver) or for the receiver to 'open up' their store by turning on 'opt in transfers'
- All token-data is stored within a table; updating a user's tokendata requires fetching that data and editing its rows. (Fortunately Aptos can parallelize table reads and writes.) This means data cannot be ported or moved around like an object; for example, you can't remove your data from a collection's store and then lock it with another module which now has the rights to update it.
- Royalty is not actually used in any of their example contract. Royalties are optional and not enforced. They are easy to bypass; it's up to the implementing market to respect them.

### Inventory:

- Note that we use dynamic_field, rather than dynamic_object_field, to keep our inventory as flexible as possible. The dynamic_object_field would require all stored objects to have key, and we don't want to impose this constraint.

The only advantage dynamic_object_field conveys is that it's possible to find the child-objects in a Sui blockchain explorer still; i.e., if you lookup their key-id, you'll be able to see the object. Whereas with dynamic_field, if you lookup the object's key-id, it'll say the object has been wrapped or deleted.

**FUTURE:** Perhaps this can be worked-around by the Sui explorer in the future, or perhaps dynamic_field can be made more general such that it behaves like dynamic_object_field whenever possible (when a value has 'key'). This would simplify the developer's API, since they would use one module / one set of functions, rather than two.

### Controversial Decisions:

- In Inventory, we could relax the read constraints such that they no longer require witnesses. In that case any module could read any other module's namespace data (although it would still have to know what the corresponding types its reading were, which would require knowledge of that specific module). Currently, reads are protected by a module's witness.
- Right now, Noots have key + store. This means they can be polymorphically transferred, which can result in an inconsistent state where the writer is not the owner. Presumably this is undesirable. Furthermore, I believe wrapping (storing) a Noot (outside of an inventory) is also undesirable, but incidentally allowed in this case. Ideally, we would store Noots using the dynamic_object_field, and not enable storing.
- In order for transfer_cap to be useful, it's important that the Noot can be stored if and only if the transfer_cap is inside of the Noot (it's fully owned). Currently with store it's possible that a partially-owned Noot could be stored and inaccessible inside of another struct. This would render the transfer_cap as unusable, and would essentially enable 'stealing'.

### Indexing:

- Find noots by owner
- Find noots by world
- Find noot sell-offer by world

### Other Stuff

- Make sure multiple people can have update authority
- Study ERC-721, 1155, Solana MetaData programs
- Consider changing name of 'owner' to 'user'
