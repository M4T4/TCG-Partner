import Testing
@testable import DeckKit

@Suite struct PlacementTests {
    @Test func textAndTitle() {
        let third = Placement(place: 3, players: 64)!
        #expect(third.text == "3.º de 64")
        #expect(third.title == "Top 4")
        #expect(Placement(place: 1)!.title == "Campeón")
        #expect(Placement(place: 2, players: 30)!.title == "Finalista")
        #expect(Placement(place: 7, players: 120)!.title == "Top 8")
        #expect(Placement(place: 9, players: 120)!.title == "Top 16")
        #expect(Placement(place: 12)!.text == "12.º")
    }

    @Test func noCutWhenItCoversTheWholeTournament() {
        #expect(Placement(place: 5, players: 8)!.title == nil)
        #expect(Placement(place: 5, players: 20)!.title == "Top 8")
        #expect(Placement(place: 300)!.title == nil)
    }

    @Test func invalidValues() {
        #expect(Placement(place: nil) == nil)
        #expect(Placement(place: 0) == nil)
        #expect(Placement(place: 4, players: 0)!.players == nil)
        #expect(Placement(place: 4)!.medal == 3)
        #expect(Placement(place: 1)!.medal == 1)
        #expect(Placement(place: 5)!.medal == nil)
    }

    @Test func ranking() {
        let results = [Placement(place: 5, players: 40)!, Placement(place: 2, players: 16)!,
                       Placement(place: 2, players: 50)!, Placement(place: 9)!]
        let sorted = results.sorted(by: Placement.isBetter)
        #expect(sorted.map(\.text) == ["2.º de 50", "2.º de 16", "5.º de 40", "9.º"])
    }
}
