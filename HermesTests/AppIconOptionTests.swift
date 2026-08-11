import Foundation
import Testing
@testable import Hermes

@Suite("App icon options")
struct AppIconOptionTests {
    @Test("The primary seal icon has no alternate name")
    func sealIsPrimary() {
        #expect(AppIconOption.seal.alternateIconName == nil)
    }

    @Test("Alternate icons map to their asset-catalog names")
    func alternateNames() {
        #expect(AppIconOption.luminous.alternateIconName == "AppIcon-Luminous")
        #expect(AppIconOption.engraved.alternateIconName == "AppIcon-Engraved")
        #expect(AppIconOption.signal.alternateIconName == "AppIcon-Signal")
        #expect(AppIconOption.original.alternateIconName == "AppIcon-Original")
    }

    @Test("Alternate icon names are unique across options")
    func uniqueNames() {
        let names = AppIconOption.allCases.compactMap(\.alternateIconName)
        #expect(Set(names).count == names.count)
        #expect(names.count == AppIconOption.allCases.count - 1)
    }

    @Test("A nil alternate name resolves to the primary seal")
    func currentFromNil() {
        #expect(AppIconOption.current(alternateIconName: nil) == .seal)
    }

    @Test("An alternate name resolves back to its option", arguments: AppIconOption.allCases)
    func roundTrip(option: AppIconOption) {
        #expect(AppIconOption.current(alternateIconName: option.alternateIconName) == option)
    }

    @Test("An unknown alternate name falls back to the primary seal")
    func unknownFallsBack() {
        #expect(AppIconOption.current(alternateIconName: "AppIcon-DoesNotExist") == .seal)
    }

    @Test("Every option has a display name and a preview asset")
    func metadataPresent() {
        for option in AppIconOption.allCases {
            #expect(!option.displayName.isEmpty)
            #expect(option.previewAssetName.hasPrefix("IconPreview-"))
        }
    }
}
