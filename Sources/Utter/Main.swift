import Foundation

/// Entry point. With `--transcribe <audio-file> [--locale <bcp47>]` Utter runs
/// headless, prints the transcript and exits (for testing the speech pipeline
/// without a microphone). Otherwise it starts the menu bar app.
@main
enum Main {
    @MainActor
    static func main() async {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--transcribe"), index + 1 < arguments.count else {
            UtterApp.main()
            return
        }
        let url = URL(fileURLWithPath: arguments[index + 1])
        let localeID = arguments.firstIndex(of: "--locale").flatMap {
            $0 + 1 < arguments.count ? arguments[$0 + 1] : nil
        } ?? Locale.current.identifier(.bcp47)

        do {
            let transcriber = Transcriber()
            let resolved = try await transcriber.prepare(localeID: localeID)
            FileHandle.standardError.write(Data("Utter: transcribing with \(resolved)\n".utf8))
            print(try await transcriber.transcribe(file: url))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Utter: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
