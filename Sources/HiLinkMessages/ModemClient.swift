import Foundation

enum ModemError: Error {
    case badResponse
    /// Error code returned by the stick, e.g. 125002 (bad session token).
    case api(code: Int)
    case sendFailed
}

/// A message as stored on the stick.
struct ModemSMS: Sendable, Hashable {
    /// The stick's own index for the message; nil for sample data.
    var index: Int?
    var phone: String
    var content: String
    var date: Date
    var isOutgoing: Bool
    var isUnread: Bool
    var hasFailed: Bool
}

struct ModemInfo: Sendable {
    var carrier: String
    var network: String
    var signalBars: Int
    var phoneNumber: String?
    /// The SIM's serial number (ICCID), used to remember settings per SIM.
    var simID: String?
    var simReady: Bool
    /// False when the stick is registered on no network (no signal).
    var hasService: Bool
    /// Home country of the SIM, falling back to the country of the current network.
    var simCountry: Country?
}

struct SMSCounts: Sendable, Equatable {
    var unread: Int
    var inbox: Int
    var outbox: Int
    var drafts: Int
    /// How many messages the stick can hold in total (500 on the E3372h).
    var capacity: Int

    /// Messages currently taking up space on the stick.
    var stored: Int { inbox + outbox + drafts }
}

/// Client for the HiLink web API that Huawei LTE sticks serve on their own network interface.
///
/// Every request first fetches a fresh session cookie and verification token from
/// `/api/webserver/SesTokInfo`; this firmware needs no login.
struct ModemClient: Sendable {
    let baseURL: URL

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    // MARK: Discovery

    /// Finds the stick by probing the gateway address of every local 192.168.x network.
    static func discover() async -> ModemClient? {
        await withTaskGroup(of: ModemClient?.self) { group in
            for host in candidateHosts() {
                group.addTask {
                    guard let url = URL(string: "http://\(host)") else { return nil }
                    let client = ModemClient(baseURL: url)
                    return await client.isHiLink() ? client : nil
                }
            }
            for await found in group {
                if let found {
                    group.cancelAll()
                    return found
                }
            }
            return nil
        }
    }

    /// Whether this Mac still has a network interface on the stick's subnet. It disappears the
    /// moment the stick is unplugged, long before a request to it would time out.
    var isReachableLocally: Bool {
        guard let host = baseURL.host else { return false }
        return Self.candidateHosts().contains(host)
    }

    /// The ".1" address of every 192.168.x network this Mac is on. The stick is the gateway of the
    /// network interface it creates, whatever subnet its firmware uses (192.168.8.x, 192.168.3.x, …).
    private static func candidateHosts() -> [String] {
        var hosts: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return hosts }
        defer { freeifaddrs(list) }

