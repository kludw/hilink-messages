import Testing
@testable import HiLinkMessages

struct LogicTests {
    @Test(arguments: [
        ("hello", 5, 160, 1),
        ("cost €5 [ok]", 15, 160, 1),
        ("zażółć", 6, 70, 1),
        (String(repeating: "a", count: 161), 161, 306, 2),
    ])
    func smsCounter(text: String, used: Int, capacity: Int, segments: Int) {
        let count = SMSCounter.count(text)
        #expect(count.used == used)
        #expect(count.capacity == capacity)
        #expect(count.segments == segments)
    }

    @Test(arguments: [
        ("Your one-time code is 284 913. Never share this code with anyone.", "284913"),
        ("G-482913 is your Google verification code.", "482913"),
        ("Twój kod to 9921", "9921"),
        ("Your bill for account no. 12001650961 is £20.00 this month.", nil),
        ("See you at 1830 tomorrow", nil),
    ] as [(String, String?)])
    func verificationCode(text: String, expected: String?) {
        #expect(MessageText.verificationCode(in: text) == expected)
    }

    @Test func phoneNumbersMatchAcrossFormats() {
        #expect(ContactsDirectory.key(for: "+44 7700 900123") == ContactsDirectory.key(for: "07700 900123"))
        #expect(ContactsDirectory.key(for: "MyBank") == nil)
    }

    @Test func numberValidation() throws {
        let uk = try #require(Country.with(iso: "GB"))
        #expect(try uk.normalized(national: "07700 900123").get() == "+44 7700900123")
        #expect(throws: Country.NumberError.self) { try uk.normalized(national: "0770 12").get() }
        #expect(throws: Country.NumberError.self) { try uk.normalized(national: "0770O 900123").get() }
    }
}
