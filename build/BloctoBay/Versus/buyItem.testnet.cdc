import FungibleToken from 0x9a0766d93b6608b7
import NonFungibleToken from 0x631e88ae7f1d7c20
import NFTStorefront from 0x94b06cfca1d8a476
import Marketplace from 0xe1aa310cfe7750c4
import FlowToken from 0x7e60df042a9c0868
import Art from 0x99ca04281098b33d

transaction(listingResourceID: UInt64, storefrontAddress: Address, buyPrice: UFix64) {
    let paymentVault: @FungibleToken.Vault
    let artCollection: &Art.Collection{NonFungibleToken.Receiver}
    let storefront: &NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}
    let listing: &NFTStorefront.Listing{NFTStorefront.ListingPublic}

    prepare(signer: AuthAccount) {
        // Create a collection to store the purchase if none present
        if signer.borrow<&Art.Collection>(from: Art.CollectionStoragePath) == nil {
            signer.save(<-Art.createEmptyCollection(), to: Art.CollectionStoragePath)
            signer.link<&Art.Collection{Art.CollectionPublic, NonFungibleToken.CollectionPublic}>(
                Art.CollectionPublicPath,
                target: Art.CollectionStoragePath
            )
        }

        self.storefront = getAccount(storefrontAddress)
            .getCapability<&NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}>(NFTStorefront.StorefrontPublicPath)
            .borrow()
            ?? panic("Could not borrow Storefront from provided address")

        self.listing = self.storefront.borrowListing(listingResourceID: listingResourceID)
            ?? panic("No Offer with that ID in Storefront")
        let price = self.listing.getDetails().salePrice

        assert(buyPrice == price, message: "buyPrice is NOT same with salePrice")

        let flowTokenVault = signer.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Cannot borrow FlowToken vault from signer storage")
        self.paymentVault <- flowTokenVault.withdraw(amount: price)

        self.artCollection = signer.borrow<&Art.Collection{NonFungibleToken.Receiver}>(from: Art.CollectionStoragePath)
            ?? panic("Cannot borrow NFT collection receiver from account")
    }

    execute {
        let item <- self.listing.purchase(payment: <-self.paymentVault)

        self.artCollection.deposit(token: <-item)

        // Be kind and recycle
        self.storefront.cleanup(listingResourceID: listingResourceID)
        Marketplace.removeListing(id: listingResourceID)
    }

}