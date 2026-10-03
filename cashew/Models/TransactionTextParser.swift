import Foundation

struct ParsedTextTransaction {
    let amount: Int
    let description: String
    let date: Date
}

struct TransactionTextParseResult {
    let transactions: [ParsedTextTransaction]
    let skippedRecordCount: Int
    let assumedYearCount: Int
}

enum TransactionTextParser {
    private struct Record {
        let dateText: String
        let tail: String
        var lines: [String]
    }

    private struct ParsedDate {
        let value: Date
        let assumedYear: Bool
    }

    private struct Money {
        let magnitude: UInt
        let sign: Int?

        func cents(defaultSign: Int = 1) -> Int? {
            let negative = (sign ?? defaultSign) < 0
            if negative, magnitude == UInt(Int.max) + 1 { return Int.min }
            guard magnitude <= UInt(Int.max) else { return nil }
            return negative ? -Int(magnitude) : Int(magnitude)
        }
    }

    private struct Columns {
        let date: Int
        let description: Int
        let amount: Int?
        let debit: Int?
        let credit: Int?
        let balance: Int?
        let type: Int?
    }

    static func parse(_ text: String, defaultYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())) -> TransactionTextParseResult {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        if let table = parseTable(lines, defaultYear: defaultYear) { return table }

        var records: [Record] = []
        var current: Record?
        var skipped = 0
        var hasBalanceHeader = false
        var inPreamble = false
        for rawLine in lines {
            let line = trimmed(rawLine)
            guard !line.isEmpty else { continue }
            if let prefix = datePrefix(in: line) {
                if let record = current { records.append(record) }
                current = Record(dateText: prefix.date, tail: prefix.tail, lines: [])
                inPreamble = false
            } else if isTableHeading(line) {
                hasBalanceHeader = hasBalanceHeader || line.lowercased().contains("balance")
            } else if current != nil {
                current?.lines.append(line)
            } else if !inPreamble {
                skipped += 1
                inPreamble = true
            }
        }
        if let record = current { records.append(record) }

        var transactions: [ParsedTextTransaction] = []
        var assumedYearCount = 0
        for record in records {
            if let (transaction, assumedYear) = parseRecord(record, defaultYear: defaultYear, hasBalanceHeader: hasBalanceHeader) {
                transactions.append(transaction)
                if assumedYear { assumedYearCount += 1 }
            } else {
                skipped += 1
            }
        }
        return TransactionTextParseResult(transactions: transactions, skippedRecordCount: skipped, assumedYearCount: assumedYearCount)
    }

    // Only leading dates delimit records. Dates within a merchant description remain untouched.
    private static func datePrefix(in line: String) -> (date: String, tail: String)? {
        let month = #"(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)"#
        let pattern = #"^(?:\d{4}-\d{1,2}-\d{1,2}|\d{1,2}/\d{1,2}(?:/(?:\d{4}|\d{2}))?|"# + month + #"\.?\s+\d{1,2}(?:,?\s+\d{4})?)(?=\s|$)"#
        guard let range = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return (String(line[range]), trimmed(String(line[range.upperBound...])))
    }

    private static func parseDate(_ text: String, defaultYear: Int) -> ParsedDate? {
        var year = defaultYear
        var month: Int?
        var day: Int?
        var assumedYear = false
        if text.contains("/") {
            let parts = text.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2 || parts.count == 3 else { return nil }
            month = Int(parts[0])
            day = Int(parts[1])
            if parts.count == 3 {
                guard let suppliedYear = Int(parts[2]), parts[2].count == 2 || parts[2].count == 4 else { return nil }
                // Bank exports with two-digit years use the conventional 1950–2049 window.
                year = parts[2].count == 2 ? (suppliedYear < 50 ? 2000 : 1900) + suppliedYear : suppliedYear
            } else {
                assumedYear = true
            }
        } else if text.first?.isNumber == true {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].count == 4, let suppliedYear = Int(parts[0]) else { return nil }
            year = suppliedYear
            month = Int(parts[1])
            day = Int(parts[2])
        } else {
            let parts = text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
                .split(whereSeparator: \.isWhitespace)
            guard parts.count == 2 || parts.count == 3 else { return nil }
            let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            if let index = months.firstIndex(of: String(parts[0].prefix(3)).lowercased()) { month = index + 1 }
            day = Int(parts[1])
            if parts.count == 3 {
                guard parts[2].count == 4, let suppliedYear = Int(parts[2]) else { return nil }
                year = suppliedYear
            } else {
                assumedYear = true
            }
        }
        guard (1...9999).contains(year), let month, (1...12).contains(month), let day, (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        guard verified.year == year, verified.month == month, verified.day == day else { return nil }
        return ParsedDate(value: date, assumedYear: assumedYear)
    }

    private static func parseRecord(_ record: Record, defaultYear: Int, hasBalanceHeader: Bool) -> (ParsedTextTransaction, Bool)? {
        guard let date = parseDate(record.dateText, defaultYear: defaultYear) else { return nil }
        var descriptions: [String] = []
        var amounts: [Money] = []
        var type: String?
        var hasInlineAmount = false
        var hasInlineBalance = false
        var malformed = false
        let candidateLines = ([record.tail] + record.lines).filter { !trimmed($0).isEmpty }
        for (lineIndex, line) in candidateLines.enumerated() {
            let cells = line.components(separatedBy: "\t").map(trimmed).filter { !$0.isEmpty }
            if cells.count >= 3, money(cells[0]) == nil,
               cells.suffix(2).allSatisfy({ isMoneyToken($0) && money($0) != nil }) {
                hasInlineBalance = true
            }
            for value in cells {
                if isMarketingPrompt(value) { continue }
                if isType(value) {
                    if let existingType = type, existingType.lowercased() != value.lowercased() { malformed = true }
                    type = value
                    continue
                }
                if let amount = money(value), isMoneyToken(value) {
                    amounts.append(amount)
                    continue
                }

                // Legacy input places the amount directly after the date, before its description.
                if lineIndex == 0, cells.count == 1, !record.tail.isEmpty,
                   let leading = leadingAmount(in: value) {
                    if let amount = money(leading.amount), !startsNumericToken(leading.remainder) {
                        amounts.append(amount)
                        descriptions.append(leading.remainder)
                    } else {
                        malformed = true
                    }
                    continue
                }

                let trailing = trailingAmounts(in: value)
                if !trailing.amounts.isEmpty {
                    if looksLikeMalformedCurrency(trailing.description) || trailing.amounts.count > 2 {
                        malformed = true
                        continue
                    }
                    // "$1 2.34" is an invalid amount, not a pair of monetary columns.
                    if trailing.amounts.count == 2,
                       !trailing.amounts[0].contains("."),
                       !trailing.amounts[1].contains("$") {
                        malformed = true
                        continue
                    }
                    if trailing.description.isEmpty, trailing.amounts.count != 2 {
                        malformed = true
                        continue
                    }
                    if !trailing.description.isEmpty { descriptions.append(trailing.description) }
                    for token in trailing.amounts {
                        if let amount = money(token) { amounts.append(amount) } else { malformed = true }
                    }
                    hasInlineAmount = true
                    hasInlineBalance = hasInlineBalance || trailing.amounts.count == 2
                    continue
                }
                if looksLikeMalformedCurrency(value) || looksLikeNumericAmount(value) {
                    malformed = true
                } else {
                    descriptions.append(value)
                }
            }
        }
        let hasBalance = hasBalanceHeader || type != nil || hasInlineBalance || hasInlineAmount
        guard !malformed, amounts.count == 1 || (amounts.count == 2 && hasBalance),
              let amount = amounts.first else { return nil }
        let description = cleanedDescription(descriptions)
        guard !description.isEmpty, !isBalanceSummary(description), let cents = amount.cents(defaultSign: inferredSign(description: description, type: type)) else { return nil }
        // Check ignored balances for overflow as well, instead of silently accepting invalid money.
        guard amounts.dropFirst().allSatisfy({ $0.cents() != nil }) else { return nil }
        return (ParsedTextTransaction(amount: cents, description: description, date: date.value), date.assumedYear)
    }

    private static func normalizedSigns(_ value: String) -> String {
        value.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "﹣", with: "-")
            .replacingOccurrences(of: "－", with: "-")
    }

    private static let moneyPattern = #"(?:[+−–—﹣－-]\s*\$?|\$\s*[+−–—﹣－-]?|)\s*(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?"#

    private static func money(_ value: String) -> Money? {
        var normalized = normalizedSigns(trimmed(value))
        let parenthesized = normalized.hasPrefix("(") && normalized.hasSuffix(")")
        if parenthesized { normalized = trimmed(String(normalized.dropFirst().dropLast())) }
        guard normalized.range(of: "^" + moneyPattern + "$", options: .regularExpression) != nil else { return nil }
        normalized = normalized.filter { !$0.isWhitespace }
        let explicitSign: Int?
        if normalized.contains("-") { explicitSign = -1 }
        else if normalized.contains("+") { explicitSign = 1 }
        else { explicitSign = parenthesized ? -1 : nil }
        if parenthesized, normalized.contains("+") || normalized.contains("-") { return nil }
        let unsigned = normalized.filter { $0 != "$" && $0 != "+" && $0 != "-" && $0 != "," }
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard let dollars = UInt(parts[0]) else { return nil }
        let fractionText = parts.count == 2 ? String(parts[1]) : ""
        guard let fraction = UInt(fractionText.padding(toLength: 2, withPad: "0", startingAt: 0)) else { return nil }
        let (hundreds, multipliedOverflow) = dollars.multipliedReportingOverflow(by: 100)
        let (magnitude, addedOverflow) = hundreds.addingReportingOverflow(fraction)
        guard !multipliedOverflow, !addedOverflow, magnitude <= UInt(Int.max) + 1 else { return nil }
        return Money(magnitude: magnitude, sign: explicitSign)
    }

    private static func isMoneyToken(_ value: String) -> Bool {
        let normalized = normalizedSigns(value)
        return normalized.contains("$") || normalized.contains(".") || normalized.hasPrefix("-") || normalized.hasPrefix("+") || normalized.hasPrefix("(")
    }

    private static func leadingAmount(in value: String) -> (amount: String, remainder: String)? {
        let pattern = "^(?:\\(" + moneyPattern + "\\)|" + moneyPattern + #")(?=\s)"#
        guard let range = value.range(of: pattern, options: .regularExpression) else { return nil }
        let remainder = trimmed(String(value[range.upperBound...]))
        guard !remainder.isEmpty else { return nil }
        return (trimmed(String(value[range])), remainder)
    }

    private static func trailingAmounts(in value: String) -> (description: String, amounts: [String]) {
        var remainder = value
        var amounts: [String] = []
        let pattern = #"(?:^|\s)(?:\("# + moneyPattern + "\\)|" + moneyPattern + ")$"
        while let range = remainder.range(of: pattern, options: .regularExpression) {
            let token = trimmed(String(remainder[range]))
            guard isMoneyToken(token) else { break }
            amounts.insert(token, at: 0)
            remainder = trimmed(String(remainder[..<range.lowerBound]))
        }
        return (remainder, amounts)
    }

    private static func startsNumericToken(_ value: String) -> Bool {
        value.range(of: #"^(?:[+−–—-]\s*)?\$?\s*\d+(?:[.,]\d+)?(?:\s|$)"#, options: .regularExpression) != nil
    }

    private static func looksLikeNumericAmount(_ value: String) -> Bool {
        let normalized = normalizedSigns(value)
        return isMoneyToken(normalized) && normalized.allSatisfy { $0.isNumber || $0.isWhitespace || "$+-.,()".contains($0) }
    }

    private static func looksLikeMalformedCurrency(_ value: String) -> Bool {
        value.range(of: #"\$\s*[+−–—-]?\s*\d"#, options: .regularExpression) != nil || looksLikeNumericAmount(value)
    }

    private static func isType(_ value: String) -> Bool {
        ["ach debit", "ach credit", "card", "deposit", "withdrawal", "debit", "credit", "card purchase", "check", "payment", "transfer"].contains(value.lowercased())
    }

    private static func inferredSign(description: String, type: String?) -> Int {
        let normalizedType = type.map { trimmed($0).lowercased() }
        if ["ach debit", "debit", "withdrawal", "check", "payment"].contains(normalizedType ?? "") { return -1 }
        if ["ach credit", "credit", "deposit"].contains(normalizedType ?? "") { return 1 }
        let value = description.lowercased()
        if value.range(of: #"\b(?:ach debit|withdrawal|payment sent)\b"#, options: .regularExpression) != nil { return -1 }
        if value.range(of: #"\b(?:ach credit|deposit|refund|interest|payment received|credit(?!\s+card\b))\b"#, options: .regularExpression) != nil { return 1 }
        if value.range(of: #"\b(?:visa (?:purchase|authorization)|dda purchase|purchase|payment|debit)\b"#, options: .regularExpression) != nil || normalizedType == "card" || normalizedType == "card purchase" { return -1 }
        return 1
    }

    private static func cleanedDescription(_ lines: [String]) -> String {
        var result: [String] = []
        for line in lines {
            let value = trimmed(line)
            guard !value.isEmpty, !result.contains(value) else { continue }
            let coveredByCombinedLine = result.contains { existing in
                existing.hasPrefix("Cash App") && existing.components(separatedBy: ",").map(trimmed).contains(value)
            }
            if !coveredByCombinedLine { result.append(value) }
        }
        return result.joined(separator: " ")
    }

    private static func isBalanceSummary(_ value: String) -> Bool {
        value.range(of: #"^(?:previous|opening|beginning|closing|ending|available|current) balance\b|^balance (?:forward|brought forward)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isMarketingPrompt(_ value: String) -> Bool {
        value.lowercased() == "want to make the most of this deposit?"
    }

    private static func isTableHeading(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower == "date" || (lower.contains("date") && (lower.contains("amount") || lower.contains("balance")) && (lower.contains("description") || lower.contains("transaction")))
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Headers disambiguate transaction amounts from debit/credit and balance columns.
    private static func parseTable(_ lines: [String], defaultYear: Int) -> TransactionTextParseResult? {
        let nonempty = lines.filter { !trimmed($0).isEmpty }
        guard let first = nonempty.first else { return nil }
        let separator: Character
        if first.contains("\t") { separator = "\t" }
        else if first.contains(",") { separator = "," }
        else { return nil }
        guard let headings = delimitedCells(first, separator: separator), let columns = columns(from: headings) else {
            return parseHeaderlessTable(nonempty, separator: separator, defaultYear: defaultYear)
        }
        var transactions: [ParsedTextTransaction] = []
        var skipped = 0
        var assumedYearCount = 0
        for line in nonempty.dropFirst() {
            guard let cells = delimitedCells(line, separator: separator), cells.count == headings.count,
                  let (transaction, assumedYear) = parseTableRow(cells, columns: columns, defaultYear: defaultYear) else {
                skipped += 1
                continue
            }
            transactions.append(transaction)
            if assumedYear { assumedYearCount += 1 }
        }
        return TransactionTextParseResult(transactions: transactions, skippedRecordCount: skipped, assumedYearCount: assumedYearCount)
    }

    private static func columns(from headings: [String]) -> Columns? {
        let normalized = headings.map { $0.lowercased().filter(\.isLetter) }
        func index(_ names: [String]) -> Int? { normalized.firstIndex { names.contains($0) } }
        guard let date = index(["date", "postingdate", "posteddate", "transactiondate", "transdate"]),
              let description = index(["description", "transactiondescription", "payee", "merchant", "name", "memo"]) else { return nil }
        let amount = index(["amount", "transactionamount", "netamount"])
        let debit = index(["debit", "debits", "withdrawal", "withdrawals", "withdrawalamount"])
        let credit = index(["credit", "credits", "deposit", "deposits", "depositamount"])
        guard amount != nil || debit != nil || credit != nil else { return nil }
        return Columns(date: date, description: description, amount: amount, debit: debit, credit: credit,
                       balance: index(["balance", "runningbalance", "availablebalance"]), type: index(["type", "transactiontype"]))
    }

    private static func parseTableRow(_ cells: [String], columns: Columns, defaultYear: Int) -> (ParsedTextTransaction, Bool)? {
        let dateText = trimmed(cells[columns.date])
        guard let prefix = datePrefix(in: dateText), prefix.tail.isEmpty,
              let date = parseDate(prefix.date, defaultYear: defaultYear) else { return nil }
        let description = trimmed(cells[columns.description])
        guard !description.isEmpty, !isBalanceSummary(description) else { return nil }
        let type = columns.type.map { cells[$0] }
        var amount: Money?
        var defaultSign = inferredSign(description: description, type: type)
        if let index = columns.amount, !cells[index].isEmpty {
            amount = money(cells[index])
            guard amount != nil else { return nil }
        } else {
            var candidates: [(Money, Int)] = []
            for (index, sign) in [(columns.debit, -1), (columns.credit, 1)] {
                guard let index, !cells[index].isEmpty else { continue }
                guard let value = money(cells[index]) else { return nil }
                candidates.append((value, sign))
            }
            let nonzero = candidates.filter { $0.0.magnitude != 0 }
            guard nonzero.count <= 1, let selected = nonzero.first ?? candidates.first else { return nil }
            amount = selected.0
            defaultSign = selected.1
        }
        if let balance = columns.balance, !cells[balance].isEmpty {
            guard let value = money(cells[balance]), value.cents() != nil else { return nil }
        }
        guard let cents = amount?.cents(defaultSign: defaultSign) else { return nil }
        return (ParsedTextTransaction(amount: cents, description: description, date: date.value), date.assumedYear)
    }

    private static func parseHeaderlessTable(_ lines: [String], separator: Character, defaultYear: Int) -> TransactionTextParseResult? {
        guard lines.allSatisfy({ $0.contains(separator) }),
              let first = lines.first, let initial = delimitedCells(first, separator: separator),
              initial.count == 3, let prefix = datePrefix(in: initial[0]), prefix.tail.isEmpty else { return nil }
        let amountIndex: Int
        let descriptionIndex: Int
        if money(initial[2]) != nil { amountIndex = 2; descriptionIndex = 1 }
        else if money(initial[1]) != nil { amountIndex = 1; descriptionIndex = 2 }
        else { return nil }
        let columns = Columns(date: 0, description: descriptionIndex, amount: amountIndex, debit: nil, credit: nil, balance: nil, type: nil)
        var transactions: [ParsedTextTransaction] = []
        var skipped = 0
        var assumedYearCount = 0
        for line in lines {
            guard let cells = delimitedCells(line, separator: separator), cells.count == 3,
                  let (transaction, assumedYear) = parseTableRow(cells, columns: columns, defaultYear: defaultYear) else {
                skipped += 1
                continue
            }
            transactions.append(transaction)
            if assumedYear { assumedYearCount += 1 }
        }
        return TransactionTextParseResult(transactions: transactions, skippedRecordCount: skipped, assumedYearCount: assumedYearCount)
    }

    private static func delimitedCells(_ line: String, separator: Character) -> [String]? {
        var cells: [String] = []
        var cell = ""
        var quoted = false
        var closedQuote = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < line.endIndex, line[next] == "\"" {
                        cell.append("\"")
                        index = line.index(after: next)
                        continue
                    }
                    quoted = false
                    closedQuote = true
                } else {
                    cell.append(character)
                }
            } else if character == separator {
                cells.append(trimmed(cell))
                cell = ""
                closedQuote = false
            } else if character == "\"", trimmed(cell).isEmpty, !closedQuote {
                cell = ""
                quoted = true
            } else {
                if closedQuote, !character.isWhitespace { return nil }
                if character == "\"" { return nil }
                cell.append(character)
            }
            index = next
        }
        guard !quoted else { return nil }
        cells.append(trimmed(cell))
        return cells
    }
}
