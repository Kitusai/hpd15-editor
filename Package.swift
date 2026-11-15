// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EditeurHPD15",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "HPD15", targets: ["HPD15"]),
        .executable(name: "HPD15Diag", targets: ["HPD15Diag"]),
        .executable(name: "HPD15Checks", targets: ["HPD15Checks"])
    ],
    targets: [
        // Logique pure : adresses, trames Roland (Model ID 00 2E), codage nibblé,
        // carte d'adresses, client RQ1/DT1, catalogue. Aucune dépendance à CoreMIDI.
        .target(name: "HPD15Core", resources: [.copy("Resources/catalog-hpd15.json")]),
        // Application « Editeur HPD15 » (SwiftUI + CoreMIDI).
        .executableTarget(name: "HPD15", dependencies: ["HPD15Core"]),
        // Outil de diagnostic en console (CoreMIDI, UM-ONE).
        .executableTarget(name: "HPD15Diag", dependencies: ["HPD15Core"]),
        // Vérifications sans matériel (sans XCTest : fonctionne avec les seuls Command Line Tools).
        .executableTarget(name: "HPD15Checks", dependencies: ["HPD15Core"])
    ]
)
