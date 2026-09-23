import Foundation
import Darwin

nonisolated enum DLNADiscovery {
    static var isAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-dlna-direct-only") { return false }
        #endif
        #if os(iOS) && !targetEnvironment(simulator)
        // The approved build configuration enables discovery and its entitlement together.
        return (Bundle.main.object(forInfoDictionaryKey: "DLNAMulticastEnabled") as? String)?.uppercased() == "YES"
        #else
        return true
        #endif
    }

    /// Active SSDP discovery receives unicast replies on the same ephemeral port.
    /// No long-lived listener or background work is needed.
    static func locations() async throws -> [URL] {
        guard isAvailable else {
            throw DLNAError.message("このアプリではNASのアドレスを指定して接続してください。")
        }
        let worker = Task.detached(priority: .userInitiated) { try scan() }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func location(in response: String) -> URL? {
        let lines = response.components(separatedBy: .newlines)
        guard let first = lines.first, first.uppercased().hasPrefix("HTTP/1.1 200") else { return nil }
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "location" {
                return DLNAClient.httpURL(String(line[line.index(after: colon)...]))
            }
        }
        return nil
    }

    private static func scan() throws -> [URL] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw networkError() }
        defer { close(fd) }
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw networkError() }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw networkError() }
        var ttl: UInt8 = 2
        guard setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout.size(ofValue: ttl))) == 0 else { throw networkError() }
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &destination.sin_addr)
        let message = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaServer:1\r\n\r\n"
        let packet = Array(message.utf8)
        let start = ContinuousClock.now
        var transmissions = 0
        var found = Set<URL>()
        var buffer = [UInt8](repeating: 0, count: 65535)
        while start.duration(to: .now) < .seconds(5) {
            try Task.checkCancellation()
            if transmissions == 0 || (transmissions == 1 && start.duration(to: .now) >= .seconds(2)) {
                let sent = packet.withUnsafeBytes { bytes in
                    withUnsafePointer(to: &destination) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                guard sent == packet.count else { throw networkError() }
                transmissions += 1
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 200)
            if ready < 0 {
                if errno == EINTR { continue }
                throw networkError()
            }
            guard ready > 0 else { continue }
            if descriptor.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { throw networkError() }
            let count = recv(fd, &buffer, buffer.count, 0)
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw networkError()
            }
            if let url = location(in: String(decoding: buffer.prefix(count), as: UTF8.self)) {
                found.insert(url)
                if found.count >= 64 { break }
            }
        }
        return found.sorted { $0.absoluteString < $1.absoluteString }
    }

    private static func networkError() -> DLNAError {
        .message("DLNAサーバーを検索できません。Wi-Fi接続と、設定のローカルネットワーク許可を確認してください。（\(errno)）")
    }
}
