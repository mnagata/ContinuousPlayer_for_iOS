import Foundation
import AVFoundation

@main struct DLNATests {
    static let base = URL(string: "http://192.0.2.1:8200/description.xml")!
    static let description = """
    <root xmlns="urn:schemas-upnp-org:device-1-0"><URLBase>http://192.0.2.1:8200/base/</URLBase><device>
    <deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType><friendlyName>NAS &amp; Video</friendlyName><UDN>uuid:nas</UDN>
    <serviceList><service><serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType><controlURL>ContentDirectory</controlURL></service></serviceList>
    </device></root>
    """
    static func didl(_ content: String) -> String {
        "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\(content)</DIDL-Lite>"
    }
    static func item(_ id: String, _ title: String, _ resource: String = "<res protocolInfo=\"http-get:*:video/mp4:*\" size=\"1234\">/stream?id=1&amp;token=x</res>") -> String {
        "<item id=\"\(id)\"><dc:title>\(title)</dc:title>\(resource)</item>"
    }
    static func rejects(_ operation: () throws -> Void) {
        do { try operation(); preconditionFailure("Expected rejection") } catch { }
    }
    @MainActor static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
        precondition(condition(), "Timed out")
    }
    @MainActor static func main() async throws {
        let addresses = [
            "192.168.1.20": "http://192.168.1.20:50001/desc/device.xml",
            " ds420j.local ": "http://ds420j.local:50001/desc/device.xml",
            "nas:12345": "http://nas:12345/desc/device.xml",
            "http://nas/": "http://nas:50001/desc/device.xml",
            "[fd00::1]": "http://[fd00::1]:50001/desc/device.xml",
            "http://nas:8080/custom.xml?id=1": "http://nas:8080/custom.xml?id=1",
            "https://nas/custom.xml": "https://nas/custom.xml"
        ]
        for (input, expected) in addresses {
            precondition(DLNAClient.descriptionURL(for: input)?.absoluteString == expected, input)
        }
        for invalid in ["", " ", "http://", "ftp://nas/x", "file:///tmp/x", "user:password@nas", "nas:0", "nas:65536", "nas:abc", "some host", "nas/#fragment", "nas?query=x"] {
            precondition(DLNAClient.descriptionURL(for: invalid) == nil, invalid)
        }
        print("PASS: Synology IP/hostname input, custom ports, IPv6, full URLs, invalid addresses")

        let server = try DLNAClient.parseServer(Data(description.utf8), descriptionURL: base)
        precondition(server.name == "NAS & Video" && server.id == "uuid:nas")
        precondition(server.controlURL.absoluteString == "http://192.0.2.1:8200/base/ContentDirectory")
        let withoutBase = description.replacingOccurrences(of: "<URLBase>http://192.0.2.1:8200/base/</URLBase>", with: "")
        let relative = try DLNAClient.parseServer(Data(withoutBase.utf8), descriptionURL: base)
        precondition(relative.controlURL.absoluteString == "http://192.0.2.1:8200/ContentDirectory")
        rejects { _ = try DLNAClient.parseServer(Data("<root/>".utf8), descriptionURL: base) }
        rejects { _ = try DLNAXML.parse(Data("<root>".utf8)) }
        precondition(DLNADiscovery.location(in: "HTTP/1.1 200 OK\r\nlOcAtIoN: http://192.0.2.1:8200/description.xml\r\n\r\n") == base)
        precondition(DLNADiscovery.location(in: "HTTP/1.1 500 Error\r\nLOCATION: \(base)\r\n") == nil)
        precondition(DLNADiscovery.location(in: "HTTP/1.1 200 OK\r\nLOCATION: file:///etc/passwd\r\n") == nil)
        precondition(DLNAClient.httpURL("http://user:password@host/x") == nil)
        print("PASS: device description, URLBase, relative URLs, SSDP headers, invalid responses")

        let folderTitles = ["アニメ 2025秋", "アニメ 2025夏", "アニメ 2025冬", "アニメ 2025春",
                            "アニメ 2024秋", "アニメ 2026年冬", "別作品 2025秋", "別作品 2025冬",
                            "資料10", "資料2", "春の作品", "2025秋", "2025冬", "2025春", "2025夏"]
        let remoteFolders = folderTitles.enumerated().map {
            DLNAEntry(id: "opaque-\($0.offset)", title: $0.element, isContainer: true, resourceURL: nil, size: nil)
        }
        let sortedFolders = MediaScanner.sortFolders(remoteFolders, name: { $0.title })
        precondition(sortedFolders.filter { $0.title.hasPrefix("アニメ") }.map(\.title) ==
                     ["アニメ 2024秋", "アニメ 2025冬", "アニメ 2025春", "アニメ 2025夏", "アニメ 2025秋", "アニメ 2026年冬"])
        precondition(sortedFolders.filter { $0.title.hasPrefix("2025") }.map(\.title) ==
                     ["2025冬", "2025春", "2025夏", "2025秋"])
        let localFolders = folderTitles.map { URL(fileURLWithPath: "/test/" + $0, isDirectory: true) }
        precondition(sortedFolders.map(\.title) == MediaScanner.sortFolders(localFolders).map(\.lastPathComponent))
        precondition(Set(sortedFolders.map(\.id)) == Set(remoteFolders.map(\.id)), "Keep DLNA object IDs intact")
        print("PASS: DLNA seasonal folders match USB order, ordinary names and object IDs preserved")

        let content = "<container id=\"folder\"><dc:title>動画</dc:title></container>"
            + item("ed", "作品 ED.m4v") + item("op", "作品 OP.mp4")
            + item("ed2", "作品 ED2") + item("op2", "作品 OP2")
            + item("unsupported", "movie.mkv", "<res protocolInfo=\"http-get:*:video/x-matroska:*\">/movie.mkv</res>")
            + item("alternate", "Video.M4V", "<res protocolInfo=\"rtsp-rtp-udp:*:video/mp4:*\">rtsp://nas/video</res><res protocolInfo=\"http-get:*:application/octet-stream:*\" size=\"-1\">/opaque</res>")
        let entries = try DLNAClient.parseEntries(Data(didl(content).utf8), baseURL: base)
        precondition(entries.count == 7 && entries[0].isContainer)
        precondition(entries[1].resourceURL?.absoluteString == "http://192.0.2.1:8200/stream?id=1&token=x")
        precondition(entries[1].size == 1234 && entries[5].resourceURL == nil)
        precondition(entries[6].resourceURL?.path == "/opaque" && entries[6].size == nil)
        let ordered = PlaylistSorter.sort(Array(entries[1...4]), name: { $0.title }, namesAreTitles: true, locale: Locale(identifier: "ja_JP"))
        precondition(ordered.map(\.id) == ["op", "ed", "op2", "ed2"])
        let dottedTitles = ["SSSS.GRIDMAN ED", "SSSS.GRIDMAN OP", "作品 OP.mp4", "作品 ED.m4v"]
        let sortedTitles = PlaylistSorter.sort(dottedTitles, name: { $0 }, namesAreTitles: true)
        precondition(sortedTitles.firstIndex(of: "SSSS.GRIDMAN OP")! < sortedTitles.firstIndex(of: "SSSS.GRIDMAN ED")!)
        precondition(PlaylistSorter.parse("作品 OP.2 ED", isTitle: true)?.category == 1)
        let body = DLNAClient.browseBody(serviceType: server.serviceType, objectID: "A&B<1>\"'", start: 200)
        let parsed = try DLNAXML.parse(Data(body.utf8))
        precondition(parsed.descendants("ObjectID").first?.text == "A&B<1>\"'")
        precondition(parsed.descendants("StartingIndex").first?.text == "200")
        print("PASS: DIDL namespaces, entities, opaque URLs, resource selection, title sorting, SOAP escaping")

        let address = URL(string: CommandLine.arguments[1])!
        let client = DLNAClient()
        let messages: [(URLError.Code, String)] = [
            (.cannotConnectToHost, "指定したポートに接続できません"),
            (.timedOut, "NASからの応答がありません"),
            (.cannotFindHost, "NASのアドレスを確認してください"),
            (.notConnectedToInternet, "NASへのネットワーク接続を利用できません"),
            (.secureConnectionFailed, "HTTPS接続を確立できません")
        ]
        for (code, expected) in messages {
            let issue = DLNAConnectionIssue.make(error: URLError(code), url: base)
            precondition(issue.title == expected)
            precondition(issue.details.contains(base.absoluteString) && issue.details.contains(String(code.rawValue)))
        }
        let managementURL = DLNAClient.descriptionURL(for: "nas:5000")!
        let managementIssue = DLNAConnectionIssue.make(error: URLError(.cannotConnectToHost), url: managementURL)
        precondition(managementIssue.guidance.contains("DSM管理画面") && managementIssue.guidance.contains("50001"))
        precondition(DLNAClient.managementPortHint(for: DLNAClient.descriptionURL(for: "nas:50001")!) == nil)
        for (path, expected) in [("management", "DLNAサーバーの応答ではありません"),
                                 ("missing", "DLNAの接続先が見つかりません"),
                                 ("denied", "NASからアクセスを拒否されました"),
                                 ("unavailable", "NASがエラーを返しました（HTTP 503）")] {
            let target = address.appendingPathComponent(path)
            do {
                _ = try await client.server(at: target)
                preconditionFailure("Expected failure for \(path)")
            } catch {
                let issue = DLNAConnectionIssue.make(error: error, url: target)
                precondition(issue.title == expected, issue.title)
                precondition(issue.details.contains(target.absoluteString))
            }
        }
        print("PASS: actionable connection errors for ports, timeout, DNS, network, TLS, HTML, HTTP 403/404/503")

        let directURL = DLNAClient.descriptionURL(for: "\(address.host!):\(address.port!)")!
        let local = try await client.server(at: directURL)
        precondition(local.descriptionURL.path == "/desc/device.xml")
        let listing = try await client.browse(local, objectID: "0")
        precondition(listing.map(\.id) == ["unsupported", "op", "ed"], "Pagination must count unsupported items")
        let empty = try await client.browse(local, objectID: "empty")
        precondition(empty.isEmpty)
        for id in ["fault", "repeat", "changed", "truncated", "malformed", "http-error"] {
            do { _ = try await client.browse(local, objectID: id); preconditionFailure("Expected error: \(id)") }
            catch { precondition(!error.localizedDescription.isEmpty) }
        }
        let slow = Task { try await client.browse(local, objectID: "slow") }
        try await Task.sleep(for: .milliseconds(100))
        slow.cancel()
        do { _ = try await slow.value; preconditionFailure("Cancellation must propagate") } catch { }
        print("PASS: HTTP device loading, paginated SOAP, empty folders, faults, repeated pages, update detection, cancellation")

        // Exercise the real AVPlayer against HTTP, with title/size from DIDL-Lite.
        let files = listing.compactMap(\.resourceURL)
        let controller = PlaybackController()
        controller.setPlaylist(files, displayNames: [files[0]: "作品 OP.mp4", files[1]: "作品 ED.m4v"], sizes: [files[0]: 1234])
        controller.select(files[0], autoplay: false)
        try await waitUntil { !controller.isLoading }
        precondition(controller.player.currentItem?.status == .readyToPlay, controller.error ?? "HTTP media failed")
        precondition(controller.currentName == "作品 OP.mp4" && controller.mediaInfo.name == "作品 OP.mp4")
        precondition(controller.mediaInfo.size == ByteCountFormatter.string(fromByteCount: 1234, countStyle: .file))
        controller.resume()
        try await waitUntil { controller.player.currentTime().seconds > 0.1 }
        controller.pause()
        controller.move(1)
        try await waitUntil { !controller.isLoading }
        precondition(controller.currentName == "作品 ED.m4v" && !controller.state.wantsToPlay)
        controller.move(-1)
        try await waitUntil { !controller.isLoading }
        controller.seek(by: -10)
        controller.resume()
        try await waitUntil { controller.state.ended }
        precondition(controller.state.currentURL == files[1])
        controller.setPlaylist([files[0]])
        controller.select(files[0], autoplay: false)
        try await waitUntil { !controller.isLoading }
        precondition(controller.currentName == "stream", "Metadata must reset on playlist replacement")
        let oldItem = controller.player.currentItem!
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: oldItem,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)])
        try await waitUntil { controller.error != nil }
        precondition(!controller.needsFolderSelection, "Network access errors must not request USB permission")
        controller.setPlaylist([])
        print("PASS: HTTP playback, title and size, previous/next, seek, continuous playback and network access failure")
        print("DLNA tests passed")
    }
}
