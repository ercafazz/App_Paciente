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

    // MARK: - Estado de navegación

    @State private var mostrarAjustes = false
    
    // MARK: - Datos Mock

    private let nombreUsuario = "Ernesto"

    private let signosMock: [SignoVitalMock] = [
        SignoVitalMock(
            icono: "heart.fill",
            colorIcono: Color(.systemRed),
            etiqueta: "Frecuencia Cardíaca",
            valor: "72",
            unidad: "lpm",
            hora: "10:42 AM"
        ),
        SignoVitalMock(
            icono: "drop.fill",
            colorIcono: Color(red: 0.94, green: 0.33, blue: 0.31),
            etiqueta: "Saturación de Oxígeno",
            valor: "98",
            unidad: "%",
            hora: "10:30 AM"
        ),
        SignoVitalMock(
            icono: "wind",
            colorIcono: Color(red: 0.0, green: 0.65, blue: 0.88),
            etiqueta: "Frecuencia Respiratoria",
            valor: "16",
            unidad: "rpm",
            hora: "10:15 AM"
        ),
    ]

    // MARK: - Colores

    private let fondoPantalla = Color(red: 0.953, green: 0.957, blue: 0.965)  // #F3F4F6
    private let grisTitulo = Color(red: 0.067, green: 0.094, blue: 0.153)     // #111827
    private let grisTexto = Color(red: 0.420, green: 0.440, blue: 0.500)      // #6B7280
    private let grisFondoQR = Color(red: 0.953, green: 0.957, blue: 0.965)    // #F3F4F6

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
        .background(fondoPantalla.ignoresSafeArea())
        .navigationDestination(isPresented: $mostrarAjustes) {
            AjustesView()
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
            // Cuadrado gris con ícono QR
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
            // Etiqueta de sección
            Text("ÚLTIMOS DATOS REGISTRADOS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(grisTexto)
                .padding(.leading, 4)

            // Tarjeta con lista
            VStack(spacing: 0) {
                ForEach(Array(signosMock.enumerated()), id: \.element.etiqueta) { index, signo in
                    VitalRowView(signo: signo, colores: (grisTitulo, grisTexto, grisFondoQR))

                    if index < signosMock.count - 1 {
                        Divider()
                            .background(fondoPantalla)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
        }
    }
}

// MARK: - Modelo Mock

private struct SignoVitalMock {
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
    let signo: SignoVitalMock
    /// (grisTitulo, grisTexto, grisFondo)
    let colores: (Color, Color, Color)

    var body: some View {
        HStack(spacing: 14) {
            // Ícono circular
            ZStack {
                Circle()
                    .fill(colores.2)
                    .frame(width: 40, height: 40)

                Image(systemName: signo.icono)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(signo.colorIcono)
            }

            // Etiqueta
            Text(signo.etiqueta)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colores.0)

            Spacer()

            // Valor + unidad + hora
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
    DashboardView()
}
