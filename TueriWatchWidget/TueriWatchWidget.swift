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

    // Nota: no fijamos colores propios en las accessory complications.
    // watchOS controla el tinting según la watch face que el usuario
    // tenga activa — el logo se rendiza en blanco / ámbar / teal / etc.
    // automáticamente. Forzar un color rompería esa coherencia visual.

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
    //
    // Sobre el rendering del logo en complications:
    //   - El asset `TueriLogo` está configurado como `template-rendering-intent: template`,
    //     así que la mayoría de watch faces lo van a tintar con el color de la face
    //     (blanco, ámbar, teal Tuēri, etc.).
    //   - En faces que soportan `.fullColor` (Modular Ultra, Smart Stack), el modificador
    //     `.widgetAccentedRenderingMode(.fullColor)` que aplicamos en `accessoryRectangular`
    //     permite renderizar el logo con sus colores originales.
    //   - `.padding(2)` evita que el logo toque el borde del círculo, que en watchOS
    //     queda apretado y visualmente "amputa" la marca.

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image("IoMT")
                .resizable()
                .scaledToFit()
                .padding(4)
        }
    }

    // MARK: - Rectangular

    private var rectangularView: some View {
        HStack(spacing: 6) {
            // Sobre el rendering del logo a todo color:
            // `widgetAccentedRenderingMode(.fullColor)` permitiría que en
            // faces compatibles (Modular Ultra, Smart Stack) el logo salga
            // con sus colores originales. PERO ese símbolo solo existe en
            // arquitectura arm64e — los Apple Watch Series 4-6 (que aún
            // soportan watchOS 10.x) usan arm64_32, donde el símbolo NO
            // existe. Con deployment target 10.6 Xcode compila para ambas
            // arquitecturas; un guard `#available` no salva la compilación
            // porque arm64_32 ni siquiera ve el símbolo.
            //
            // Cuando subamos el deployment target a watchOS 11.0+ y
            // dropeemos arm64_32 (saca de soporte Series 4-6), podremos
            // añadir `.widgetAccentedRenderingMode(.fullColor)` aquí sin
            // tocar nada más.
            Image("TueriLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text("IoMT")
                    .font(.system(size: 14, weight: .semibold))
                Text("Monitoreo activo")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Corner

    private var cornerView: some View {
        Image("TueriLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
            .widgetLabel {
                Text("IoMT")
            }
    }

    // MARK: - Inline
    //
    // Inline NO acepta imágenes custom — solo SF Symbols a través de `systemImage:`.
    // Es una limitación del sistema (la fila inline es una sola línea de texto en
    // la parte superior de la face). Para esa familia mantenemos el símbolo médico
    // para que al menos sea reconocible al lado del nombre.

    private var inlineView: some View {
        Label("IoMT", systemImage: "heart.text.clipboard")
    }
}

// MARK: - Widget Configuration

@main
struct TueriWatchWidget: Widget {
    let kind: String = "IoMT Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TueriProvider()) { entry in
            TueriWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("IoMT")
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
