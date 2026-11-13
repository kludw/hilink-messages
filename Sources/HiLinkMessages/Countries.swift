import Foundation

/// A country with its international dialling code, for entering the SIM's own number.
struct Country: Identifiable, Hashable {
    /// ISO 3166-1 alpha-2 code, e.g. "GB".
    let iso: String
    /// Dialling code without the plus, e.g. "44".
    let dialCode: String

    var id: String { iso }

    var name: String {
        Locale.current.localizedString(forRegionCode: iso) ?? iso
    }

    /// The flag emoji, built from the two regional-indicator letters.
    var flag: String {
        String(String.UnicodeScalarView(iso.unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }

    /// All countries, sorted by their name in the user's language.
    static let all: [Country] = dialCodes
        .split(separator: " ")
        .compactMap { pair -> Country? in
            let parts = pair.split(separator: ":")
            guard parts.count == 2 else { return nil }
            return Country(iso: String(parts[0]), dialCode: String(parts[1]))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static func with(iso: String?) -> Country? {
        guard let iso else { return nil }
        return all.first { $0.iso == iso.uppercased() }
    }

    /// The home country of a SIM, from the mobile country code that starts its IMSI (or a network's PLMN).
    static func forMobileCountryCode(_ code: String) -> Country? {
        guard let mcc = Int(code.prefix(3)), let iso = mobileCountryCodes[mcc] else { return nil }
        return with(iso: iso)
    }

    /// How many digits a national number has (without the leading 0), for the countries where
    /// that is fixed or narrow. Others fall back to the general international limits.
    private static let nationalLengths: [String: ClosedRange<Int>] = [
        "GB": 9...10, "IE": 7...9, "PL": 9...9, "US": 10...10, "CA": 10...10, "FR": 9...9, "ES": 9...9,
        "PT": 9...9, "NL": 9...9, "BE": 8...9, "DE": 6...13, "IT": 8...11, "CH": 9...9, "AT": 7...13,
        "SE": 7...9, "NO": 8...8, "DK": 8...8, "FI": 5...11, "CZ": 9...9, "SK": 9...9, "UA": 9...9,
        "AU": 9...9, "NZ": 8...10, "IN": 10...10, "TR": 10...10,
    ]

    /// Checks a number typed for this country and returns it in international form ("+44 7700900123"),
    /// or a message saying what is wrong with it.
    func normalized(national input: String) -> Result<String, NumberError> {
        let typed = input.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return .failure(.empty) }
        // Spaces, dashes, dots and brackets are fine as separators; anything else is a typo.
        let separators = CharacterSet(charactersIn: " -.()")
        guard typed.unicodeScalars.allSatisfy({ ("0"..."9").contains(Character($0)) || separators.contains($0) }) else {
            return .failure(.invalidCharacters)
        }
        var digits = typed.filter(\.isNumber)
        // The trunk 0 of a national number ("07700…") is not dialled after a country code.
        if digits.hasPrefix("0") { digits.removeFirst() }

        let allowed = Self.nationalLengths[iso] ?? 4...(15 - dialCode.count)
        if digits.count < allowed.lowerBound { return .failure(.tooShort(expected: allowed)) }
        if digits.count > allowed.upperBound { return .failure(.tooLong(expected: allowed)) }
        return .success("+\(dialCode) \(digits)")
    }

    enum NumberError: Error {
        case empty, invalidCharacters
        case tooShort(expected: ClosedRange<Int>)
        case tooLong(expected: ClosedRange<Int>)

        var message: String {
            switch self {
            case .empty: "Enter the phone number."
            case .invalidCharacters: "Use digits only."
            case .tooShort(let expected): "Too short: \(Self.describe(expected)) expected after the country code."
            case .tooLong(let expected): "Too long: \(Self.describe(expected)) expected after the country code."
            }
        }

        private static func describe(_ range: ClosedRange<Int>) -> String {
            range.lowerBound == range.upperBound
                ? "\(range.lowerBound) digits"
                : "\(range.lowerBound) to \(range.upperBound) digits"
        }
    }

    /// Splits "+44 7700 900123" into its country and the rest. Several countries share a code
    /// (+1, +44, +7), so `preferred` wins when its code fits.
    static func split(number: String, preferred: Country?) -> (country: Country, national: String)? {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("+") else { return nil }
        let rest = String(trimmed.dropFirst())
        func remainder(after country: Country) -> String {
            String(rest.dropFirst(country.dialCode.count)).trimmingCharacters(in: .whitespaces)
        }
        if let preferred, rest.hasPrefix(preferred.dialCode) {
            return (preferred, remainder(after: preferred))
        }
        let match = all
            .filter { rest.hasPrefix($0.dialCode) }
            .max { ($0.dialCode.count, primaryRank($0)) < ($1.dialCode.count, primaryRank($1)) }
        return match.map { ($0, remainder(after: $0)) }
    }

    /// Among countries sharing a dialling code, the one most people mean.
    private static func primaryRank(_ country: Country) -> Int {
        ["US", "GB", "RU", "IT", "FR", "NO", "AU", "MA"].contains(country.iso) ? 1 : 0
    }

    private static let dialCodes = """
        AF:93 AL:355 DZ:213 AS:1 AD:376 AO:244 AI:1 AG:1 AR:54 AM:374 AW:297 AU:61 AT:43 AZ:994 BS:1 BH:973 \
        BD:880 BB:1 BY:375 BE:32 BZ:501 BJ:229 BM:1 BT:975 BO:591 BA:387 BW:267 BR:55 VG:1 BN:673 BG:359 \
        BF:226 BI:257 KH:855 CM:237 CA:1 CV:238 KY:1 CF:236 TD:235 CL:56 CN:86 CO:57 KM:269 CG:242 CD:243 \
        CK:682 CR:506 CI:225 HR:385 CU:53 CW:599 CY:357 CZ:420 DK:45 DJ:253 DM:1 DO:1 EC:593 EG:20 SV:503 \
        GQ:240 ER:291 EE:372 SZ:268 ET:251 FK:500 FO:298 FJ:679 FI:358 FR:33 GF:594 PF:689 GA:241 GM:220 \
        GE:995 DE:49 GH:233 GI:350 GR:30 GL:299 GD:1 GP:590 GU:1 GT:502 GG:44 GN:224 GW:245 GY:592 HT:509 \
        HN:504 HK:852 HU:36 IS:354 IN:91 ID:62 IR:98 IQ:964 IE:353 IM:44 IL:972 IT:39 JM:1 JP:81 JE:44 \
        JO:962 KZ:7 KE:254 KI:686 XK:383 KW:965 KG:996 LA:856 LV:371 LB:961 LS:266 LR:231 LY:218 LI:423 \
        LT:370 LU:352 MO:853 MG:261 MW:265 MY:60 MV:960 ML:223 MT:356 MH:692 MQ:596 MR:222 MU:230 YT:262 \
        MX:52 FM:691 MD:373 MC:377 MN:976 ME:382 MS:1 MA:212 MZ:258 MM:95 NA:264 NR:674 NP:977 NL:31 NC:687 \
        NZ:64 NI:505 NE:227 NG:234 NU:683 KP:850 MK:389 MP:1 NO:47 OM:968 PK:92 PW:680 PS:970 PA:507 PG:675 \
        PY:595 PE:51 PH:63 PL:48 PT:351 PR:1 QA:974 RE:262 RO:40 RU:7 RW:250 WS:685 SM:378 ST:239 SA:966 \
        SN:221 RS:381 SC:248 SL:232 SG:65 SX:1 SK:421 SI:386 SB:677 SO:252 ZA:27 KR:82 SS:211 ES:34 LK:94 \
        KN:1 LC:1 PM:508 VC:1 SD:249 SR:597 SE:46 CH:41 SY:963 TW:886 TJ:992 TZ:255 TH:66 TL:670 TG:228 \
        TO:676 TT:1 TN:216 TR:90 TM:993 TC:1 TV:688 UG:256 UA:380 AE:971 GB:44 US:1 UY:598 UZ:998 VU:678 \
        VA:39 VE:58 VN:84 VI:1 YE:967 ZM:260 ZW:263
        """

    /// Mobile country codes (ITU E.212) for the countries above.
    private static let mobileCountryCodes: [Int: String] = {
        let table = """
            202:GR 204:NL 206:BE 208:FR 212:MC 213:AD 214:ES 216:HU 218:BA 219:HR 220:RS 221:XK 222:IT 226:RO \
            228:CH 230:CZ 231:SK 232:AT 234:GB 235:GB 238:DK 240:SE 242:NO 244:FI 246:LT 247:LV 248:EE 250:RU \
            255:UA 257:BY 259:MD 260:PL 262:DE 266:GI 268:PT 270:LU 272:IE 274:IS 276:AL 278:MT 280:CY 282:GE \
            283:AM 284:BG 286:TR 288:FO 290:GL 292:SM 293:SI 294:MK 295:LI 297:ME 302:CA 310:US 311:US 312:US \
            313:US 314:US 315:US 316:US 330:PR 334:MX 338:JM 340:GP 342:BB 344:AG 346:KY 348:VG 350:BM 352:GD \
            354:MS 356:KN 358:LC 360:VC 362:CW 363:AW 364:BS 365:AI 366:DM 368:CU 370:DO 372:HT 374:TT 376:TC \
            400:AZ 401:KZ 402:BT 404:IN 405:IN 410:PK 412:AF 413:LK 414:MM 415:LB 416:JO 417:SY 418:IQ 419:KW \
            420:SA 421:YE 422:OM 424:AE 425:IL 426:BH 427:QA 428:MN 429:NP 432:IR 434:UZ 436:TJ 437:KG 438:TM \
            440:JP 441:JP 450:KR 452:VN 454:HK 455:MO 456:KH 457:LA 460:CN 466:TW 467:KP 470:BD 472:MV 502:MY \
            505:AU 510:ID 514:TL 515:PH 520:TH 525:SG 528:BN 530:NZ 537:PG 539:TO 540:SB 541:VU 542:FJ 546:NC \
            547:PF 549:WS 602:EG 603:DZ 604:MA 605:TN 606:LY 607:GM 608:SN 609:MR 610:ML 611:GN 612:CI 613:BF \
            614:NE 615:TG 616:BJ 617:MU 618:LR 619:SL 620:GH 621:NG 622:TD 623:CF 624:CM 625:CV 626:ST 627:GQ \
            628:GA 629:CG 630:CD 631:AO 632:GW 633:SC 634:SD 635:RW 636:ET 637:SO 638:DJ 639:KE 640:TZ 641:UG \
            642:BI 643:MZ 645:ZM 646:MG 647:RE 648:ZW 649:NA 650:MW 651:LS 652:BW 653:SZ 654:KM 655:ZA 657:ER \
            659:SS 702:BZ 704:GT 706:SV 708:HN 710:NI 712:CR 714:PA 716:PE 722:AR 724:BR 730:CL 732:CO 734:VE \
            736:BO 738:GY 740:EC 744:PY 746:SR 748:UY
            """
        var result: [Int: String] = [:]
        for pair in table.split(separator: " ") {
            let parts = pair.split(separator: ":")
            if parts.count == 2, let code = Int(parts[0]) { result[code] = String(parts[1]) }
        }
        return result
    }()
}
