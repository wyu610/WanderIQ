import SwiftUI
import UIKit

/// "Warm Wayfarer" palette — matches the web app (warm sand canvas, forest-teal
/// ink, terracotta accent). Applied app-wide via `.tint` + UIKit bar appearance.
extension Color {
    static let wSand = Color(red: 0.965, green: 0.945, blue: 0.910)   // #F6F1E8
    static let wPaper = Color(red: 1.000, green: 0.992, blue: 0.973)  // #FFFDF8
    static let wInk = Color(red: 0.122, green: 0.227, blue: 0.204)    // #1F3A34
    static let wInkSoft = Color(red: 0.329, green: 0.388, blue: 0.365)
    static let wTerracotta = Color(red: 0.878, green: 0.478, blue: 0.373) // #E07A5F
    static let wTeal = Color(red: 0.184, green: 0.522, blue: 0.463)   // #2F8576
    static let wLine = Color(red: 0.906, green: 0.867, blue: 0.800)   // #E7DDCC
}

enum Theme {
    /// Configure global navigation- and tab-bar appearance: warm sand bars with
    /// serif (New York) titles echoing the web's Fraunces, and ink text.
    static func apply() {
        let sand = UIColor(Color.wSand)
        let ink = UIColor(Color.wInk)

        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let desc = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            return UIFont(descriptor: desc, size: size)
        }

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = sand
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: ink, .font: serif(17, .semibold)]
        nav.largeTitleTextAttributes = [.foregroundColor: ink, .font: serif(32, .bold)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = sand
        tab.shadowColor = UIColor(Color.wLine)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

/// Apply the warm sand canvas to a List/Form screen (hides the default grey
/// grouped background so white cells read as cards on sand, like the web).
extension View {
    func warmCanvas() -> some View {
        self.scrollContentBackground(.hidden).background(Color.wSand)
    }
}