        var cursor = list
        while let entry = cursor {
            cursor = entry.pointee.ifa_next
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let raw = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let bytes = withUnsafeBytes(of: raw) { Array($0) }
            guard bytes.count == 4, bytes[0] == 192, bytes[1] == 168 else { continue }
            let host = "192.168.\(bytes[2]).1"
            if !hosts.contains(host) { hosts.append(host) }
        }
        return hosts
    }

    private func isHiLink() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "api/device/basic_information"))
        request.timeoutInterval = 2
        guard let (data, _) = try? await Self.session.data(for: request),
              let root = XMLNode.parse(data) else { return false }
        return root.name == "response" && root["classify"]?.text.lowercased() == "hilink"
    }

    // MARK: Status

    func info() async throws -> ModemInfo {
        // One at a time: each request takes a fresh session token, and the stick
        // rejects tokens issued to overlapping requests.
        let status = try await get("api/monitoring/status")
        let plmn = try await get("api/net/current-plmn")
        let device = try await get("api/device/information")

        let msisdn = device["Msisdn"]?.text ?? ""
        return ModemInfo(
            carrier: plmn["FullName"]?.text ?? plmn["ShortName"]?.text ?? "",
            network: Self.networkName(typeEx: status["CurrentNetworkTypeEx"]?.int, type: status["CurrentNetworkType"]?.int),
            signalBars: min(max(status["SignalIcon"]?.int ?? 0, 0), 5),
            phoneNumber: msisdn.isEmpty ? nil : msisdn,
            simID: device["Iccid"]?.text.isEmpty == false ? device["Iccid"]?.text : nil,
            simReady: status["SimStatus"]?.int == 1,
            hasService: status["ServiceStatus"]?.int == 2 && status["CurrentNetworkTypeEx"]?.int != 0,
            simCountry: Country.forMobileCountryCode(device["Imsi"]?.text ?? "")
                ?? Country.forMobileCountryCode(plmn["Numeric"]?.text ?? "")
        )
    }

    private static func networkName(typeEx: Int?, type: Int?) -> String {
        switch typeEx ?? -1 {
        case 0: return "No Service"
        case 1, 2, 3: return "2G"
        case 41...46, 61...65: return "3G"
        case 101: return "LTE"
        case 1011: return "LTE+"
        case 111: return "5G"
        default: break
        }
        switch type ?? -1 {
        case 0: return "No Service"
        case 1...3: return "2G"
        case 4...18: return "3G"
        case 19: return "LTE"
        default: return ""
        }
    }

    func counts() async throws -> SMSCounts {
        let node = try await get("api/sms/sms-count")
        return SMSCounts(
            unread: node["LocalUnread"]?.int ?? 0,
            inbox: node["LocalInbox"]?.int ?? 0,
            outbox: node["LocalOutbox"]?.int ?? 0,
            drafts: node["LocalDraft"]?.int ?? 0,
            capacity: node["LocalMax"]?.int ?? 0
        )
    }

    // MARK: Messages

    /// All received and sent messages stored on the stick.
    func messages() async throws -> [ModemSMS] {
        let inbox = try await list(box: 1)
        let outbox = try await list(box: 2)
        return inbox + outbox
    }

    private func list(box: Int) async throws -> [ModemSMS] {
        let pageSize = 20
        var result: [ModemSMS] = []
        for page in 1...50 {
            let body = "<PageIndex>\(page)</PageIndex><ReadCount>\(pageSize)</ReadCount><BoxType>\(box)</BoxType>"
                + "<SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>0</UnreadPreferred>"
            let node = try await post("api/sms/sms-list", body: body)
            let items = node["Messages"]?.children ?? []
            for item in items {
                guard let date = Self.dateFormatter.date(from: item["Date"]?.text ?? "") else { continue }
                let stat = item["Smstat"]?.int ?? 1
                result.append(ModemSMS(
                    index: item["Index"]?.int,
                    phone: item["Phone"]?.text ?? "",
                    content: item["Content"]?.text ?? "",
                    date: date,
                    isOutgoing: box == 2,
                    isUnread: box == 1 && stat == 0,
                    hasFailed: box == 2 && stat == 4
                ))
            }
            if items.count < pageSize { break }
        }
        return result
    }

    /// Sends a text message and waits until the stick reports it sent or failed.
    func send(_ text: String, to phone: String) async throws {
        let body = "<Index>-1</Index><Phones><Phone>\(Self.escape(phone))</Phone></Phones><Sca></Sca>"
            + "<Content>\(Self.escape(text))</Content><Length>\(text.count)</Length><Reserved>1</Reserved>"
            + "<Date>\(Self.dateFormatter.string(from: .now))</Date>"
        let response = try await post("api/sms/send-sms", body: body)
        guard response.text.uppercased() == "OK" else { throw ModemError.sendFailed }

        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(500))
            let status = try await get("api/sms/send-status")
            if !(status["FailPhone"]?.text ?? "").isEmpty { throw ModemError.sendFailed }
            if !(status["SucPhone"]?.text ?? "").isEmpty { return }
        }
        // No verdict in time; the caller reloads the outbox, which shows the real outcome.
    }

    func markRead(index: Int) async throws {
        _ = try await post("api/sms/set-read", body: "<Index>\(index)</Index>")
    }

    func delete(index: Int) async throws {
        _ = try await post("api/sms/delete-sms", body: "<Index>\(index)</Index>")
    }

    // MARK: Transport

    private func get(_ path: String) async throws -> XMLNode {
        try await perform(path, body: nil)
    }

    private func post(_ path: String, body: String) async throws -> XMLNode {
        try await perform(path, body: "<?xml version=\"1.0\" encoding=\"UTF-8\"?><request>\(body)</request>")
    }

    /// The stick invalidates a session token as soon as another one is issued, so a token fetch and
    /// the request that uses it must never interleave with another pair. Polling, sending, marking
    /// read and deleting all start from different tasks; this queue runs their requests one by one.
    private actor RequestQueue {
        private var last: Task<Void, Never>?

        func run(_ operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
            let previous = last
            let task = Task {
                await previous?.value
                return try await operation()
            }
            last = Task { _ = try? await task.value }
            return try await task.value
        }
    }

    private static let queue = RequestQueue()

    private func perform(_ path: String, body: String?) async throws -> XMLNode {
        let base = baseURL
        for attempt in 0..<2 {
            let data = try await Self.queue.run { try await Self.exchange(base: base, path: path, body: body) }
            guard let root = XMLNode.parse(data) else { throw ModemError.badResponse }
            guard root.name == "error" else { return root }
            let code = root["code"]?.int ?? 0
            // 125001–125003 are session/token errors (e.g. the stick's own web page was open); try once more.
            if attempt == 0, (125001...125003).contains(code) { continue }
            throw ModemError.api(code: code)
        }
        throw ModemError.badResponse
    }

    /// One token fetch followed by the request that uses it.
    private static func exchange(base: URL, path: String, body: String?) async throws -> Data {
        let (tokenData, _) = try await session.data(from: base.appending(path: "api/webserver/SesTokInfo"))
        guard let tokens = XMLNode.parse(tokenData),
              let sessionInfo = tokens["SesInfo"]?.text, let token = tokens["TokInfo"]?.text else {
            throw ModemError.badResponse
        }

        var request = URLRequest(url: base.appending(path: path))
        let cookie = sessionInfo.hasPrefix("SessionID=") ? sessionInfo : "SessionID=\(sessionInfo)"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(token, forHTTPHeaderField: "__RequestVerificationToken")
        if let body {
            request.httpMethod = "POST"
            request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }

        return try await session.data(for: request).0
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// The stick reports and expects timestamps in local time, without a zone.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

/// Minimal XML tree; the stick's responses are small, flat documents.
final class XMLNode {
    let name: String
    var text = ""
    var children: [XMLNode] = []

    init(name: String) { self.name = name }

    /// First child with the given name, ignoring case (the firmware is inconsistent about it).
    subscript(name: String) -> XMLNode? {
        children.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    var int: Int? { Int(text) }

    static func parse(_ data: Data) -> XMLNode? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        return parser.parse() ? builder.root : nil
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLNode?
        private var stack: [XMLNode] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLNode(name: elementName)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            if let node = stack.popLast() {
                node.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
