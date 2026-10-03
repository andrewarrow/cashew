import Foundation

struct ParsedTextTransaction {
    let amount: Int
    let description: String
    let date: Date
}

struct TransactionTextParseResult {
    let transactions: [ParsedTextTransaction]
    let skippedRecordCount: Int
}

enum TransactionTextParser {
    private struct Record {
        var dateLine: String
        var lines: [String]
    }

    static func parse(_ text: String) -> TransactionTextParseResult {
        let lines = text.components(separatedBy: .newlines)
        var records: [Record] = []
        var current: Record?
        var skipped = 0

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if startsDateRecord(line) {
                if let record = current { records.append(record) }
                current = Record(dateLine: line, lines: [])
            } else if !line.isEmpty {
                if current == nil {
                    // Non-empty text before the first record is one malformed record.
                    skipped += 1
                } else {
                    current?.lines.append(line)
                }
            }
        }
        if let record = current { records.append(record) }

        let parsed = records.compactMap { parse(record: $0) }
        skipped += records.count - parsed.count
        return TransactionTextParseResult(transactions: parsed, skippedRecordCount: skipped)
    }

    private static func startsDateRecord(_ line: String) -> Bool {
        line.range(of: #"^\d{1,2}/\d{1,2}/\d{4}(?=\s|$)"#, options: .regularExpression) != nil
    }

    private static func parse(record: Record) -> ParsedTextTransaction? {
        let dateText = String(record.dateLine.prefix { $0 != "\t" && !$0.isWhitespace })
        guard let date = parseDate(dateText) else { return nil }

        var descriptions: [String] = []
        var amounts: [String] = []
        var hasMalformedAmount = false

        // The date line can also carry a legacy transaction or tab-separated bank row.
        let dateTail = String(record.dateLine.dropFirst(dateText.count))
        let candidateLines = ([dateTail] + record.lines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for line in candidateLines {
            let cells = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if cells.count > 1 {
                for cell in cells {
                    if let parsedAmount = amountText(from: cell) {
                        amounts.append(parsedAmount)
                    } else {
                        descriptions.append(cell)
                    }
                }
                continue
            }

            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsedAmount = amountText(from: value) {
                amounts.append(parsedAmount)
                continue
            }

            // Legacy format: MM/DD/YYYY -12.34 Description.
            if amounts.isEmpty,
               let match = value.range(of: #"^[+−-]?\s*\$?\s*(?:\d[\d,]*)(?:\.\d{1,2})?(?=\s|$)"#, options: .regularExpression) {
                let amountCandidate = String(value[match]).trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.amountText(from: amountCandidate) != nil {
                    amounts.append(amountCandidate)
                    let remainder = value[match.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remainder.isEmpty { descriptions.append(remainder) }
                    continue
                }
            }

            // A bank row may put its currency amount after the description on one line.
            if let (description, trailingAmount) = trailingCurrencyAmount(in: value) {
                descriptions.append(description)
                amounts.append(trailingAmount)
                continue
            }

            if looksLikeMalformedAmountLine(value) {
                hasMalformedAmount = true
                continue
            }
            descriptions.append(value)
        }

        guard !hasMalformedAmount, amounts.count == 1,
              let rawAmount = amounts.first,
              let cents = cents(from: rawAmount),
              !descriptions.isEmpty else { return nil }
        let description = descriptions.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return nil }

        let isPurchaseOrAuthorization = ["visa authorization", "visa purchase", "dda purchase"].contains {
            description.range(of: "^\\s*\($0)", options: [.regularExpression, .caseInsensitive]) != nil
        }
        let explicitSign = normalizedAmount(rawAmount).first
        let signedCents: Int
        if explicitSign == "-" || explicitSign == "−" {
            signedCents = -cents
        } else if explicitSign == "+" {
            signedCents = cents
        } else {
            signedCents = isPurchaseOrAuthorization ? -cents : cents
        }
        return ParsedTextTransaction(amount: signedCents, description: description, date: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd/yyyy"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    private static func amountText(from value: String) -> String? {
        let normalized = normalizedAmount(value)
        guard normalized.range(of: #"^[+-]?(?:\$)?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trailingCurrencyAmount(in value: String) -> (String, String)? {
        guard let match = value.range(
            of: #"(?:^|\s)([+−-]?\s*\$\s*\d[\d,]*(?:\.\d{1,2})?)$"#,
            options: .regularExpression
        ) else { return nil }

        let token = String(value[match]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard amountText(from: token) != nil else { return nil }
        let description = String(value[..<match.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return nil }
        return (description, token)
    }

    private static func looksLikeMalformedAmountLine(_ value: String) -> Bool {
        let normalized = normalizedAmount(value)
        guard let first = normalized.first,
              first == "$" || first == "+" || first == "-" else { return false }
        return normalized.contains("$") || normalized.allSatisfy { $0.isNumber || $0 == "." || $0 == "," || $0 == "+" || $0 == "-" }
    }

    private static func normalizedAmount(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
            .filter { !$0.isWhitespace && !$0.isNewline }
    }

    private static func cents(from value: String) -> Int? {
        let normalized = normalizedAmount(value)
        let unsigned = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard let dollars = Int(parts[0]), parts.count <= 2 else { return nil }
        let fractional = parts.count == 2 ? String(parts[1]) : ""
        let paddedFraction = fractional.padding(toLength: 2, withPad: "0", startingAt: 0)
        guard let fraction = Int(paddedFraction), dollars <= (Int.max - fraction) / 100 else { return nil }
        let total = dollars * 100 + fraction
        return total
    }
}
