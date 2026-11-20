import SwiftUI

/// "Get help & find care": emergency, advice line, doctor and physio, with sources.
struct FindCareSection: View {
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Get help & find care", subtitle: CareResources.ownClinician)
            ForEach(CareResources.all.prefix(compact ? 2 : 10)) { r in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: r.symbol).font(.title3).foregroundStyle(r.urgent ? .white : Theme.accent)
                        .frame(width: 44, height: 44)
                        .background(r.urgent ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Theme.accent.opacity(0.15)), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(r.name).font(.headline)
                            Spacer()
                            Text(r.contact).font(.headline).foregroundStyle(r.urgent ? .red : Theme.accent)
                        }
                        Text(r.when).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let u = URL(string: r.url) { Link("Source", destination: u).font(.caption) }
                    }
                }
            }
            Text(CareResources.abroad).font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
