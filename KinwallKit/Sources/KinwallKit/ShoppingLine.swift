import Foundation

/// The shopping trip Live Activity's line under the current item: where it is, then what's after
/// it. "Dairy · then Dishwasher tablets (Aisle 17)", "then Milk (same aisle)", "Dairy · last one!".
/// In three parts so the view can shorten the next item's name and never the aisle.
public struct ShoppingLine: Equatable, Sendable {
    public let lead: String
    public let name: String
    public let tail: String
    public var text: String { lead + name + tail }

    /// `aisle`: the current item's; `next`: the item after it (title, aisle) if the activity has it;
    /// `left`: items left, the current one included.
    public init(aisle: String?, next: (title: String, aisle: String?)?, left: Int) {
        let aisle = aisle.flatMap { $0.isEmpty ? nil : $0 }
        let at = aisle.map { "\($0) · " } ?? ""
        if let next {
            let nextAisle = next.aisle.flatMap { $0.isEmpty ? nil : $0 }
            lead = aisle == nil ? "Then " : at + "then "
            name = next.title
            tail = nextAisle.map { $0 == aisle ? " (same aisle)" : " (\($0))" } ?? ""
        } else if left == 1 {
            lead = aisle == nil ? "Last one!" : at + "last one!"; name = ""; tail = ""
        } else {
            lead = aisle ?? ""; name = ""; tail = ""
        }
    }
}
