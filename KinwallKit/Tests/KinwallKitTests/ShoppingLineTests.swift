import Testing
@testable import KinwallKit

@Suite struct ShoppingLineTests {
    @Test func whereItIsThenWhatsAfter() {
        let l = ShoppingLine(aisle: "Dairy", next: ("Dishwasher tablets", "Aisle 17"), left: 3)
        #expect(l.lead == "Dairy · then " && l.name == "Dishwasher tablets" && l.tail == " (Aisle 17)")
        #expect(l.text == "Dairy · then Dishwasher tablets (Aisle 17)")
    }
    @Test func sameAisle() {
        #expect(ShoppingLine(aisle: "Dairy", next: ("Milk", "Dairy"), left: 3).text == "Dairy · then Milk (same aisle)")
    }
    @Test func lastOne() {
        #expect(ShoppingLine(aisle: "Dairy", next: nil, left: 1).text == "Dairy · last one!")
        #expect(ShoppingLine(aisle: nil, next: nil, left: 1).text == "Last one!")
    }
    @Test func noAisles() {
        #expect(ShoppingLine(aisle: nil, next: ("Milk", nil), left: 2).text == "Then Milk")
        #expect(ShoppingLine(aisle: "Dairy", next: ("Milk", nil), left: 2).text == "Dairy · then Milk")
        #expect(ShoppingLine(aisle: nil, next: ("Milk", "Dairy"), left: 2).text == "Then Milk (Dairy)")
    }
    @Test func pastWhatItCarries() {
        // More left than the activity carries: just where the current one is.
        #expect(ShoppingLine(aisle: "Dairy", next: nil, left: 4).text == "Dairy")
        #expect(ShoppingLine(aisle: nil, next: nil, left: 4).text == "")
    }
}
