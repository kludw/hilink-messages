import Foundation
import Testing
@testable import HiLinkMessages

/// Decoding and encoding the stick's XML with the types generated from openapi.yaml.
/// The documents are real responses from an E3372h-320, with identifiers replaced.
struct XMLCodingTests {
    private typealias API = Components.Schemas

    private func decode<T: Decodable>(_ type: T.Type, _ xml: String) throws -> T {
        let root = try #require(XMLNode.parse(Data(xml.utf8)))
        return try XMLCoding.decode(type, from: root)
    }

    @Test func sessionToken() throws {
        let token = try decode(API.SessionToken.self, """
            <?xml version="1.0" encoding="UTF-8"?><response><SesInfo>abc123</SesInfo><TokInfo>tok456</TokInfo></response>
            """)
        #expect(token.sesInfo == "abc123")
        #expect(token.tokInfo == "tok456")
    }

    @Test func monitoringStatusTreatsEmptyElementsAsMissing() throws {
        let status = try decode(API.MonitoringStatus.self, """
            <?xml version="1.0" encoding="UTF-8"?>
            <response>
            <ConnectionStatus>902</ConnectionStatus>
            <SignalStrength></SignalStrength>
            <SignalIcon>4</SignalIcon>
            <CurrentNetworkType>19</CurrentNetworkType>
            <RoamingStatus>0</RoamingStatus>
            <ServiceStatus>2</ServiceStatus>
            <SimStatus>1</SimStatus>
            <CurrentNetworkTypeEx>101</CurrentNetworkTypeEx>
            <maxsignal>5</maxsignal>
            </response>
            """)
        #expect(status.signalIcon == 4)
        #expect(status.currentNetworkTypeEx == 101)
        #expect(status.serviceStatus == 2)
        #expect(status.simStatus == 1)
        #expect(status.maxsignal == 5)
    }

    @Test func deviceInformationWithEmptyNumber() throws {
        let device = try decode(API.DeviceInformation.self, """
            <response>
            <DeviceName>E3372h-320</DeviceName>
            <Imei>000000000000000</Imei>
            <Imsi>234100000000000</Imsi>
            <Iccid>8944000000000000000</Iccid>
            <Msisdn></Msisdn>
            <SoftwareVersion>10.0.3.1&#40;H192SP2C983&#41;</SoftwareVersion>
            </response>
            """)
        #expect(device.deviceName == "E3372h-320")
        #expect(device.msisdn == nil)
        #expect(device.imsi?.hasPrefix("234") == true)
        #expect(device.softwareVersion == "10.0.3.1(H192SP2C983)")
    }

    @Test func currentPlmn() throws {
        let plmn = try decode(API.CurrentPlmn.self, """
            <response><State>0</State><FullName>O2 - UK</FullName><ShortName>O2 - UK</ShortName><Numeric>23410</Numeric><Rat>7</Rat><Spn></Spn></response>
            """)
        #expect(plmn.fullName == "O2 - UK")
        #expect(plmn.numeric == "23410")
    }

    @Test func smsCount() throws {
        let counts = try decode(API.SmsCount.self, """
            <response>
            \t<LocalUnread>0</LocalUnread>
            \t<LocalInbox>3</LocalInbox>
            \t<LocalOutbox>2</LocalOutbox>
            \t<LocalDraft>0</LocalDraft>
            \t<LocalMax>500</LocalMax>
            \t<SimMax>50</SimMax>
            </response>
            """)
        #expect(counts.localInbox == 3)
        #expect(counts.localOutbox == 2)
        #expect(counts.localMax == 500)
    }

    @Test func smsListWithMessages() throws {
        let list = try decode(API.SmsListResponse.self, """
            <?xml version="1.0" encoding="utf-8"?>
            <response>
            \t<Count>2</Count>
            \t<Messages>
            \t\t<Message>
            \t\t\t<Smstat>3</Smstat>
            \t\t\t<Index>40001</Index>
            \t\t\t<Phone>+447700900123</Phone>
            \t\t\t<Content>Tom &amp; Jerry &lt;3</Content>
            \t\t\t<Date>2026-11-12 17:58:28</Date>
            \t\t\t<Sca></Sca>
            \t\t\t<SaveType>3</SaveType>
            \t\t\t<Priority>4</Priority>
            \t\t\t<SmsType>1</SmsType>
            \t\t</Message>
            \t\t<Message>
            \t\t\t<Smstat>0</Smstat>
            \t\t\t<Index>40000</Index>
            \t\t\t<Phone>MyBank</Phone>
            \t\t\t<Content>Your code is 284 913</Content>
            \t\t\t<Date>2026-11-12 01:01:54</Date>
            \t\t</Message>
            \t</Messages>
            </response>
            """)
        let messages = try #require(list.messages?.message)
        #expect(list.count == 2)
        #expect(messages.count == 2)
        #expect(messages[0].index == 40001)
        #expect(messages[0].content == "Tom & Jerry <3")
        #expect(messages[0].sca == nil)
        #expect(messages[1].smstat == 0)
        #expect(messages[1].phone == "MyBank")
    }

    @Test func emptySmsList() throws {
        let list = try decode(API.SmsListResponse.self, """
            <response>
            \t<Count>0</Count>
            \t<Messages>
            \t</Messages>
            </response>
            """)
        #expect(list.count == 0)
        #expect((list.messages?.message ?? []).isEmpty)
    }

