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
        expect(TransactionTextParser.parse("01/01/2026 10.29 Coffee").transactions.first?.amount == 1029, "legacy positive amount")
        print("TransactionTextParser tests passed")
    }

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
