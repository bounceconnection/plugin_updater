import Testing
import Foundation
@testable import Pluginventory

@Suite("AssetNames Constants Tests")
struct AssetNamesTests {

    @Test("MenuBarIcon asset name is correct")
    func menuBarIconName() {
        #expect(Constants.AssetNames.menuBarIcon == "MenuBarIcon")
    }

    @Test("AppIcon asset name is correct")
    func appIconName() {
        #expect(Constants.AssetNames.appIcon == "AppIcon")
    }

    @Test("Asset names are non-empty strings")
    func assetNamesNonEmpty() {
        #expect(!Constants.AssetNames.menuBarIcon.isEmpty)
        #expect(!Constants.AssetNames.appIcon.isEmpty)
    }

    @Test("Asset names are distinct")
    func assetNamesDistinct() {
        #expect(Constants.AssetNames.menuBarIcon != Constants.AssetNames.appIcon)
    }
}
