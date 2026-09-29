import AppIntents
import SwiftUI
import WidgetKit

// Controls (iOS 18): Control Center, the Lock Screen's control slots and the Action button. Each
// opens the app somewhere with an intent from native/ios/OpenIntents.swift, which iOS runs in the
// app (openAppWhenRun), so they work signed out or offline too: the app opens where it can.

@available(iOS 18.0, *)
struct AddToGroceriesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "family.kinwall.app.control.add") {
            ControlWidgetButton(action: OpenGroceriesIntent()) { Label("Add to Groceries", systemImage: "cart.badge.plus") }
        }
        .displayName("Add to Groceries")
        .description("Opens Groceries in Kinwall, ready to add.")
    }
}

@available(iOS 18.0, *)
struct StartShoppingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "family.kinwall.app.control.shop") {
            ControlWidgetButton(action: ShopGroceriesIntent()) { Label("Start shopping", systemImage: "cart") }
        }
        .displayName("Start shopping")
        .description("Opens Kinwall's shopping mode on Groceries.")
    }
}

@available(iOS 18.0, *)
struct NightScreenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "family.kinwall.app.control.night") {
            ControlWidgetButton(action: NightScreenIntent()) { Label("Night screen", systemImage: "moon.stars") }
        }
        .displayName("Night screen")
        .description("Opens Kinwall on the dim night clock.")
    }
}

@available(iOS 18.0, *)
struct KinwallControls: WidgetBundle {
    var body: some Widget {
        AddToGroceriesControl()
        StartShoppingControl()
        NightScreenControl()
    }
}
