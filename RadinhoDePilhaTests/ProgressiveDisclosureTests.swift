import Foundation
import Testing
@testable import RadinhoDePilha

@Suite("Progressive disclosure")
@MainActor
struct ProgressiveDisclosureTests {
    private func loadedViewModel(
        matchID: String = SampleMatches.liveComeback.id
    ) async -> (MatchNarrationViewModel, SpeechServiceSpy) {
        let spy = SpeechServiceSpy()
        let viewModel = MatchNarrationViewModel(
            provider: InMemoryMatchDataProvider.sample(),
            speech: spy
        )
        await viewModel.load(matchID: matchID)

        return (viewModel, spy)
    }

    // MARK: - Layers

    @Test("The first layer says the score and the stage of the match, and nothing more")
    func scoreLayerIsBrief() async {
        let (viewModel, spy) = await loadedViewModel()

        await viewModel.speakScore()

        #expect(await spy.interruptingText == ["Náutico 2, CRB 1. Segundo tempo, 67 minutos."])
    }

    @Test("The second layer says the latest moment and the one before it")
    func recentLayerSaysTheLastTwoMoments() async throws {
        let (viewModel, spy) = await loadedViewModel()
        let narrations = viewModel.narrations
        let latest = try #require(narrations.last)
        let previous = narrations[narrations.count - 2]

        await viewModel.speakRecentMoments()

        let spoken = try #require(await spy.interruptingText.last)
        #expect(spoken == "Último lance. \(latest.text) Antes disso. \(previous.text)")
    }

    @Test("A match with no moments says so instead of staying silent")
    func recentLayerHandlesAnEmptyMatch() async {
        let (viewModel, spy) = await loadedViewModel(matchID: SampleMatches.scheduled.id)

        await viewModel.speakRecentMoments()

        #expect(await spy.interruptingText == ["Ainda não houve lances nesta partida."])
    }

    // MARK: - Stepping through the match

    @Test("Stepping back starts from the latest moment and moves towards the first")
    func steppingBackWalksTowardsTheStart() async throws {
        let (viewModel, spy) = await loadedViewModel()
        let narrations = viewModel.narrations

        await viewModel.speakPreviousMoment()
        await viewModel.speakPreviousMoment()

        let spoken = await spy.interrupting
        let expected = [narrations[narrations.count - 1].id, narrations[narrations.count - 2].id]
        #expect(spoken.map(\.id) == expected)
    }

    @Test("Stepping back past the first moment says there is nothing earlier")
    func steppingBackStopsAtTheStart() async {
        let (viewModel, spy) = await loadedViewModel()

        for _ in viewModel.narrations {
            await viewModel.speakPreviousMoment()
        }
        await viewModel.speakPreviousMoment()

        #expect(await spy.interruptingText.last == "Este é o primeiro lance da partida.")
    }

    @Test("Stepping forward returns towards the present")
    func steppingForwardReturns() async {
        let (viewModel, spy) = await loadedViewModel()
        let narrations = viewModel.narrations

        await viewModel.speakPreviousMoment()
        await viewModel.speakPreviousMoment()
        await viewModel.speakNextMoment()

        #expect(await spy.interrupting.last?.id == narrations[narrations.count - 1].id)
    }

    @Test("Stepping forward from the present says this is the latest moment")
    func steppingForwardStopsAtThePresent() async {
        let (viewModel, spy) = await loadedViewModel()

        await viewModel.speakNextMoment()

        #expect(await spy.interruptingText == ["Este é o lance mais recente."])
        #expect(await spy.interrupting.isEmpty)
    }

    // MARK: - Before kick-off

    @Test("The pre-match briefing is spoken at once, since it was asked for")
    func previewInterrupts() async throws {
        let (viewModel, spy) = await loadedViewModel(matchID: SampleMatches.scheduled.id)

        await viewModel.speakPreview()

        let spoken = try #require(await spy.interruptingText.last)
        #expect(spoken.hasPrefix("Pré-jogo."))
        #expect(spoken.contains("CRB e Náutico"))
    }
}
