import Foundation

@main
enum TransactionTextParserTests {
    static func main() {
        let fixture = """
        10/02/2026
        Dda Purchase 74862889 Uber Trip San Franciscoca Usa 2026-10-02 11.32.12
        - $13.98

        10/02/2026
        Dda Purchase 04802911 Waymo Www.waymo.comca Usa 2026-10-02 11.23.51
        - $16.43

        10/02/2026
        Visa Authorization 74862889 Uber Trip 2026-10-02 15.17.42
        $57.99

        10/02/2026
        Visa Authorization 469216 Starbucks 8007827282 2026-10-02 09.36.33
        $25.00

        10/02/2026
        Visa Authorization 403629 Dd *doordash 2026-10-02 08.18.10
        $28.33

        10/02/2026
        Visa Purchase 00009551 Ucla Physicians Www.ucla.com Causa 2026-10-02 09.42.24
        - $235.89

        10/02/2026
        Visa Purchase Ybyt3pb5 Rvivl 121-36865600 Causa 2026-10-02 09.42.23
        - $70.00

        10/02/2026
        Dda Purchase 00n3cc01 7-eleven Culver City Ca Usa 2026-10-02 20.04.40
        - $7.18

        10/02/2026
        Visa Purchase 424818 Venmo *john Castillo New York Ny Usa10014 2026-10-02 15.42.38
        - $200.00

        10/02/2026
        Visa Authorization 469216 In-n-out Culver City 2026-10-02 18.26.21
        $62.47

        10/02/2026
        Visa Authorization 423168 Pavilions #2212 2026-10-02 12.38.41
        $18.60

        10/02/2026
        Visa Authorization 442733 Chick-fil-a #03331 2026-10-02 10.39.24
        $5.57

        10/02/2026
        Visa Authorization 479338 Acorns Early 2026-10-02 08.00.07
        $52.00

        10/02/2026
        Visa Purchase Chevron 0092916 Los Angeles Causa 2026-10-02 09.42.14
        - $75.00

        10/02/2026
        Visa Purchase Acorns Early 855-7392859 Deusa 2026-10-02 09.42.13
        - $52.00

        10/02/2026
        Visa Purchase 00009551 Ucla Physicians Www.ucla.com Causa 2026-10-02 09.42.12
        - $40.00

        10/01/2026
        Visa Authorization 403629 Dd *doordash Oakberrya 2026-10-01 17.02.27
        $13.94

        10/01/2026
        Visa Authorization 469216 Proquestebs 7349974150 2026-10-01 21.59.09
        $44.00

        10/01/2026
        Visa Authorization 442733 Chick-fil-a #03331 2026-10-01 18.44.38
        $19.34

        10/01/2026
        Visa Authorization 442733 Chick-fil-a #03331 2026-10-01 17.35.52
        $10.34
        """
        let result = TransactionTextParser.parse(fixture)
        expect(result.transactions.count == 20, "fixture should parse all 20 records")
        expect(result.skippedRecordCount == 0, "fixture should have no skipped records")
        let expectedAmounts = [-1398, -1643, -5799, -2500, -2833, -23589, -7000, -718, -20000, -6247,
                               -1860, -557, -5200, -7500, -5200, -4000, -1394, -4400, -1934, -1034]
        expect(result.transactions.map(\.amount) == expectedAmounts, "fixture cents and bank sign handling")
        expect(result.transactions.allSatisfy { dateString($0.date) == ($0.description.contains("2026-10-01") ? "10/01/2026" : "10/02/2026") }, "fixture dates")
        expect(result.transactions[0].description == "Dda Purchase 74862889 Uber Trip San Franciscoca Usa 2026-10-02 11.32.12", "preserve full bank description")
        expect(result.transactions[12].description.hasPrefix("Visa Authorization"), "preserve authorization prefix")
        expect(result.transactions[12].description.contains("08.00.07"), "preserve description timestamp")
        expect(result.transactions[12].description != result.transactions[14].description, "keep authorization and purchase entries distinct")

        let signs = TransactionTextParser.parse("""
        01/02/2026 $10.29 Deposit
        01/02/2026 + $19.34 Visa Authorization adjustment
        01/02/2026 - $0.29 Refund
        01/02/2026 $1,234.56 Credit
        """)
        expect(signs.transactions.map(\.amount) == [1029, 1934, -29, 123456], "explicit signs, cents precision, and grouping separators")

        let tabsOneLine = TransactionTextParser.parse("01/02/2026\tVisa Purchase 0091 Store 2026-01-02 12.30.00\t$2.05\r\n01/03/2026 -0.29 Legacy format\r\n")
        expect(tabsOneLine.transactions.count == 2, "tab row, CRLF, and legacy format")
        expect(tabsOneLine.transactions[0].amount == -205, "unsigned bank purchase is an expense")
        expect(tabsOneLine.transactions[0].description == "Visa Purchase 0091 Store 2026-01-02 12.30.00", "tab row description")
        expect(tabsOneLine.transactions[1].amount == -29 && tabsOneLine.transactions[1].description == "Legacy format", "legacy signed input")

        let spaceSeparatedBankRow = TransactionTextParser.parse("10/02/2026 Visa Authorization 469216 Starbucks 2026-10-02 09.36.33 $25.00")
        expect(spaceSeparatedBankRow.transactions.count == 1, "space-separated one-line bank row")
        expect(spaceSeparatedBankRow.transactions[0].amount == -2500, "space-separated bank row amount")
        expect(spaceSeparatedBankRow.transactions[0].description == "Visa Authorization 469216 Starbucks 2026-10-02 09.36.33", "space-separated bank row description")

        let recovery = TransactionTextParser.parse("""
        02/30/2026
        Visa Authorization Store
        $10.00
        02/01/2026
        Visa Authorization Good 2026-02-01 14.15.00
        $19.34
        02/02/2026
        Visa Purchase Bad Currency
        $1.2.3
        02/03/2026
        Visa Purchase Incomplete
        """)
        expect(recovery.transactions.count == 1 && recovery.transactions[0].amount == -1934, "reject invalid date, currency, and incomplete blocks while recovering")
        expect(recovery.skippedRecordCount == 3, "count skipped records")
        let ambiguous = TransactionTextParser.parse("""
        02/04/2026
        Visa Purchase Ambiguous
        $10.00
        $11.00
        02/05/2026
        Visa Purchase Malformed
        $1,23 Merchant
        $12.00
        """)
        expect(ambiguous.transactions.isEmpty, "reject multiple amounts and malformed currency even with a valid amount")
        expect(ambiguous.skippedRecordCount == 2, "count ambiguous and malformed records")
        let malformedSpacingAndOverflow = TransactionTextParser.parse("""
        02/06/2026
        Visa Purchase Spaced Digits
        $1 2.34
        02/07/2026
        Visa Purchase Overflow
        $999999999999999999999999999.99
        """)
        expect(malformedSpacingAndOverflow.transactions.isEmpty, "reject whitespace inside amounts and integer overflow")
        expect(malformedSpacingAndOverflow.skippedRecordCount == 2, "count malformed spacing and overflow records")
        expect(TransactionTextParser.parse("01/01/2026 10.29 Coffee").transactions.first?.amount == 1029, "legacy positive amount")
        expect(TransactionTextParser.parse("1/2/2026 $1.00 Coffee").transactions.first?.amount == 100, "accept unpadded month and day")

        let chase = TransactionTextParser.parse(chaseStatement, defaultYear: 2026)
        let chaseAmounts = [-155102, 254, -1600, -1600, 242592, -2000, -1600, 19325, -1899,
                            -1600, 31795, -123008, -1600, -1600, 138600, -1600, -2499, -1600]
        let chaseDates = ["10/01/2026", "10/01/2026", "09/29/2026", "09/21/2026", "09/21/2026",
                          "09/16/2026", "09/15/2026", "09/14/2026", "09/08/2026", "09/08/2026",
                          "09/08/2026", "09/01/2026", "08/31/2026", "08/26/2026", "08/25/2026",
                          "08/18/2026", "08/17/2026", "08/11/2026"]
        expect(chase.transactions.count == 18 && chase.skippedRecordCount == 0, "Chase statement should parse all 18 records")
        expect(chase.transactions.map(\.amount) == chaseAmounts, "Chase amounts use transaction amount rather than running balance")
        expect(chase.transactions.map { dateString($0.date) } == chaseDates, "Chase English and numeric dates")
        expect(chase.transactions[0].description == "APPLECARD GSBANK PAYMENT 7010919 WEB ID: 9999999999", "deduplicate repeated Chase description")
        expect(chase.transactions[2].description == "Cash App (...7970), JORDAN ARROW", "merge distinct wrapped description lines without duplicate text")
        expect(chase.transactions[4].description == "REMOTE ONLINE DEPOSIT # 1", "remove deposit promotion and type label")
        expect(chase.transactions[13].description == "CASH APP*JORDAN ARROW Oakland CA 08/25 (...7970)", "keep date-like merchant metadata in description")
        expect(chase.transactions.allSatisfy { !$0.description.contains("ACH debit") && !$0.description.contains("ACH credit") && !$0.description.contains("Card") && !$0.description.contains("Deposit") }, "omit Chase transaction type labels")
        expect(chase.transactions.allSatisfy {
            $0.description.range(of: #"\b\d[\d,]*\.\d{2}\b"#, options: .regularExpression) == nil
        }, "omit Chase running balances")

        let pdf = TransactionTextParser.parse(pdfStatement, defaultYear: 2026)
        let pdfAmounts = [-1600, -2499, -1600, 138600, -1600, -1600, -123008, 31795, -1600, -1899]
        let pdfDates = ["08/11/2026", "08/17/2026", "08/18/2026", "08/25/2026", "08/26/2026",
                        "08/31/2026", "09/01/2026", "09/08/2026", "09/08/2026", "09/08/2026"]
        expect(pdf.transactions.count == 10 && pdf.skippedRecordCount == 0, "PDF statement should parse all 10 rows and wrapped balances")
        expect(pdf.transactions.map(\.amount) == pdfAmounts, "PDF statement amounts and debit/credit signs")
        expect(pdf.transactions.map { dateString($0.date) } == pdfDates, "PDF yearless dates follow posting dates, not merchant metadata")
        expect(pdf.assumedYearCount == 10, "count yearless PDF transaction dates")
        expect(pdf.transactions[3].description.contains("1"), "preserve standalone account or merchant identifier")
        expect(pdf.transactions[4].description.hasPrefix("Payment Sent 08/25"), "08/25 merchant metadata does not override 08/26 posting date")
        let pdfWithPriorDefaultYear = TransactionTextParser.parse(pdfStatement, defaultYear: 2025)
        expect(pdfWithPriorDefaultYear.transactions.allSatisfy { dateString($0.date).hasSuffix("2025") }, "custom default year applies to yearless dates")
        expect(pdfWithPriorDefaultYear.assumedYearCount == 10, "count each date assigned the custom default year")

        let delimited = TransactionTextParser.parse("""
        Date,Description,Debit,Credit,Balance
        2026-01-02,"Coffee, Main St",12.34,,100.00
        2026-01-03,Payroll,,1234.56,1334.56
        """)
        expect(delimited.transactions.count == 2, "parse delimited rows with headers and quoted commas")
        expect(delimited.transactions.map(\.amount) == [-1234, 123456], "debit and credit columns determine signs, ignoring balances")
        expect(delimited.transactions[0].description == "Coffee, Main St", "quoted comma remains in description")
        expect(delimited.transactions[1].description == "Payroll", "numeric balance does not enter description")
        let tabDelimited = TransactionTextParser.parse("""
        Date\tDescription\tDebit\tCredit\tBalance
        2026-01-04\tTrain\t8.00\t\t50.00
        """)
        expect(tabDelimited.transactions.count == 1 && tabDelimited.transactions[0].amount == -800, "parse TSV headers and debit columns")
        expect(tabDelimited.transactions.first?.description == "Train", "TSV balance column stays out of description")

        let openingBalanceAndCompactRows = TransactionTextParser.parse("""
        06/28/2019 Previous Balance $445.28
        07/01/2019 Deposit = 131 $209.54 $654.82
        07/01/2019 C&J CLARK RETAIL ACH DEBIT SETTLEMENT STORE
        NBR 131
        $21.70 $1,308.47
        07/03/2019 DEPOSIT CORRECTION CREDIT $13.04 $1,471.53
        """)
        expect(openingBalanceAndCompactRows.transactions.count == 3, "ignore statement opening balance and parse compact transaction rows")
        expect(openingBalanceAndCompactRows.transactions.map(\.amount) == [20954, -2170, 1304], "separate compact transaction amounts from balances")
        expect(openingBalanceAndCompactRows.transactions[0].description.contains("131"), "preserve deposit identifier")
        expect(openingBalanceAndCompactRows.transactions[1].description.contains("NBR 131"), "preserve wrapped merchant identifier")

        let genericDates = TransactionTextParser.parse("""
        2026-02-03 $4.50 ISO Coffee
        February 4, 2026 -$2.25 Book
        02/05/2026 ($3.00) Parenthesized Refund
        """)
        expect(genericDates.transactions.count == 3, "accept ISO, full English month, and parenthesized negative formats")
        expect(genericDates.transactions.map(\.amount) == [450, -225, -300], "parse generic amount signs")
        expect(genericDates.transactions.map { dateString($0.date) } == ["02/03/2026", "02/04/2026", "02/05/2026"], "generic supported date formats")

        let directionPrecedence = TransactionTextParser.parse("""
        01/02/2026
        Credit Card Payment
        ACH debit
        $10.00
        $100.00
        01/03/2026
        Purchase Adjustment
        ACH credit
        $2.00
        $102.00
        01/04/2026
        Merchant Refund
        Card
        $5.00
        $107.00
        """)
        expect(directionPrecedence.transactions.map(\.amount) == [-1000, 200, 500], "transaction type controls unsigned amount direction despite misleading description words")
        expect(directionPrecedence.transactions.map(\.description) == ["Credit Card Payment", "Purchase Adjustment", "Merchant Refund"], "preserve descriptions while resolving direction from transaction type")

        print("TransactionTextParser tests passed")
    }

    private static let chaseStatement = """
    Oct 1, 2026
    APPLECARD GSBANK PAYMENT 7010919 WEB ID: 9999999999
    APPLECARD GSBANK PAYMENT 7010919 WEB ID: 9999999999
    ACH debit
    −$1,551.02
    $10,864.69
    10/01/2026
    APPLE INC. ACH/CRED PPD ID: A243609761
    APPLE INC. ACH/CRED PPD ID: A243609761
    ACH credit
    $2.54
    $12,415.71
    Sep 29, 2026
    Cash App (...7970), JORDAN ARROW
    Cash App (...7970)
    JORDAN ARROW
    Card
    −$16.00
    $12,413.17
    Sep 21, 2026
    Cash App (...7970), JORDAN ARROW
    Cash App (...7970)
    JORDAN ARROW
    Card
    −$16.00
    $12,429.17
    09/21/2026
    REMOTE ONLINE DEPOSIT # 1
    Want to make the most of this deposit?
    Deposit
    $2,425.92
    $12,445.17
    Sep 16, 2026
    Cash App (...7970), JORDAN ARROW
    Cash App (...7970)
    JORDAN ARROW
    Card
    −$20.00
    $10,019.25
    Sep 15, 2026
    Cash App (...7970), JORDAN ARROW
    Cash App (...7970)
    JORDAN ARROW
    Card
    −$16.00
    $10,039.25
    Sep 14, 2026
    REMOTE ONLINE DEPOSIT # 1
    Deposit
    $193.25
    $10,055.25
    Sep 8, 2026
    PAYPAL PURCHASE SPOTIFY*P469009 WEB ID: PAYPALSI77
    PAYPAL PURCHASE SPOTIFY*P469009 WEB ID: PAYPALSI77
    ACH debit
    −$18.99
    $9,862.00
    09/08/2026
    CASH APP*JORDAN ARROW Oakland CA 09/07 (...7970)
    CASH APP*JORDAN ARROW Oakland CA 09/07 (...7970)
    Card
    −$16.00
    $9,880.99
    09/08/2026
    REMOTE ONLINE DEPOSIT # 1
    Deposit
    $317.95
    $9,896.99
    Sep 1, 2026
    APPLECARD GSBANK PAYMENT 7010919 WEB ID: 9999999999
    APPLECARD GSBANK PAYMENT 7010919 WEB ID: 9999999999
    ACH debit
    −$1,230.08
    $9,579.04
    Aug 31, 2026
    Cash App (...7970), JORDAN ARROW
    Cash App (...7970)
    JORDAN ARROW
    Card
    −$16.00
    $10,809.12
    Aug 26, 2026
    CASH APP*JORDAN ARROW Oakland CA 08/25 (...7970)
    CASH APP*JORDAN ARROW Oakland CA 08/25 (...7970)
    Card
    −$16.00
    $10,825.12
    Aug 25, 2026
    REMOTE ONLINE DEPOSIT # 1
    Deposit
    $1,386.00
    $10,841.12
    Aug 18, 2026
    Cash App (...7970), JORDAN ARROW
    Cash App (...7970)
    JORDAN ARROW
    Card
    −$16.00
    $9,455.12
    Aug 17, 2026
    PAYPAL PURCHASE TUNECORE WEB ID: PAYPALSI77
    PAYPAL PURCHASE TUNECORE WEB ID: PAYPALSI77
    ACH debit
    −$24.99
    $9,471.12
    Aug 11, 2026
    Cash App (...7970), JORDAN ARROW
    Cash App (...7970)
    JORDAN ARROW
    Card
    −$16.00
    $9,496.11
    """

    private static let pdfStatement = """
    08/11 Payment Sent 08/11 Cash App*Jordan Arrow Oakland CA Card 7970 -16.00 9,496.11
    08/17 Paypal Purchase Tunecore Web ID: Paypalsi77 -24.99 9,471.12
    08/18 Payment Sent 08/18 Cash App*Jordan Arrow Oakland CA Card 7970 -16.00 9,455.12
    08/25 Remote Online Deposit 1 1,386.00
    10,841.12
    08/26 Payment Sent 08/25 Cash App*Jordan Arrow Oakland CA Card 7970 -16.00 10,825.12
    08/31 Payment Sent 08/31 Cash App*Jordan Arrow Oakland CA Card 7970 -16.00 10,809.12
    09/01 Applecard Gsbank Payment 7010919 Web ID: 9999999999 -1,230.08 9,579.04
    09/08 Remote Online Deposit 1 317.95
    9,896.99
    09/08 Payment Sent 09/07 Cash App*Jordan Arrow Oakland CA Card 7970 -16.00 9,880.99
    09/08 Paypal Purchase Spotify*P469009 Web ID: Paypalsi77 -18.99 9,862.00
    """

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
