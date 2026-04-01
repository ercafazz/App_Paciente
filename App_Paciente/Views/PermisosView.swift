//
//  PermisosView.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/1/26.
//

import SwiftUI

/// Pantalla de onboarding que explica al paciente por qué necesitamos acceder
/// a sus datos de salud y solicita permisos de lectura en HealthKit.
/// Corresponde a la Screen 4 del diseño de Tuēri.
struct PermisosView: View {

    // MARK: - Estado

    /// Binding al flujo de onboarding. Se pone en `true` cuando los permisos se solicitan exitosamente.
    @Binding var permisosCompletados: Bool

    @State private var estaCargando = false
    @State private var mostrarAlerta = false
    @State private var mensajeError = ""

    // MARK: - Colores del diseño

    private let tealTueri = Color(red: 0.051, green: 0.424, blue: 0.471)     // #0D6C78
    private let grisTexto = Color(red: 0.420, green: 0.440, blue: 0.500)      // #6B7280
    private let grisTitulo = Color(red: 0.122, green: 0.161, blue: 0.216)     // #1F2937
    private let grisBorde = Color(red: 0.898, green: 0.906, blue: 0.929)      // #E5E7EB

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            ScrollView {
                VStack(spacing: 0) {

                    // ── Branding ──
                    encabezado

                    // ── Ilustración Apple Watch ──
                    ilustracionReloj
                        .padding(.bottom, 28)

                    // ── Título y descripción ──
                    textoExplicativo
                        .padding(.bottom, 28)

                    // ── Lista de permisos ──
                    listaPermisos
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // ── Botón principal ──
            botonConectar
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .background(Color.white)
        .alert("Error", isPresented: $mostrarAlerta) {
            Button("Entendido", role: .cancel) { }
        } message: {
            Text(mensajeError)
        }
    }

    // MARK: - Subvistas

    /// Branding superior: logo y tagline.
    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image("TueriLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .padding(.bottom, 4)

            Text("Tuēri")
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(grisTitulo)

            Text("Cuidamos de ti, estés donde estés.")
                .font(.system(size: 16))
                .foregroundStyle(grisTexto)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }

    /// Ilustración central: Apple Watch estilizado con corazón.
    private var ilustracionReloj: some View {
        ZStack {
            // Cuerpo del reloj
            RoundedRectangle(cornerRadius: 20)
                .stroke(grisTitulo, lineWidth: 3)
                .frame(width: 100, height: 130)

            // Correa superior
            RoundedRectangle(cornerRadius: 6)
                .fill(grisTitulo)
                .frame(width: 44, height: 22)
                .offset(y: -76)

            // Correa inferior
            RoundedRectangle(cornerRadius: 6)
                .fill(grisTitulo)
                .frame(width: 44, height: 22)
                .offset(y: 76)

            // Corona (Digital Crown)
            RoundedRectangle(cornerRadius: 2)
                .fill(grisTitulo)
                .frame(width: 6, height: 22)
                .offset(x: 53)

            // Corazón central
            Image(systemName: "heart.fill")
                .font(.system(size: 38))
                .foregroundStyle(tealTueri)
        }
        .frame(height: 180)
    }

    /// Título principal y texto explicativo.
    private var textoExplicativo: some View {
        VStack(spacing: 10) {
            Text("Para cuidarte mejor, necesitamos conectarnos")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(grisTitulo)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Tu médico usa los datos de tu Apple Watch para monitorear tus signos vitales. En el siguiente paso, te pediremos autorización para leer:")
                .font(.system(size: 14))
                .foregroundStyle(grisTexto)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Lista visual de los tres permisos requeridos.
    private var listaPermisos: some View {
        VStack(spacing: 0) {
            filaPermiso(
                icono: "heart.fill",
                color: .red,
                texto: "Frecuencia Cardíaca"
            )

            Divider()
                .background(grisBorde)

            filaPermiso(
                icono: "drop.fill",
                color: Color(red: 0.94, green: 0.33, blue: 0.31),   // rojo suave
                texto: "Saturación de Oxígeno — SpO₂"
            )

            Divider()
                .background(grisBorde)

            filaPermiso(
                icono: "wind",
                color: Color(red: 0.0, green: 0.65, blue: 0.88),    // sky-500
                texto: "Frecuencia Respiratoria"
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(grisBorde, lineWidth: 1)
        )
    }

    /// Fila individual de permiso con ícono y texto.
    private func filaPermiso(icono: String, color: Color, texto: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icono)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 28, alignment: .center)

            Text(texto)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(grisTitulo)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    /// Botón principal que solicita permisos de HealthKit.
    private var botonConectar: some View {
        Button {
            Task {
                await solicitarPermisos()
            }
        } label: {
            Group {
                if estaCargando {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Conectar Apple Watch")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(tealTueri)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(estaCargando)
    }

    // MARK: - Lógica

    /// Solicita permisos de HealthKit y navega al siguiente paso si tiene éxito.
    private func solicitarPermisos() async {
        estaCargando = true
        defer { estaCargando = false }

        do {
            try await HealthKitManager.shared.solicitarPermisos()

            // Permisos solicitados exitosamente → avanzar en el onboarding
            permisosCompletados = true

        } catch HealthKitManagerError.healthKitNoDisponible {
            mensajeError = "HealthKit no está disponible en este dispositivo. Tuēri requiere un iPhone con Apple Watch vinculado."
            mostrarAlerta = true

        } catch {
            mensajeError = "No se pudieron solicitar los permisos: \(error.localizedDescription)"
            mostrarAlerta = true
        }
    }
}

// MARK: - Preview

#Preview {
    PermisosView(permisosCompletados: .constant(false))
}
