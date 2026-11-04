import Testing
@testable import UtterCore

@Suite struct TriggerGestureTests {
    @Test func holdThenReleaseFinishes() {
        var g = TriggerGesture(tapThreshold: 0.3)
        #expect(g.press(at: 0) == .start)
        #expect(g.release(at: 1.2) == .finish)
        #expect(g.state == .idle)
    }

    @Test func quickTapEntersHandsFreeAndSecondPressFinishesOnRelease() {
        var g = TriggerGesture(tapThreshold: 0.3)
        #expect(g.press(at: 0) == .start)
        #expect(g.release(at: 0.1) == .enterHandsFree)
        #expect(g.press(at: 5) == .none)
        #expect(g.release(at: 5.1) == .finish)
        #expect(g.state == .idle)
    }

    @Test func chordWhileHoldingCancels() {
        var g = TriggerGesture()
        _ = g.press(at: 0)
        #expect(g.interrupt() == .cancel)
        #expect(g.release(at: 0.5) == .none)
    }

    @Test func shortcutDuringHandsFreeKeepsListening() {
        var g = TriggerGesture()
        _ = g.press(at: 0)
        _ = g.release(at: 0.1)
        _ = g.press(at: 2)
        #expect(g.interrupt() == .none)
        #expect(g.state == .handsFree)
        #expect(g.release(at: 2.2) == .none)
    }

    @Test func escapeCancelsUnlessIdle() {
        var g = TriggerGesture()
        #expect(g.escape() == .none)
        _ = g.press(at: 0)
        _ = g.release(at: 0.1)
        #expect(g.escape() == .cancel)
        #expect(g.state == .idle)
    }
}

@Suite struct TranscriptAccumulatorTests {
    @Test func joinsSegmentsWithSingleSpaces() {
        var t = TranscriptAccumulator()
        t.apply("Hello", isFinal: true)
        t.apply("world", isFinal: false)
        #expect(t.display == "Hello world")
        t.apply("world.", isFinal: true)
        #expect(t.result == "Hello world.")
    }

    @Test func doesNotSpaceBeforePunctuationOrDoubleSpace() {
        var t = TranscriptAccumulator()
        t.apply("Hi ", isFinal: true)
        t.apply(" there", isFinal: true)
        t.apply(", friend", isFinal: true)
        #expect(t.result == "Hi  there, friend")
    }

    @Test func volatileTextIsNotInserted() {
        var t = TranscriptAccumulator()
        t.apply("maybe", isFinal: false)
        #expect(t.result == "")
        #expect(t.display == "maybe")
    }
}

@Suite struct LocaleResolverTests {
    let supported: Set<String> = ["en-US", "en-GB", "pl-PL", "de-DE", "de-AT"]

    @Test func exactMatch() {
        #expect(LocaleResolver.resolve("pl-PL", supported: supported, preferredRegion: nil) == "pl-PL")
    }

    @Test func languageMatchPrefersRegionThenUS() {
        #expect(LocaleResolver.resolve("en-PL", supported: supported, preferredRegion: "GB") == "en-GB")
        #expect(LocaleResolver.resolve("en-PL", supported: supported, preferredRegion: "PL") == "en-US")
        #expect(LocaleResolver.resolve("de-CH", supported: supported, preferredRegion: nil) == "de-AT")
    }

    @Test func fallsBackToEnglish() {
        #expect(LocaleResolver.resolve("xx-YY", supported: supported, preferredRegion: nil) == "en-US")
    }
}
