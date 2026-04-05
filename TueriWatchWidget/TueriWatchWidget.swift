import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct TueriProvider: TimelineProvider {
    func placeholder(in context: Context) -> TueriEntry {
        TueriEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (TueriEntry) -> Void) {
        completion(TueriEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TueriEntry>) -> Void) {
        // Refrescar cada 30 minutos — la complicación es estática,
        // solo necesita existir para que watchOS dé prioridad a la app.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        let timeline = Timeline(entries: [TueriEntry(date: .now)], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Entry

struct TueriEntry: TimelineEntry {
    let date: Date
}

// MARK: - Widget Views

struct TueriWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: TueriEntry

    // Teal oscuro #0D6C78
    private let teal = Color(red: 0.051, green: 0.424, blue: 0.471)

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    // MARK: - Circular (más común en esfera)

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(teal)
        }
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(teal)

            VStack(alignment: .leading, spacing: 1) {
                Text("Tuēri")
                    .font(.system(size: 14, weight: .semibold))
                Text("Monitoreo activo")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Corner

    private var cornerView: some View {
        Image(systemName: "heart.text.clipboard")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(teal)
            .widgetLabel {
                Text("Tuēri")
            }
    }

    // MARK: - Inline

    private var inlineView: some View {
        Label("Tuēri", systemImage: "heart.text.clipboard")
    }
}

// MARK: - Widget Configuration

@main
struct TueriWatchWidget: Widget {
    let kind: String = "TueriWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TueriProvider()) { entry in
            TueriWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tuēri")
        .description("Monitoreo pasivo de signos vitales.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline,
        ])
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    TueriWatchWidget()
} timeline: {
    TueriEntry(date: .now)
}
