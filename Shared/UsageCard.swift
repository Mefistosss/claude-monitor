import SwiftUI

/// The medium-widget layout, also shown in the app window.
struct UsageCard: View {
    var snapshot: UsageSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            sessionColumn
                .frame(width: 92)
            VStack(alignment: .leading, spacing: 5) {
                LimitBar(title: Text("Week"), limit: snapshot.weekly)
                ForEach(snapshot.scoped, id: \.name) { scoped in
                    LimitBar(title: Text(verbatim: scoped.name), limit: scoped.limit, showsReset: false)
                }
                Spacer(minLength: 0)
                Divider()
                tokensLine
                footerLine
            }
        }
    }

    private var sessionColumn: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: (snapshot.session?.remainingPercent ?? 0) / 100)
                    .stroke(UsageColor.forRemaining(snapshot.session?.remainingPercent), style: .init(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(Format.percent(snapshot.session?.remainingPercent))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("left")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 62, height: 62)

            Text("5 hours")
                .font(.system(size: 11, weight: .medium))
            ResetText(date: snapshot.session?.resetsAt)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let plan = snapshot.plan {
                Text(verbatim: plan)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private var tokensLine: some View {
        let t = snapshot.tokens
        return Text("\(Format.compact(t.output)) out · \(Format.compact(t.cacheRead)) cache · 5h")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var footerLine: some View {
        Group {
            if let problem = snapshot.problem {
                Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let login = snapshot.loginExpiresAt {
                Label {
                    Text("Login expires in \(Format.days(until: login))")
                } icon: {
                    Image(systemName: "key.fill")
                }
                .foregroundStyle(login.timeIntervalSinceNow < 3 * 86400 ? .orange : .secondary)
            }
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct LimitBar: View {
    var title: Text
    var limit: UsageSnapshot.Limit?
    var showsReset = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                title.font(.system(size: 11, weight: .medium))
                Spacer()
                Text(Format.percent(limit?.remainingPercent))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            ProgressView(value: (limit?.remainingPercent ?? 0) / 100)
                .progressViewStyle(.linear)
                .tint(UsageColor.forRemaining(limit?.remainingPercent))
                .controlSize(.mini)
            if showsReset, let resets = limit?.resetsAt {
                Text("resets \(resets.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "resets in 2 hr, 10 min" — counts down live inside the widget.
private struct ResetText: View {
    var date: Date?

    var body: some View {
        if let date, date > .now {
            Text("resets in \(Text(date, style: .relative))")
        } else {
            Text(verbatim: "—")
        }
    }
}

enum UsageColor {
    static func forRemaining(_ percent: Double?) -> Color {
        guard let percent else { return .gray }
        switch percent {
        case ..<10: return .red
        case ..<30: return .orange
        default: return .green
        }
    }
}

enum Format {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return (value / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// 57269 -> "57K" / "57 тис." / "57 тыс."
    static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }

    /// Localized "17 days" / "17 днів" / "17 дней".
    static func days(until date: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        let interval = max(0, date.timeIntervalSinceNow)
        formatter.allowedUnits = interval >= 86400 ? [.day] : [.hour, .minute]
        formatter.maximumUnitCount = 1
        return formatter.string(from: interval) ?? ""
    }
}

extension UsageSnapshot.Problem {
    var message: LocalizedStringKey {
        switch self {
        case .notLoggedIn: "Not logged in to Claude Code"
        case .tokenExpired: "Open Claude Code to refresh"
        case .network: "No connection, data may be stale"
        }
    }
}
