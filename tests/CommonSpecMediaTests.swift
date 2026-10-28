import AVFoundation
import Foundation

/// Fixture readiness checks only; session restoration is tested after stage 1 exists.
@main struct CommonSpecMediaTests {
    @MainActor static func main() async throws {
        let base = URL(string: CommandLine.arguments[1])!
        let server = try await DLNAClient().server(at: base.appendingPathComponent("description.xml"))
        let entries = try await DLNAClient().browse(server, objectID: "normal")
        precondition(entries.count == 2 && entries.allSatisfy { $0.resourceURL != nil })
        let controller = PlaybackController()
        let urls = entries.compactMap(\.resourceURL)
        controller.setPlaylist(urls)
        for url in urls {
            controller.select(url, autoplay: false)
            let deadline = Date().addingTimeInterval(15)
            while controller.isLoading && Date() < deadline {
                try await Task.sleep(for: .milliseconds(25))
            }
            precondition(!controller.isLoading && controller.error == nil, "HTTP fixture must prepare")
            precondition(controller.player.currentItem!.duration.seconds >= 89.9, "Need a long fixture")
            precondition(controller.mediaInfo.video.contains("fps"), "Video metadata must be available")
            let finished = await controller.player.seek(to: CMTime(seconds: 30, preferredTimescale: 600),
                                                        toleranceBefore: .zero, toleranceAfter: .zero)
            precondition(finished && abs(controller.player.currentTime().seconds - 30) < 0.1)
            precondition(controller.player.rate == 0 && !controller.state.wantsToPlay)
        }
        controller.setPlaylist([])
        print("PASS: long OP/ED HTTP preparation, video metadata and paused 30-second seek (not session acceptance)")
    }
}
