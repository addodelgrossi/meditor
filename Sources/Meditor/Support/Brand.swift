import SwiftUI

enum Brand {
    static let aqua = Color(red: 0.16, green: 0.82, blue: 0.86)
    static let indigo = Color(red: 0.33, green: 0.39, blue: 0.96)
    static let gradient = LinearGradient(
        colors: [aqua, indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
