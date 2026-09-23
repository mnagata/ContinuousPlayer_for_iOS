import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

nonisolated struct DLNAServer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let descriptionURL: URL
    let controlURL: URL
    let serviceType: String
}

nonisolated struct DLNAEntry: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let isContainer: Bool
    let resourceURL: URL?
    let size: Int64?
}

nonisolated enum DLNAError: LocalizedError {
    case message(String)
    case httpStatus(Int)
    case notMediaServer
    var errorDescription: String? {
        switch self {
        case .message(let message): message
        case .httpStatus(let status): "NASの応答エラー（HTTP \(status)）。"
        case .notMediaServer: "接続先からDLNAメディアサーバーの情報を取得できませんでした。"
        }
    }
}

/// User-facing connection guidance. Transport failures are not proof of a specific
/// NAS setting or permission denial, so offer checks without claiming a cause.
nonisolated struct DLNAConnectionIssue {
    let title: String
    let guidance: String
    let details: String

    static func make(error: Error, url: URL) -> DLNAConnectionIssue {
        let title: String
        var guidance: String
        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        if let failure = error as? DLNAError {
            switch failure {
            case .httpStatus(401), .httpStatus(403):
                title = "NASからアクセスを拒否されました"
                guidance = "メディアサーバーのDMAデバイス一覧で、この端末のアクセスが許可されているか確認してください。"
            case .httpStatus(404):
                title = "DLNAの接続先が見つかりません"
                guidance = "指定したポートまたはURLのパスが違う可能性があります。Synologyでは、まずポート番号を付けずにNASのIPアドレスだけで接続してください。"
            case .httpStatus(let status):
                title = "NASがエラーを返しました（HTTP \(status)）"
                guidance = "メディアサーバーの起動状態を確認して、もう一度接続してください。"
            case .notMediaServer:
                title = "DLNAサーバーの応答ではありません"
                guidance = "Web管理画面など、別のサービスへ接続している可能性があります。SynologyではIPアドレスだけで接続するか、DLNA用のポートを指定してください。"
            case .message(let message):
                title = "サーバー情報を読み取れません"
                guidance = message
            }
        } else if (error as NSError).domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: (error as NSError).code) {
            case .cannotConnectToHost:
                title = "指定したポートに接続できません"
                guidance = "NASのポート \(port) に接続できませんでした。ポート番号、メディアサーバーの起動状態、NASのファイアウォールを確認してください。"
            case .timedOut:
                title = "NASからの応答がありません"
                guidance = "接続がタイムアウトしました。NASのアドレス、同じWi-Fiへの接続、メディアサーバーの起動状態を確認してください。"
            case .cannotFindHost, .dnsLookupFailed:
                title = "NASのアドレスを確認してください"
                guidance = "ホスト名を見つけられませんでした。名前の入力を確認するか、NASのIPアドレスで接続してください。"
            case .notConnectedToInternet, .dataNotAllowed:
                title = "NASへのネットワーク接続を利用できません"
                guidance = "NASと同じWi-Fiに接続してください。設定アプリのContinuousPlayerで「ローカルネットワーク」が許可されているかも確認してください。"
            case .networkConnectionLost:
                title = "NASとの接続が切れました"
                guidance = "Wi-FiとNASの接続を確認し、もう一度接続してください。"
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
                 .clientCertificateRequired:
                title = "HTTPS接続を確立できません"
                guidance = "接続方式または証明書を確認してください。Synologyの標準メディアサーバーはHTTPを使うため、まずIPアドレスだけで接続してください。"
            case .appTransportSecurityRequiresSecureConnection:
                title = "このHTTP接続は許可されていません"
                guidance = "LAN内のNASのIPアドレスで接続してください。一般のドメイン名を使うHTTP接続は、アプリの通信設定で制限される場合があります。"
            default:
                title = "NASに接続できません"
                guidance = "NASのアドレス、同じWi-Fiへの接続、ローカルネットワークの許可を確認して、再接続してください。"
            }
        } else {
            title = "NASに接続できません"
            guidance = "アドレスとネットワークを確認して、もう一度接続してください。"
        }
        if let hint = DLNAClient.managementPortHint(for: url) { guidance += "\n" + hint }
        let nsError = error as NSError
        // Do not include query tokens in copied diagnostics.
        var target = URLComponents(url: url, resolvingAgainstBaseURL: false)
        target?.query = nil
        target?.fragment = nil
        return DLNAConnectionIssue(title: title, guidance: guidance,
            details: "接続先: \(target?.url?.absoluteString ?? url.host ?? "不明")\nエラー: \(nsError.domain) (\(nsError.code))\n\(error.localizedDescription)")
    }
}

