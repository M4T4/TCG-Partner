import Testing
@testable import DeckKit

@Suite struct DeckParserTests {
    /// Exportada desde Limitless (botón «Copy to clipboard»).
    let dragapult = """
    Pokémon: 17
    4 Dreepy TWM 128
    3 Drakloak TWM 129
    2 Dragapult ex TWM 130
    2 Duskull PRE 35
    1 Dusclops PRE 36
    1 Dusknoir PRE 37
    1 Budew PRE 4
    1 Fezandipiti ex SFA 38
    1 Bloodmoon Ursaluna ex TWM 141
    1 Munkidori TWM 95

    Trainer: 35
    4 Arven SVI 166
    4 Iono PAL 185
    2 Boss's Orders PAL 172
    1 Professor Turo's Scenario PAR 171
    4 Buddy-Buddy Poffin TEF 144
    4 Rare Candy SVI 191
    4 Ultra Ball SVI 196
    2 Night Stretcher SFA 61
    2 Counter Catcher PAR 160
    1 Super Rod PAL 188
    1 Unfair Stamp TWM 165
    2 Rescue Board TEF 159
    1 Sparkling Crystal SCR 142
    1 Technical Machine: Evolution PAR 178
    2 Artazon PAL 171

    Energy: 8
    3 Basic {R} Energy SVE 2
    3 Basic {P} Energy SVE 5
    2 Luminous Energy PAL 191

    Total Cards: 60
    """

    @Test func limitlessExport() {
        let deck = DeckParser.parse(dragapult)
        #expect(deck.unparsedLines.isEmpty)
        #expect(deck.totalCount == 60)
        #expect(deck.isStandardSize)
        #expect(deck.count(in: .pokemon) == 17)
        #expect(deck.count(in: .trainer) == 35)
        #expect(deck.count(in: .energy) == 8)
        #expect(deck.entries.first == CardEntry(count: 4, name: "Dreepy", setCode: "TWM", number: "128", section: .pokemon))
        #expect(deck.entries.contains { $0.name == "Technical Machine: Evolution" && $0.setCode == "PAR" })
        #expect(deck.entries.contains { $0.name == "Boss's Orders" && $0.number == "172" })
        #expect(deck.suggestedName == "Dragapult ex")
    }

    @Test func exportRoundTrip() {
        let deck = DeckParser.parse(dragapult)
        #expect(deck.export() == dragapult)
        #expect(DeckParser.parse(deck.export()).entries == deck.entries)
    }

    @Test func oldPTCGLiveFormat() {
        let deck = DeckParser.parse("""
        ******  Pokémon Trading Card Game Deck List  ******

        ##Pokémon - 6
        * 4 Charizard ex OBF 125
        * 2 Pidgey MEW 16

        ##Trainer Cards - 4
        * 4 Rare Candy SVI 191

        ##Energy - 6
        * 6 Fire Energy SVE 2

        Total Cards - 16
        """)
        #expect(deck.unparsedLines.isEmpty)
        #expect(deck.totalCount == 16)
        #expect(!deck.isStandardSize)
        #expect(deck.count(in: .pokemon) == 6)
        #expect(deck.entries(in: .trainer).map(\.name) == ["Rare Candy"])
        #expect(deck.entries(in: .energy).first?.setCode == "SVE")
    }

    @Test func promosGalleryAndNameOnly() {
        let deck = DeckParser.parse("""
        Pokémon: 3
        1 Pikachu with Grey Felt Hat SVP 85
        1 Charizard VSTAR BRS TG03
        1 Radiant Charizard PGO 11
        Trainer: 4
        4 Arven
        Energy: 8
        8 Basic {P} Energy
        """)
        #expect(deck.unparsedLines.isEmpty)
        #expect(deck.entries[0] == CardEntry(count: 1, name: "Pikachu with Grey Felt Hat", setCode: "SVP", number: "85", section: .pokemon))
        #expect(deck.entries[1].number == "TG03")
        #expect(deck.entries[1].paddedNumber == "TG03")
        #expect(deck.entries[2].paddedNumber == "011")
        #expect(deck.entries[3] == CardEntry(count: 4, name: "Arven", section: .trainer))
        #expect(deck.entries[4].section == .energy)
        #expect(deck.entries[4].setCode == nil)
    }

    @Test func spanishHeadersAndNoHeaders() {
        let spanish = DeckParser.parse("Entrenadores: 4\n4 Arven SVI 166\nEnergía: 2\n2 Basic {W} Energy SVE 3")
        #expect(spanish.entries.map(\.section) == [.trainer, .energy])
        let bare = DeckParser.parse("4 Dreepy TWM 128\n3 Basic {P} Energy SVE 5")
        #expect(bare.entries.map(\.section) == [.pokemon, .energy])
    }

    @Test func unparsedLines() {
        let deck = DeckParser.parse("Pokémon: 4\n4 Dreepy TWM 128\nhola mundo\nx Pikachu")
        #expect(deck.totalCount == 4)
        #expect(deck.unparsedLines == ["hola mundo", "x Pikachu"])
    }

    @Test func searchNamesAndKeys() {
        #expect(CardEntry(count: 1, name: "Basic {P} Energy", section: .energy).searchName == "Psychic Energy")
        #expect(CardEntry(count: 1, name: "Basic {D} Energy", section: .energy).searchName == "Darkness Energy")
        #expect(CardEntry(count: 1, name: "Luminous Energy", section: .energy).searchName == "Luminous Energy")
        #expect(CardEntry(count: 1, name: "Basic {R} Energy", section: .energy).printName == "Basic Fire Energy")
        #expect(CardEntry(count: 1, name: "Dragapult ex", section: .pokemon).printName == "Dragapult ex")
        #expect(CardEntry(count: 1, name: "Dreepy", setCode: "TWM", number: "128", section: .pokemon).cardKey == "TWM-128")
        #expect(CardEntry(count: 1, name: "Basic {P} Energy", setCode: "SVE", number: "5", section: .energy).paddedNumber == "005")
    }

    @Test func summary() {
        #expect(DeckParser.parse(dragapult).summary == "60 cartas · 17 Pokémon · 35 Entrenador · 8 Energía")
    }
}
