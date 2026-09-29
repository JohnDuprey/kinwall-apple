import Foundation
import Testing
@testable import KinwallKit

@Suite struct CheckInTests {
    func tc(_ json: String) throws -> TempCheck { try JSONDecoder().decode(TempCheck.self, from: Data(json.utf8)) }
    let settings = #""settings":{"on":true,"sleep":true,"feelings":true,"goal":true,"showGoal":true,"evening":true,"eveningTime":"21:00","journal":true,"battery":true}"#

    @Test func morningGoesSleepFeelingsGoal() throws {
        let base = #"{"memberId":"m3","date":"2026-09-29",\#(settings),"private":false,"sleep":null,"feelings":null,"goal":null,"goalSkipped":false,"followup":null,"followupOpen":false,"drained":null,"drainedOpen":false,"custom":["sleepy"],"#
        #expect(try tc(base + #""answered":{"sleep":false,"feelings":false,"goal":false,"followup":false,"drained":false}}"#).step == .sleep)
        #expect(try tc(base + #""answered":{"sleep":true,"feelings":false,"goal":false,"followup":false,"drained":false}}"#).step == .feelings)
        #expect(try tc(base + #""answered":{"sleep":true,"feelings":true,"goal":false,"followup":false,"drained":false}}"#).step == .goal)
        #expect(try tc(base + #""answered":{"sleep":true,"feelings":true,"goal":true,"followup":false,"drained":false}}"#).step == .done)
    }

    @Test func eveningGoesFollowupThenDrained() throws {
        let base = #"{"memberId":"m3","date":"2026-09-29",\#(settings),"private":false,"sleep":"good","feelings":["good"],"goal":"Read","goalSkipped":false,"followup":null,"followupOpen":true,"drained":null,"drainedOpen":true,"custom":[],"#
        #expect(try tc(base + #""answered":{"sleep":true,"feelings":true,"goal":true,"followup":false,"drained":false}}"#).step == .followup)
        #expect(try tc(base + #""answered":{"sleep":true,"feelings":true,"goal":true,"followup":true,"drained":false}}"#).step == .drained)
        #expect(try tc(base + #""answered":{"sleep":true,"feelings":true,"goal":true,"followup":true,"drained":true}}"#).step == .done)
    }

    @Test func offOrPrivate() throws {
        let off = #"{"memberId":"m3","date":"d","settings":{"on":false,"sleep":true,"feelings":true,"goal":true,"showGoal":true,"evening":false,"eveningTime":"21:00","journal":true,"battery":false},"private":false,"sleep":null,"feelings":null,"goal":null,"goalSkipped":false,"followup":null,"followupOpen":false,"drained":null,"drainedOpen":false,"custom":[],"answered":{"sleep":false,"feelings":false,"goal":false,"followup":false,"drained":false}}"#
        #expect(try tc(off).step == .off)
    }

    @Test func feelingChoicesPutTheirOwnFirst() {
        #expect(TempCheck.feelingChoices(custom: ["sleepy", "Good"], limit: 4) == ["sleepy", "great", "good", "fine"])
    }

    @Test func batterySummary() throws {
        let json = #"{"memberId":"m3","on":true,"today":"2026-09-29","days":[{"date":"2026-09-29","forecast":false,"start":70,"drain":28,"level":62,"reasons":[{"text":"Sleep: good","points":75},{"text":"1 event","points":-10},{"text":"Goal for today","points":-5},{"text":"Learning","points":0}],"lowBefore":null},{"date":"2026-09-30","forecast":true,"start":70,"drain":85,"level":0,"reasons":[],"lowBefore":"Art class"}],"warnings":[{"date":"2026-09-30","text":"Tomorrow looks full: 5 events. Maybe plan a rest?","suggestions":[]}]}"#
        let b = try JSONDecoder().decode(Battery.self, from: Data(json.utf8))
        let s = try #require(b.summary)
        #expect(s.level == 62 && s.line == "62% · Good by this evening")
        #expect(s.reasons == ["Sleep: good", "1 event"])
        #expect(s.headsUp == "Tomorrow looks full: 5 events. Maybe plan a rest?")
        #expect(Battery.word(80) == "Full" && Battery.word(24) == "Running low")
        let off = try JSONDecoder().decode(Battery.self, from: Data(#"{"memberId":"m1","on":false,"today":"2026-09-29","days":[],"warnings":[]}"#.utf8))
        #expect(off.summary == nil)
    }
}
