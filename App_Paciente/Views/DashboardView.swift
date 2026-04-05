//
//  DashboardView.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/2/26.
//

import SwiftUI
import Auth
import Supabase

/// Pantalla principal del paciente tras completar el onboarding.
/// Muestra el código QR de vinculación y los últimos signos vitales registrados.
///
/// **Mecanismos de refresco:**
/// 1. `.task` — carga inicial al aparecer
/// 2. `.refreshable` — pull-to-refresh manual
/// 3. `scenePhase .active` — al volver a foreground
/// 4. `NotificationCenter .tueriLoteEnviado` — tras envío exitoso de HealthKitManager
struct DashboardView: View {

    // MARK: - Estado

    @Environment(\.scenePhase) private var scenePhase
    @State private var mostrarAjustes = false
    @State private var isLoading = true
    @State private var ultimoLote: LoteSignosVitales?
    @State private var ultimaSpO2: LecturaPuntualDisplay?
    @State private var ultimaFR: LecturaPuntualDisplay?
    @State private var nombreUsuario = "Paciente"

    /// ID que cambia para re-disparar `.task(id:)`.
    /// SwiftUI cancela el task anterior automáticamente → sin refreshes duplicados.
    @State private var refreshID = UUID()

    // MARK: - Colores

    private let fondoPantalla = Color(red: 0.953, green: 0.957, blue: 0.965)  // #F3F4F6
    private let grisTitulo = Color(red: 0.067, green: 0.094, blue: 0.153)     // #111827
    private let grisTexto = Color(red: 0.420, green: 0.440, blue: 0.500)      // #6B7280
    private let grisFondoQR = Color(red: 0.953, green: 0.957, blue: 0.965)    // #F3F4F6

    // MARK: - Formateadores de fecha

