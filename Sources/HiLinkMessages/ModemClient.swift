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
    var deviceName: String
    var firmware: String
}

/// Mobile data settings of the stick.
struct MobileDataSettings: Sendable, Equatable {
    var isEnabled: Bool
    /// Nil if the stick does not report a roaming setting.
    var allowsRoaming: Bool?
}

/// Mobile data transferred through the stick this month, in bytes.
struct DataUsage: Sendable, Equatable {
    var monthDownload: Int64 = 0
    var monthUpload: Int64 = 0
}

/// Identity of the stick, for the Settings window.
struct DeviceDetails: Sendable, Equatable {
    var name = ""
    var firmware = ""
    var hardware = ""
    var webUI = ""
    var imei = ""
    var serialNumber = ""
    var uptimeSeconds: Int64?
    /// Whether the stick updates its firmware by itself; nil if it does not say.
    var updatesAutomatically: Bool?
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

/// The API's types, generated at build time from `openapi.yaml` by Swift OpenAPI Generator.
private typealias API = Components.Schemas

/// Client for the HiLink web API that Huawei LTE sticks serve on their own network interface.
/// The API is described in `openapi.yaml`; requests and responses use the types generated from it.
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
              let root = XMLNode.parse(data), root.name == "response",
              let basics = try? XMLCoding.decode(API.BasicInformation.self, from: root) else { return false }
        return basics.classify?.lowercased() == "hilink"
    }

    // MARK: Status

    func info() async throws -> ModemInfo {
        // One at a time: each request takes a fresh session token, and the stick
        // rejects tokens issued to overlapping requests.
        let status: API.MonitoringStatus = try await get("api/monitoring/status")
        let plmn: API.CurrentPlmn = try await get("api/net/current-plmn")
        let device: API.DeviceInformation = try await get("api/device/information")

        func nonEmpty(_ text: String?) -> String? { text?.isEmpty == false ? text : nil }
        return ModemInfo(
            carrier: nonEmpty(plmn.fullName) ?? plmn.shortName ?? "",
            network: Self.networkName(typeEx: status.currentNetworkTypeEx, type: status.currentNetworkType),
            signalBars: min(max(status.signalIcon ?? 0, 0), 5),
            phoneNumber: nonEmpty(device.msisdn),
            simID: nonEmpty(device.iccid),
            simReady: status.simStatus == 1,
            hasService: status.serviceStatus == 2 && status.currentNetworkTypeEx != 0,
            simCountry: Country.forMobileCountryCode(device.imsi ?? "")
                ?? Country.forMobileCountryCode(plmn.numeric ?? ""),
            deviceName: device.deviceName ?? "",
            firmware: device.softwareVersion ?? ""
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
        let counts: API.SmsCount = try await get("api/sms/sms-count")
        return SMSCounts(
            unread: counts.localUnread ?? 0,
            inbox: counts.localInbox ?? 0,
            outbox: counts.localOutbox ?? 0,
            drafts: counts.localDraft ?? 0,
            capacity: counts.localMax ?? 0
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
            let request = API.SmsListRequest(pageIndex: page, readCount: pageSize, boxType: box,
                                             sortType: 0, ascending: 0, unreadPreferred: 0)
            let response: API.SmsListResponse = try await post("api/sms/sms-list", request)
            let items = response.messages?.message ?? []
            for item in items {
                guard let date = Self.dateFormatter.date(from: item.date ?? "") else { continue }
                let state = item.smstat ?? 1
                result.append(ModemSMS(
                    index: item.index,
                    phone: item.phone ?? "",
                    content: item.content ?? "",
                    date: date,
                    isOutgoing: box == 2,
                    isUnread: box == 1 && state == 0,
                    hasFailed: box == 2 && state == 4
                ))
            }
            if items.count < pageSize { break }
        }
        return result
    }

    /// Sends a text message and waits until the stick reports it sent or failed.
    func send(_ text: String, to phone: String) async throws {
        let request = API.SendSmsRequest(index: -1, phones: .init(phone: [phone]), sca: "", content: text,
                                         length: text.count, reserved: 1,
                                         date: Self.dateFormatter.string(from: .now))
        let accepted: String = try await post("api/sms/send-sms", request)
        guard accepted.uppercased() == "OK" else { throw ModemError.sendFailed }

        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(500))
            let status: API.SendStatus = try await get("api/sms/send-status")
            if status.failPhone?.isEmpty == false { throw ModemError.sendFailed }
            if status.sucPhone?.isEmpty == false { return }
        }
        // No verdict in time; the caller reloads the outbox, which shows the real outcome.
    }

    func markRead(index: Int) async throws {
        let _: String = try await post("api/sms/set-read", API.SmsIndexRequest(index: index))
    }

    func delete(index: Int) async throws {
        let _: String = try await post("api/sms/delete-sms", API.SmsIndexRequest(index: index))
    }

    // MARK: Mobile data, usage and device
    //
    // These calls are marked `x-verified: false` in openapi.yaml: they follow how HiLink sticks
    // generally behave and still need checking against a real device.

    func mobileData() async throws -> MobileDataSettings {
        let dataSwitch: API.MobileDataSwitch = try await get("api/dialup/mobile-dataswitch")
        // Roaming lives in a separate document; not every firmware serves it.
        let connection: API.ConnectionSettings? = try? await get("api/dialup/connection")
        return MobileDataSettings(isEnabled: dataSwitch.dataswitch == 1,
                                  allowsRoaming: connection?.roamAutoConnectEnable.map { $0 == 1 })
    }

    func setMobileData(enabled: Bool) async throws {
        try await expectOK(post("api/dialup/mobile-dataswitch", API.MobileDataSwitch(dataswitch: enabled ? 1 : 0)))
    }

    /// Changes only the roaming flag: the other connection settings are read and sent back unchanged.
    func setRoaming(allowed: Bool) async throws {
        var connection: API.ConnectionSettings = try await get("api/dialup/connection")
        connection.roamAutoConnectEnable = allowed ? 1 : 0
        try await expectOK(post("api/dialup/connection", connection))
    }

    func dataUsage() async throws -> DataUsage {
        let month: API.MonthStatistics = try await get("api/monitoring/month_statistics")
        return DataUsage(monthDownload: month.currentMonthDownload ?? 0, monthUpload: month.currentMonthUpload ?? 0)
    }

    func deviceDetails() async throws -> DeviceDetails {
        let device: API.DeviceInformation = try await get("api/device/information")
        // Not every firmware has the update settings; leave the switch out if this one does not.
        let update: API.AutoUpdateConfig? = try? await get("api/online-update/autoupdate-config")
        return DeviceDetails(name: device.deviceName ?? "", firmware: device.softwareVersion ?? "",
                             hardware: device.hardwareVersion ?? "", webUI: device.webUIVersion ?? "",
                             imei: device.imei ?? "", serialNumber: device.serialNumber ?? "",
                             uptimeSeconds: device.uptime, updatesAutomatically: update?.autoUpdate.map { $0 == 1 })
    }

    /// Changes only the automatic-update flag: the other update settings are read and sent back unchanged.
    func setFirmwareAutoUpdate(enabled: Bool) async throws {
        var config: API.AutoUpdateConfig = try await get("api/online-update/autoupdate-config")
        config.autoUpdate = enabled ? 1 : 0
        try await expectOK(post("api/online-update/autoupdate-config", config))
    }

    /// Restarts the stick. It drops off the Mac for a while and is rediscovered afterwards.
    func restart() async throws {
        try await expectOK(post("api/device/control", API.DeviceControlRequest(control: 1)))
    }

    /// Restores the stick's factory settings. It restarts, and anything configured on it is lost.
    func factoryReset() async throws {
        try await expectOK(post("api/device/control", API.DeviceControlRequest(control: 2)))
    }

    private func expectOK(_ response: String) throws {
        guard response.uppercased() == "OK" else { throw ModemError.badResponse }
    }

    // MARK: Transport

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        try XMLCoding.decode(Response.self, from: try await perform(path, body: nil))
    }

    private func post<Request: Encodable, Response: Decodable>(_ path: String, _ request: Request) async throws -> Response {
        let body = try XMLCoding.encode(request, root: "request")
        return try XMLCoding.decode(Response.self, from: try await perform(path, body: body))
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
            let code = (try? XMLCoding.decode(API.ApiError.self, from: root))?.code ?? 0
            // 125001–125003 are session/token errors (e.g. the stick's own web page was open); try once more.
            if attempt == 0, (125001...125003).contains(code) { continue }
            throw ModemError.api(code: code)
        }
        throw ModemError.badResponse
    }

    /// One token fetch followed by the request that uses it.
    private static func exchange(base: URL, path: String, body: String?) async throws -> Data {
        let (tokenData, _) = try await session.data(from: base.appending(path: "api/webserver/SesTokInfo"))
        guard let tokenRoot = XMLNode.parse(tokenData),
              let tokens = try? XMLCoding.decode(API.SessionToken.self, from: tokenRoot) else {
            throw ModemError.badResponse
        }
        let (sessionInfo, token) = (tokens.sesInfo, tokens.tokInfo)

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