/// A bounded XML tree shared by device descriptions, SOAP and DIDL-Lite.
/// Namespace prefixes vary between servers; UPnP element local names do not.
nonisolated final class DLNAXML: NSObject, XMLParserDelegate {
    final class Node {
        let name: String
        let attributes: [String: String]
        var text = ""
        var children: [Node] = []
        init(_ name: String, _ attributes: [String: String] = [:]) {
            self.name = name
            self.attributes = attributes
        }
        func child(_ name: String) -> Node? { children.first { $0.name == name } }
        func value(_ name: String) -> String { child(name)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        func descendants(_ name: String) -> [Node] {
            children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
        }
    }
    private let root = Node("document")
    private var stack: [Node] = []
    private var count = 0

    static func parse(_ data: Data) throws -> Node {
        guard data.count <= 8 * 1024 * 1024 else { throw DLNAError.message("サーバーの応答が大きすぎます。") }
        let delegate = DLNAXML()
        delegate.stack = [delegate.root]
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw DLNAError.message("サーバーからのXMLを読み取れません。") }
        return delegate.root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        count += 1
        guard stack.count < 64, count <= 100_000 else { parser.abortParsing(); return }
        let node = Node(elementName, attributes)
        stack.last?.children.append(node)
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        stack.removeLast()
    }
}