    private static let formateadorHora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "es_VE")
        return f
    }()

    private static let formateadorHoraDia: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, h:mm a"
        f.locale = Locale(identifier: "es_VE")
        return f
    }()

    /// Formatea el intervalo del lote para FC.
    /// - Mismo día: "3:50 AM - 4:15 AM"
    /// - Cruza días: "4 abr, 11:50 PM - 5 abr, 12:15 AM"
    private func formatearIntervaloFC() -> String {
        guard let lote = ultimoLote else { return "--:--" }
        let inicio = lote.inicioIntervalo
        let fin = lote.finIntervalo
        let cal = Calendar.current

        if cal.isDate(inicio, inSameDayAs: fin) {
            let hInicio = Self.formateadorHora.string(from: inicio)
            let hFin = Self.formateadorHora.string(from: fin)
            return "\(hInicio) - \(hFin)"
        } else {
            let hInicio = Self.formateadorHoraDia.string(from: inicio)
            let hFin = Self.formateadorHoraDia.string(from: fin)
            return "\(hInicio) - \(hFin)"
        }
    }

    /// Formatea la fecha de una lectura puntual.
    /// Hoy: "3:50 AM"
    /// Otro día: "4 abr, 3:50 AM"
    private func formatearFechaLectura(_ fecha: Date) -> String {
        if Calendar.current.isDateInToday(fecha) {
            return Self.formateadorHora.string(from: fecha)
        } else {
            return Self.formateadorHoraDia.string(from: fecha)
        }
    }

    // MARK: - Signos vitales derivados

    private var signosVitales: [SignoVitalDisplay] {
        return [
            // FC: del último lote (promedio + intervalo)
            SignoVitalDisplay(
                icono: "heart.fill",
                colorIcono: Color(.systemRed),
                etiqueta: "Frecuencia Cardíaca",
                valor: ultimoLote?.fcPromedio.map { "\(Int($0.rounded()))" } ?? "--",
                unidad: "lpm",
                detalleTemporal: formatearIntervaloFC()
            ),
            // SpO2: última lectura puntual
            SignoVitalDisplay(
                icono: "drop.fill",
                colorIcono: Color(red: 0.94, green: 0.33, blue: 0.31),
                etiqueta: "Saturación de Oxígeno",
                valor: ultimaSpO2.map { "\(Int($0.valor.rounded()))" } ?? "--",
                unidad: "%",
                detalleTemporal: ultimaSpO2.map { formatearFechaLectura($0.fecha) } ?? "--:--"
            ),
            // FR: última lectura puntual
            SignoVitalDisplay(
                icono: "wind",
                colorIcono: Color(red: 0.0, green: 0.65, blue: 0.88),
                etiqueta: "Frecuencia Respiratoria",
                valor: ultimaFR.map { "\(Int($0.valor.rounded()))" } ?? "--",
                unidad: "rpm",
                detalleTemporal: ultimaFR.map { formatearFechaLectura($0.fecha) } ?? "--:--"
            ),
        ]
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                cabecera
                    .padding(.bottom, 24)
                tarjetaQR
                    .padding(.bottom, 24)
                seccionSignosVitales
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .refreshable {
            await cargarUltimosSignos()
        }
        .background(fondoPantalla.ignoresSafeArea())
        .navigationDestination(isPresented: $mostrarAjustes) {
            AjustesView()
        }
        // Un solo .task(id:) para TODOS los triggers.
        // Cambiar refreshID re-ejecuta el task; SwiftUI cancela el anterior.
        // Esto previene 3 queries Supabase simultáneas al abrir la app.
        .task(id: refreshID) {
            await cargarUltimosSignos()
        }
        // Refresco al volver a foreground
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                print("[Dashboard] 🟢 Foreground → refresh")
                refreshID = UUID()
            }
        }
        // Refresco cuando HealthKitManager envía un lote exitosamente
        .onReceive(
            NotificationCenter.default.publisher(for: .tueriLoteEnviado)
        ) { _ in
            print("[Dashboard] 📬 Lote enviado → refresh")
            refreshID = UUID()
        }
    }

    // MARK: - Cabecera

    private var cabecera: some View {
        HStack {
            Text("Hola, \(nombreUsuario)")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(grisTitulo)

            Spacer()

            Button {
                mostrarAjustes = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(grisTexto)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Tarjeta QR

    private var tarjetaQR: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 14)
                .fill(grisFondoQR)
                .frame(width: 176, height: 176)
                .overlay(
                    Image(systemName: "qrcode")
                        .font(.system(size: 100, weight: .ultraLight))
                        .foregroundStyle(grisTitulo)
                )

            Text("Permite que tu médico escanee este código para poder monitorear tus signos vitales.")
                .font(.system(size: 14))
                .foregroundStyle(grisTexto)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 260)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }

    // MARK: - Sección Signos Vitales

    private var seccionSignosVitales: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ÚLTIMOS DATOS REGISTRADOS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(grisTexto)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .tint(Color(red: 0.051, green: 0.424, blue: 0.471))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ForEach(Array(signosVitales.enumerated()), id: \.element.etiqueta) { index, signo in
                        VitalRowView(signo: signo, colores: (grisTitulo, grisTexto, grisFondoQR))

                        if index < signosVitales.count - 1 {
                            Divider()
                                .background(fondoPantalla)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
        }
    }

    // MARK: - Carga de datos desde Supabase

    private func cargarUltimosSignos() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id

            // Cargar en paralelo: lote (FC), lectura SpO2, lectura FR, nombre
            async let loteQuery: [LoteSignosVitales] = SupabaseManager.shared.client
                .from("lotes_signos_vitales")
                .select()
                .eq("id_paciente", value: userId)
                .order("fin_intervalo", ascending: false)
                .limit(1)
                .execute()
                .value

            async let spo2Query: [LecturaPuntualRow] = SupabaseManager.shared.client
                .from("lecturas_puntuales")
                .select()
                .eq("id_paciente", value: userId)
                .eq("tipo_signo", value: "spo2")
                .order("fecha_lectura", ascending: false)
                .limit(1)
                .execute()
                .value

            async let frQuery: [LecturaPuntualRow] = SupabaseManager.shared.client
                .from("lecturas_puntuales")
                .select()
                .eq("id_paciente", value: userId)
                .eq("tipo_signo", value: "fr")
                .order("fecha_lectura", ascending: false)
                .limit(1)
                .execute()
                .value

            async let nombreQuery: String? = {
                if let meta = session.user.userMetadata["nombre_completo"]?.stringValue {
                    return meta.components(separatedBy: " ").first ?? meta
                }
                return nil
            }()

            let lotes = try await loteQuery
            let spo2Rows = try await spo2Query
            let frRows = try await frQuery
            let nombre = await nombreQuery

            await MainActor.run {
                ultimoLote = lotes.first
                ultimaSpO2 = spo2Rows.first.map {
                    LecturaPuntualDisplay(valor: $0.valor, fecha: $0.fechaLectura)
                }
                ultimaFR = frRows.first.map {
                    LecturaPuntualDisplay(valor: $0.valor, fecha: $0.fechaLectura)
                }
                if let nombre { nombreUsuario = nombre }
                isLoading = false
            }

            print("[Dashboard] ✅ Datos cargados. Lote: \(lotes.first != nil) SpO2: \(spo2Rows.first != nil) FR: \(frRows.first != nil)")

        } catch {
            print("[Dashboard] ❌ Error: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Modelos de datos para lecturas puntuales

/// Fila decodificada de la tabla `lecturas_puntuales`.
/// Solo se usa para la query de Supabase → se convierte a `LecturaPuntualDisplay`.
private struct LecturaPuntualRow: Codable {
    let idLectura: UUID
    let idPaciente: UUID
    let tipoSigno: String
    let valor: Double
    let fechaLectura: Date
    let creadoEn: Date?

    enum CodingKeys: String, CodingKey {
        case idLectura = "id_lectura"
        case idPaciente = "id_paciente"
        case tipoSigno = "tipo_signo"
        case valor
        case fechaLectura = "fecha_lectura"
        case creadoEn = "creado_en"
    }
}

/// Modelo ligero para el estado del dashboard. Solo valor + fecha.
private struct LecturaPuntualDisplay {
    let valor: Double
    let fecha: Date
}

// MARK: - Modelo de display para signos vitales

private struct SignoVitalDisplay {
    let icono: String
    let colorIcono: Color
    let etiqueta: String
    let valor: String
    let unidad: String
    let detalleTemporal: String
}

// MARK: - VitalRowView (Componente de fila)

private struct VitalRowView: View {
    let signo: SignoVitalDisplay
    let colores: (Color, Color, Color)

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(colores.2)
                    .frame(width: 40, height: 40)

                Image(systemName: signo.icono)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(signo.colorIcono)
            }

            Text(signo.etiqueta)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colores.0)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(signo.valor)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(colores.0)

                    Text(signo.unidad)
                        .font(.system(size: 14))
                        .foregroundStyle(colores.1)
                }

                Text(signo.detalleTemporal)
                    .font(.system(size: 12))
                    .foregroundStyle(colores.1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DashboardView()
    }
}
