//
//  DashboardView.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/2/26.
//

import SwiftUI

/// Pantalla principal del paciente tras completar el onboarding.
/// Muestra el código QR de vinculación y los últimos signos vitales registrados.
/// Corresponde a la Screen 6 del diseño de Tuēri.
struct DashboardView: View {

    // MARK: - Estado

    @State private var mostrarAjustes = false
    @State private var isLoading = true
    @State private var ultimoLote: LoteSignosVitales?
    @State private var nombreUsuario = "Paciente"

    // MARK: - Colores

    private let fondoPantalla = Color(red: 0.953, green: 0.957, blue: 0.965)  // #F3F4F6
    private let grisTitulo = Color(red: 0.067, green: 0.094, blue: 0.153)     // #111827
    private let grisTexto = Color(red: 0.420, green: 0.440, blue: 0.500)      // #6B7280
    private let grisFondoQR = Color(red: 0.953, green: 0.957, blue: 0.965)    // #F3F4F6

    // MARK: - Formateador de hora

    private static let formateadorHora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "es_VE")
        return f
    }()

    // MARK: - Signos vitales derivados del lote

    private var signosVitales: [SignoVitalDisplay] {
        let hora = ultimoLote.map { Self.formateadorHora.string(from: $0.finIntervalo) }

        return [
            SignoVitalDisplay(
                icono: "heart.fill",
                colorIcono: Color(.systemRed),
                etiqueta: "Frecuencia Cardíaca",
                valor: ultimoLote?.fcPromedio.map { "\(Int($0.rounded()))" } ?? "--",
                unidad: "lpm",
                hora: hora ?? "--:--"
            ),
            SignoVitalDisplay(
                icono: "drop.fill",
                colorIcono: Color(red: 0.94, green: 0.33, blue: 0.31),
                etiqueta: "Saturación de Oxígeno",
                valor: ultimoLote?.spo2Promedio.map { "\(Int($0.rounded()))" } ?? "--",
                unidad: "%",
                hora: hora ?? "--:--"
            ),
            SignoVitalDisplay(
                icono: "wind",
                colorIcono: Color(red: 0.0, green: 0.65, blue: 0.88),
                etiqueta: "Frecuencia Respiratoria",
                valor: ultimoLote?.frPromedio.map { "\(Int($0.rounded()))" } ?? "--",
                unidad: "rpm",
                hora: hora ?? "--:--"
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
        .task {
            await cargarUltimosSignos()
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

    /// Consulta el último lote de signos vitales del paciente autenticado
    /// y obtiene el nombre del perfil para la cabecera.
    private func cargarUltimosSignos() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id

            // Cargar nombre y último lote en paralelo
            async let loteQuery: [LoteSignosVitales] = SupabaseManager.shared.client
                .from("lotes_signos_vitales")
                .select()
                .eq("id_paciente", value: userId)
                .order("fin_intervalo", ascending: false)
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
            let nombre = await nombreQuery

            await MainActor.run {
                ultimoLote = lotes.first
                if let nombre { nombreUsuario = nombre }
                isLoading = false
            }

            print("[DashboardView] ✅ Datos cargados. Lote encontrado: \(lotes.first != nil)")

        } catch {
            print("[DashboardView] ❌ Error al cargar datos: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Modelo de display para signos vitales

private struct SignoVitalDisplay {
    let icono: String
    let colorIcono: Color
    let etiqueta: String
    let valor: String
    let unidad: String
    let hora: String
}

// MARK: - VitalRowView (Componente de fila)

/// Fila individual que muestra un signo vital con ícono circular, etiqueta, valor y hora.
private struct VitalRowView: View {
    let signo: SignoVitalDisplay
    /// (grisTitulo, grisTexto, grisFondo)
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

                Text(signo.hora)
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