    @Test func lowercaseElementNamesStillMatch() throws {
        let message = try decode(API.SmsMessage.self, """
            <message><smstat>3</smstat><index>7</index><phone>+447700900123</phone><content>hi</content></message>
            """)
        #expect(message.index == 7)
        #expect(message.content == "hi")
    }

    @Test func sendStatusAndError() throws {
        let status = try decode(API.SendStatus.self, """
            <response><Phone></Phone><SucPhone>+447700900123</SucPhone><FailPhone></FailPhone><TotalCount>1</TotalCount><CurIndex>1</CurIndex></response>
            """)
        #expect(status.sucPhone == "+447700900123")
        #expect(status.failPhone == nil)

        let error = try decode(API.ApiError.self, "<error><code>125002</code><message/></error>")
        #expect(error.code == 125002)
    }

    @Test func plainOKResponse() throws {
        #expect(try decode(String.self, "<response>OK</response>") == "OK")
    }

    @Test func encodesListRequestInDocumentOrder() throws {
        let request = API.SmsListRequest(pageIndex: 1, readCount: 20, boxType: 2, sortType: 0, ascending: 0, unreadPreferred: 0)
        #expect(try XMLCoding.encode(request, root: "request") == """
            <?xml version="1.0" encoding="UTF-8"?><request><PageIndex>1</PageIndex><ReadCount>20</ReadCount><BoxType>2</BoxType>\
            <SortType>0</SortType><Ascending>0</Ascending><UnreadPreferred>0</UnreadPreferred></request>
            """)
    }

    @Test func encodesSendRequestWithEscapingAndPhoneList() throws {
        let request = API.SendSmsRequest(index: -1, phones: .init(phone: ["+447700900123"]), sca: "",
                                         content: "a < b & \"c\"", length: 11, reserved: 1, date: "2026-11-12 19:48:11")
        #expect(try XMLCoding.encode(request, root: "request") == """
            <?xml version="1.0" encoding="UTF-8"?><request><Index>-1</Index><Phones><Phone>+447700900123</Phone></Phones><Sca></Sca>\
            <Content>a &lt; b &amp; &quot;c&quot;</Content><Length>11</Length><Reserved>1</Reserved><Date>2026-11-12 19:48:11</Date></request>
            """)
    }

    @Test func encodesIndexRequest() throws {
        #expect(try XMLCoding.encode(API.SmsIndexRequest(index: 40001), root: "request")
                == #"<?xml version="1.0" encoding="UTF-8"?><request><Index>40001</Index></request>"#)
    }

    // MARK: Mobile data, usage and device
    //
    // These documents follow how HiLink sticks generally answer; they have not been captured
    // from a real device yet. Replace them with real responses once the calls are verified.

    @Test func encodesSettingsRequests() throws {
        #expect(try XMLCoding.encode(API.MobileDataSwitch(dataswitch: 0), root: "request")
                == #"<?xml version="1.0" encoding="UTF-8"?><request><dataswitch>0</dataswitch></request>"#)
        #expect(try XMLCoding.encode(API.DeviceControlRequest(control: 1), root: "request")
                == #"<?xml version="1.0" encoding="UTF-8"?><request><Control>1</Control></request>"#)
        #expect(try XMLCoding.encode(API.DeviceControlRequest(control: 2), root: "request")
                == #"<?xml version="1.0" encoding="UTF-8"?><request><Control>2</Control></request>"#)
    }

    @Test func connectionSettingsRoundTripChangesOnlyRoaming() throws {
        var settings = try decode(API.ConnectionSettings.self, """
            <response><RoamAutoConnectEnable>0</RoamAutoConnectEnable><MaxIdelTime>0</MaxIdelTime><ConnectMode>0</ConnectMode>\
            <MTU>1500</MTU><auto_dial_switch>1</auto_dial_switch><pdp_always_on>0</pdp_always_on></response>
            """)
        #expect(settings.roamAutoConnectEnable == 0)
        settings.roamAutoConnectEnable = 1
        #expect(try XMLCoding.encode(settings, root: "request") == """
            <?xml version="1.0" encoding="UTF-8"?><request><RoamAutoConnectEnable>1</RoamAutoConnectEnable><MaxIdelTime>0</MaxIdelTime>\
            <ConnectMode>0</ConnectMode><MTU>1500</MTU><auto_dial_switch>1</auto_dial_switch><pdp_always_on>0</pdp_always_on></request>
            """)
    }

    @Test func monthStatisticsUseLargeCounters() throws {
        let month = try decode(API.MonthStatistics.self, """
            <response><CurrentMonthDownload>19800000000</CurrentMonthDownload><CurrentMonthUpload>2100000000</CurrentMonthUpload>\\
            <MonthDuration>3900000</MonthDuration><MonthLastClearTime>2026-11-1</MonthLastClearTime></response>
            """)
        #expect(month.currentMonthDownload == 19_800_000_000)
        #expect(month.currentMonthUpload == 2_100_000_000)
    }

    @Test func autoUpdateConfigRoundTripChangesOnlyTheSwitch() throws {
        var config = try decode(API.AutoUpdateConfig.self,
                                "<response><auto_update>1</auto_update><ui_download>0</ui_download></response>")
        #expect(config.autoUpdate == 1)
        config.autoUpdate = 0
        #expect(try XMLCoding.encode(config, root: "request")
                == #"<?xml version="1.0" encoding="UTF-8"?><request><auto_update>0</auto_update><ui_download>0</ui_download></request>"#)
    }
}
