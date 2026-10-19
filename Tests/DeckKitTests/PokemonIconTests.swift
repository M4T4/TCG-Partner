import Testing
@testable import DeckKit

@Suite struct PokemonIconTests {
    @Test func cardNamesToSlugs() {
        #expect(PokemonIcon.slug("Alakazam") == "alakazam")
        #expect(PokemonIcon.slug("Dragapult ex") == "dragapult")
        #expect(PokemonIcon.slug("Charizard VSTAR") == "charizard")
        #expect(PokemonIcon.slug("Raging Bolt ex") == "raging-bolt")
        #expect(PokemonIcon.slug("Iron Hands ex") == "iron-hands")
        #expect(PokemonIcon.slug("Mr. Mime") == "mr-mime")
        #expect(PokemonIcon.slug("Farfetch'd") == "farfetchd")
        #expect(PokemonIcon.slug("Ho-Oh") == "ho-oh")
        #expect(PokemonIcon.slug("Porygon-Z") == "porygon-z")
        #expect(PokemonIcon.slug("Flabébé") == "flabebe")
    }

    @Test func formsAndPrefixes() {
        #expect(PokemonIcon.slug("Alolan Ninetales") == "ninetales-alola")
        #expect(PokemonIcon.slug("Hisuian Zoroark VSTAR") == "zoroark-hisui")
        #expect(PokemonIcon.slug("Mega Lucario ex") == "lucario-mega")
        #expect(PokemonIcon.slug("Mega Charizard X ex") == "charizard-mega-x")
        #expect(PokemonIcon.slug("Wellspring Mask Ogerpon ex") == "ogerpon-wellspring")
        #expect(PokemonIcon.slug("Teal Mask Ogerpon ex") == "ogerpon")
        #expect(PokemonIcon.slug("Bloodmoon Ursaluna ex") == "ursaluna-bloodmoon")
        #expect(PokemonIcon.slug("Origin Forme Palkia VSTAR") == "palkia-origin")
        #expect(PokemonIcon.slug("Rapid Strike Urshifu VMAX") == "urshifu-rapid-strike")
        #expect(PokemonIcon.slug("Black Kyurem ex") == "kyurem-black")
        #expect(PokemonIcon.slug("Ethan's Typhlosion") == "typhlosion")
        #expect(PokemonIcon.slug("Team Rocket's Mewtwo ex") == "mewtwo")
        #expect(PokemonIcon.slug("Radiant Charizard") == "charizard")
    }

    @Test func candidatesAndSplit() {
        #expect(PokemonIcon.candidates("Alakazam Fantasma") == ["alakazam-fantasma", "alakazam"])
        #expect(PokemonIcon.candidates("Gardevoir ex") == ["gardevoir"])
        #expect(PokemonIcon.candidates("") == [])
        #expect(PokemonIcon.split("Alakazam / Dusknoir") == ["Alakazam", "Dusknoir"])
        #expect(PokemonIcon.split("Charizard ex + Pidgeot ex + Fezandipiti") == ["Charizard ex", "Pidgeot ex"])
        #expect(PokemonIcon.split("Gardevoir ex") == ["Gardevoir ex"])
        #expect(PokemonIcon.url(slug: "alakazam").absoluteString == "https://r2.limitlesstcg.net/pokemon/gen9/alakazam.png")
    }
}

@Suite struct IconPickerLogicTests {
    @Test func secondPokemonKeepsInheritedFirst() {
        // Carpeta sin iconos propios que hereda «Alakazam»: escribir solo el segundo conserva el primero.
        let result = PokemonIcon.combine(first: "", second: "Dusknoir", previous: [], inherited: ["Alakazam"])
        #expect(result.names == ["Alakazam", "Dusknoir"])
        #expect(result.first == "Alakazam")
    }

    @Test func bothFieldsTyped() {
        let result = PokemonIcon.combine(first: "Alakazam", second: "Dusknoir", previous: ["Alakazam"], inherited: [])
        #expect(result.names == ["Alakazam", "Dusknoir"])
    }

    @Test func clearingFirstOnPurposeKeepsOnlySecond() {
        // Si ya tenía iconos propios y borras el primero, no se vuelve a meter el heredado.
        let result = PokemonIcon.combine(first: "", second: "Dusknoir", previous: ["Alakazam", "Dusknoir"], inherited: ["Alakazam"])
        #expect(result.names == ["Dusknoir"])
        #expect(result.first == "")
    }

    @Test func emptyMeansInherit() {
        #expect(PokemonIcon.combine(first: " ", second: "", previous: ["Gengar"], inherited: ["Alakazam"]).names == [])
        // Sin heredado no hay nada que rellenar.
        #expect(PokemonIcon.combine(first: "", second: "Dusknoir", previous: [], inherited: []).names == ["Dusknoir"])
    }
}
