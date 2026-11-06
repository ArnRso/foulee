// swift-tools-version: 6.2
import PackageDescription

/// Protocole Bluetooth FTMS (Fitness Machine Service) du tapis : décodage des trames, encodage
/// des commandes et bornage de la vitesse, sans dépendance au reste de l'app : testable avec
/// `swift test`.
let package = Package(
    name: "FTMSKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FTMSKit", targets: ["FTMSKit"])
    ],
    targets: [
        .target(name: "FTMSKit", swiftSettings: strictSettings),
        .testTarget(
            name: "FTMSKitTests",
            dependencies: ["FTMSKit"],
            swiftSettings: strictSettings,
        ),
    ],
)

/// Réglages les plus stricts : sûreté mémoire explicite et fonctionnalités à venir de Swift
/// activées dès maintenant.
///
/// Les avertissements sont rendus bloquants par `scripts/test.sh` plutôt qu'ici : Xcode
/// compile les packages locaux en masquant leurs avertissements, ce qui entre en conflit.
var strictSettings: [SwiftSetting] {
    [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
    ]
}
