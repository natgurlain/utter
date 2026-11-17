import Testing

@testable import UtterCore

@Suite struct LiveChunkerTests {
    @Test func sendsCompleteSentencesOnce() {
        var chunker = LiveChunker()
        #expect(chunker.add("So I think we should") == nil)
        #expect(chunker.add("ship it tomorrow.") == "So I think we should ship it tomorrow.")
        #expect(chunker.pending == "")
    }

    @Test func holdsShortSentencesForContext() {
        var chunker = LiveChunker()
        #expect(chunker.add("Okay.") == nil)
        #expect(chunker.add("Let's go now.") == "Okay. Let's go now.")
    }

    @Test func cutsLongRunsWithoutPunctuation() {
        var chunker = LiveChunker(minWords: 3, maxWords: 5)
        #expect(chunker.add("one two three") == nil)
        #expect(chunker.add("four five") == "one two three four five")
    }

    @Test func flushReturnsTheRest() {
        var chunker = LiveChunker()
        _ = chunker.add("and then")
        #expect(chunker.flush() == "and then")
        #expect(chunker.flush() == nil)
    }
}

@Suite struct ChunkStitcherTests {
    @Test func joinsSentences() {
        let text = ChunkStitcher.stitch([
            (raw: "so um we ship.", cleaned: "So we ship."),
            (raw: "then check logs", cleaned: "Then check logs."),
        ])
        #expect(text == "So we ship. Then check logs.")
    }

    @Test func repairsAChunkCutMidSentence() {
        let text = ChunkStitcher.stitch([
            (raw: "we should ship the build", cleaned: "We should ship the build."),
            (raw: "tomorrow morning", cleaned: "Tomorrow morning."),
        ])
        #expect(text == "We should ship the build tomorrow morning.")
    }

    @Test func keepsCapitalsThatWereSpoken() {
        let text = ChunkStitcher.stitch([
            (raw: "we met", cleaned: "We met."),
            (raw: "Anna at noon", cleaned: "Anna at noon."),
        ])
        #expect(text == "We met Anna at noon.")
    }

    @Test func singlePieceIsUnchanged() {
        #expect(ChunkStitcher.stitch([(raw: "hi there", cleaned: "Hi there.")]) == "Hi there.")
        #expect(ChunkStitcher.stitch([]) == "")
    }
}
