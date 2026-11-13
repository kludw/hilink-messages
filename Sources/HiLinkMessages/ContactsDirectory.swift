import Contacts
import Foundation

struct ContactInfo: Sendable, Hashable {
    var name: String
    /// Small square photo from the contact card, if the contact has one.
    var imageData: Data?
}

/// One phone number of one contact, for the "To:" field suggestions.
struct ContactEntry: Sendable, Hashable, Identifiable {
    var name: String
    var number: String
    /// "mobile", "home", … if the number is labelled.
    var label: String?
    var imageData: Data?

    var id: String { name + "|" + number }
}

struct ContactsSnapshot: Sendable {
    /// Lookup by normalised phone number.
    var index: [String: ContactInfo] = [:]
    /// Every contact number, sorted by name.
    var entries: [ContactEntry] = []
}

/// Read-only lookup of names and photos from the Mac's Contacts, keyed by phone number.
enum ContactsDirectory {
    /// Asks for Contacts access if needed and returns every contact that has a phone number.
    /// Returns an empty index if access is denied.
    static func load() async -> ContactsSnapshot {
        let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        guard granted else { return ContactsSnapshot() }

        return await Task.detached(priority: .utility) {
            let keys: [any CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactOrganizationNameKey as NSString,
                CNContactPhoneNumbersKey as NSString,
                CNContactThumbnailImageDataKey as NSString,
            ]
            var snapshot = ContactsSnapshot()
            let request = CNContactFetchRequest(keysToFetch: keys)
            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                let formatted = CNContactFormatter.string(from: contact, style: .fullName)
                let name = formatted ?? contact.organizationName
                guard !name.isEmpty else { return }
                let info = ContactInfo(name: name, imageData: contact.thumbnailImageData)
                for phone in contact.phoneNumbers {
                    let number = phone.value.stringValue
                    guard let key = key(for: number) else { continue }
                    if snapshot.index[key] == nil { snapshot.index[key] = info }
                    let label = phone.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) }
                    snapshot.entries.append(ContactEntry(name: name, number: number, label: label,
                                                         imageData: info.imageData))
                }
            }
            snapshot.entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return snapshot
        }.value
    }

    /// Normalises a phone number so that "+44 7700 900123" and "07700 900123" match.
    /// Numbers are compared on their last nine digits; shorter numbers must match exactly.
    /// Alphanumeric sender IDs (e.g. "BankAlert") never match a contact.
    static func key(for number: String) -> String? {
        guard !number.contains(where: \.isLetter) else { return nil }
        let digits = number.filter { $0.isASCII && $0.isNumber }
        guard digits.count >= 3 else { return nil }
        return digits.count >= 9 ? String(digits.suffix(9)) : digits
    }
}