nonisolated struct DLNAClient: Sendable {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    static func httpURL(_ string: String, relativeTo base: URL? = nil) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// Synology Media Server exposes this HTTP description endpoint. Other servers
    /// can still be connected using their complete device-description URL.
    static func descriptionURL(for address: String) -> URL? {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !input.contains(where: { $0.isWhitespace }) else { return nil }
        let text = input.contains("://") ? input : "http://" + input
        guard let url = httpURL(text), var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        if components.path.isEmpty || components.path == "/" {
            guard components.query == nil else { return nil }
            components.port = components.port ?? 50001
            components.path = "/desc/device.xml"
        }
        return components.url
    }

    static func managementPortHint(for url: URL) -> String? {
        guard let port = url.port, [5000, 5001].contains(port) else { return nil }
        return "ポート \(port) は通常SynologyのDSM管理画面用です。DLNAの標準ポートは50001です。"
    }

    func server(at url: URL) async throws -> DLNAServer {
        let (data, response) = try await request(URLRequest(url: url))
        do {
            return try Self.parseServer(data, descriptionURL: response.url ?? url)
        } catch {
            throw DLNAError.notMediaServer
        }
    }

    static func parseServer(_ data: Data, descriptionURL: URL) throws -> DLNAServer {
        let xml = try DLNAXML.parse(data)
        let baseText = xml.descendants("URLBase").first?.text ?? ""
        let base = baseText.isEmpty ? descriptionURL : httpURL(baseText, relativeTo: descriptionURL) ?? descriptionURL
        for device in xml.descendants("device") where device.value("deviceType").hasPrefix("urn:schemas-upnp-org:device:MediaServer:") {
            guard let service = device.child("serviceList")?.children.first(where: {
                $0.name == "service" && $0.value("serviceType").hasPrefix("urn:schemas-upnp-org:service:ContentDirectory:")
            }), !service.value("controlURL").isEmpty,
                  let control = httpURL(service.value("controlURL"), relativeTo: base) else { continue }
            let name = device.value("friendlyName")
            let udn = device.value("UDN")
            return DLNAServer(id: udn.isEmpty ? descriptionURL.absoluteString : udn,
                              name: name.isEmpty ? descriptionURL.host ?? "DLNAサーバー" : name,
                              descriptionURL: descriptionURL, controlURL: control,
                              serviceType: service.value("serviceType"))
        }
        throw DLNAError.message("DLNAメディアサーバーの情報が見つかりません。デバイス記述URLを確認してください。")
    }

    func browse(_ server: DLNAServer, objectID: String) async throws -> [DLNAEntry] {
        var entries: [DLNAEntry] = []
        var seen = Set<String>()
        var start = 0
        var updateID: String?
        // Use NumberReturned (including unsupported entries), never the filtered count.
        for _ in 0..<500 {
            try Task.checkCancellation()
            var request = URLRequest(url: server.controlURL)
            request.httpMethod = "POST"
            request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
            request.setValue("\"\(server.serviceType)#Browse\"", forHTTPHeaderField: "SOAPAction")
            request.httpBody = Data(Self.browseBody(serviceType: server.serviceType, objectID: objectID, start: start).utf8)
            let (data, _) = try await self.request(request)
            let page = try Self.parsePage(data, baseURL: server.descriptionURL)
            if let updateID, updateID != page.updateID {
                throw DLNAError.message("NASの一覧が更新されました。もう一度読み込んでください。")
            }
            updateID = page.updateID
            let fresh = page.entries.filter { seen.insert($0.id).inserted }
            entries.append(contentsOf: fresh)
            guard page.returned > 0 else {
                guard start >= page.total else { throw DLNAError.message("NASの一覧を最後まで取得できません。再読み込みしてください。") }
                return entries
            }
            guard !fresh.isEmpty else { throw DLNAError.message("NASが同じ一覧を繰り返し返しました。再読み込みしてください。") }
            start += page.returned
            if start >= page.total { return entries }
        }
        throw DLNAError.message("一覧の件数が多すぎます。NAS側でフォルダーを分けてください。")
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func browseBody(serviceType: String, objectID: String, start: Int) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body><u:Browse xmlns:u="\(escape(serviceType))"><ObjectID>\(escape(objectID))</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>\(start)</StartingIndex><RequestedCount>200</RequestedCount><SortCriteria></SortCriteria></u:Browse></s:Body>
        </s:Envelope>
        """
    }

    struct Page {
        let entries: [DLNAEntry]
        let returned: Int
        let total: Int
        let updateID: String
    }

    static func parsePage(_ data: Data, baseURL: URL) throws -> Page {
        let xml = try DLNAXML.parse(data)
        if let fault = xml.descendants("Fault").first {
            let detail = fault.descendants("errorDescription").first?.text ?? fault.value("faultstring")
            throw DLNAError.message("NASが一覧取得を拒否しました: \(detail)")
        }
        guard let response = xml.descendants("BrowseResponse").first,
              let returned = Int(response.value("NumberReturned")), (0...100_000).contains(returned),
              let total = Int(response.value("TotalMatches")), total >= 0,
              let result = response.child("Result") else { throw DLNAError.message("NASの一覧応答が不正です。") }
        let entries: [DLNAEntry]
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && returned == 0 {
            entries = []
        } else {
            entries = try parseEntries(Data(result.text.utf8), baseURL: baseURL)
        }
        guard entries.count == returned else { throw DLNAError.message("NASの一覧件数が応答と一致しません。") }
        return Page(entries: entries, returned: returned, total: total, updateID: response.value("UpdateID"))
    }

    static func parseEntries(_ data: Data, baseURL: URL) throws -> [DLNAEntry] {
        let xml = try DLNAXML.parse(data)
        guard let root = xml.child("DIDL-Lite") else { throw DLNAError.message("メディア一覧を読み取れません。") }
        return try root.children.filter { ["container", "item"].contains($0.name) }.map { node in
            guard let id = node.attributes["id"], !id.isEmpty else { throw DLNAError.message("メディアの識別情報がありません。") }
            let title = node.value("title")
            let resource = node.children.first { res in
                guard res.name == "res", let url = httpURL(res.text, relativeTo: baseURL) else { return false }
                let protocolInfo = (res.attributes["protocolInfo"] ?? "").split(separator: ":", omittingEmptySubsequences: false)
                guard protocolInfo.count >= 4, protocolInfo[0].lowercased() == "http-get" else { return false }
                let mime = protocolInfo[2].lowercased().split(separator: ";").first.map(String.init) ?? ""
                // A URL may be an opaque /resource?id=..., with no file extension.
                return ["video/mp4", "video/x-m4v", "video/m4v"].contains(mime)
                    || (["application/octet-stream", "*"].contains(mime)
                        && (["mp4", "m4v"].contains(url.pathExtension.lowercased())
                            || ["mp4", "m4v"].contains((title as NSString).pathExtension.lowercased())))
            }
            return DLNAEntry(id: id, title: title.isEmpty ? "名称未設定" : title,
                             isContainer: node.name == "container",
                             resourceURL: resource.flatMap { httpURL($0.text, relativeTo: baseURL) },
                             size: resource.flatMap { $0.attributes["size"].flatMap(Int64.init) }.flatMap { $0 >= 0 ? $0 : nil })
        }
    }

    private func request(_ original: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = original
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        // Stream with a hard size bound so malformed servers cannot exhaust memory.
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DLNAError.message("NASからHTTP応答がありません。") }
        guard response.expectedContentLength <= 8 * 1024 * 1024 else { throw DLNAError.message("NASの応答が大きすぎます。") }
        var data = Data()
        for try await byte in bytes {
            if data.count % 4096 == 0 { try Task.checkCancellation() }
            guard data.count < 8 * 1024 * 1024 else { throw DLNAError.message("NASの応答が大きすぎます。") }
            data.append(byte)
        }
        if !(200..<300).contains(http.statusCode) {
            if let xml = try? DLNAXML.parse(data), let detail = xml.descendants("errorDescription").first?.text {
                throw DLNAError.message("NASの応答エラー: \(detail)")
            }
            throw DLNAError.httpStatus(http.statusCode)
        }
        return (data, http)
    }
}
