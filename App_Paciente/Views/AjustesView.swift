//
//  AjustesView.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/2/26.
//

import SwiftUI
import Supabase
/// Pantalla de ajustes del paciente. Muestra el perfil, los médicos vinculados
/// y la opción de cerrar sesión. Corresponde a la Screen 7 del diseño de Tuēri.
struct AjustesView: View {

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @AppStorage("isAuthenticated") var isAuthenticated = false

    // MARK: - Datos Mock

    private let datosPerfil: [(etiqueta: String, valor: String)] = [
        ("Nombre",              "Ernesto Apellido"),
        ("Sexo",                "Masculino"),
        ("Fecha de Nacimiento", "DD/MM/AAAA"),
        ("Cédula",              "V-12345678"),
        ("Teléfono",            "+58 XXX-XXXXXXX"),
        ("Correo",              "correo@ejemplo.com"),
    ]

    private let medicosMock: [(nombre: String, telefono: String)] = [
        ("Nombre Apellido", "+58 XXX-XXXXXXX"),
        ("Nombre Apellido", "+58 XXX-XXXXXXX"),
    ]

    // MARK: - Colores

    private let tealTueri = Color(red: 0.051, green: 0.424, blue: 0.471)
    private let fondoPantalla = Color(red: 0.953, green: 0.957, blue: 0.965)
    private let grisTitulo = Color(red: 0.067, green: 0.094, blue: 0.153)
    private let grisTexto = Color(red: 0.420, green: 0.440, blue: 0.500)
    private let grisFondo = Color(red: 0.945, green: 0.949, blue: 0.957)
    private let grisBorde = Color(red: 0.953, green: 0.957, blue: 0.965)

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            barraNavegacion
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    bloquePerfil
                        .padding(.bottom, 24)
                    bloqueMedicos
                        .padding(.bottom, 24)
                    bloqueCerrarSesion
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(fondoPantalla.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    // MARK: - Barra de Navegación Custom

    private var barraNavegacion: some View {
        ZStack {
            // Título centrado
            Text("Ajustes")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(grisTitulo)

            // Botón Volver a la izquierda
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Volver")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .foregroundStyle(tealTueri)
                }

                Spacer()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
    }

    // MARK: - Bloque 1: Perfil

    private var bloquePerfil: some View {
        VStack(spacing: 0) {
            // Avatar
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(grisFondo)
                        .frame(width: 64, height: 64)

                    Image(systemName: "person")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(grisTexto)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 14)

            // Filas de datos
            VStack(spacing: 0) {
                ForEach(Array(datosPerfil.enumerated()), id: \.element.etiqueta) { index, dato in
                    PerfilRowView(
                        etiqueta: dato.etiqueta,
                        valor: dato.valor,
                        colorTitulo: grisTitulo,
                        colorValor: grisTexto
                    )

                    if index < datosPerfil.count - 1 {
                        Divider()
                            .background(grisBorde)
                            .padding(.horizontal, 18)
                    }
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Bloque 2: Médicos Vinculados

    private var bloqueMedicos: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Etiqueta de sección
            Text("PERSONAL DE SALUD VINCULADO")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(grisTexto)
                .padding(.leading, 4)

            // Tarjeta
            VStack(spacing: 0) {
                ForEach(Array(medicosMock.enumerated()), id: \.offset) { index, medico in
                    MedicoRowView(
                        nombre: medico.nombre,
                        telefono: medico.telefono,
                        teal: tealTueri,
                        grisFondo: grisFondo,
                        grisTitulo: grisTitulo,
                        grisTexto: grisTexto
                    )

                    if index < medicosMock.count - 1 {
                        Divider()
                            .background(grisBorde)
                            .padding(.horizontal, 18)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Bloque 3: Cerrar Sesión

    private var bloqueCerrarSesion: some View {
        Button {
            Task {
                do {
                    try await SupabaseManager.shared.client.auth.signOut()
                    isAuthenticated = false
                    dismiss()
                    print("[AjustesView] ✅ Sesión cerrada exitosamente.")
                } catch {
                    print("[AjustesView] ❌ Error al cerrar sesión: \(error.localizedDescription)")
                }
            }
        } label: {
            Text("Cerrar Sesión")
                .font(.system(size: 16))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - PerfilRowView

/// Fila del bloque de perfil: etiqueta a la izquierda, valor a la derecha.
private struct PerfilRowView: View {
    let etiqueta: String
    let valor: String
    let colorTitulo: Color
    let colorValor: Color

    var body: some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 15))
                .foregroundStyle(colorTitulo)

            Spacer()

            Text(valor)
                .font(.system(size: 15))
                .foregroundStyle(colorValor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

// MARK: - MedicoRowView

/// Fila del bloque de médicos: ícono + nombre/teléfono + botón desvincular.
private struct MedicoRowView: View {
    let nombre: String
    let telefono: String
    let teal: Color
    let grisFondo: Color
    let grisTitulo: Color
    let grisTexto: Color

    var body: some View {
        HStack(spacing: 12) {
            // Ícono circular
            ZStack {
                Circle()
                    .fill(grisFondo)
                    .frame(width: 40, height: 40)

                Image(systemName: "stethoscope")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(teal)
            }

            // Nombre y teléfono
            VStack(alignment: .leading, spacing: 2) {
                Text(nombre)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(grisTitulo)

                Text(telefono)
                    .font(.system(size: 12))
                    .foregroundStyle(grisTexto)
            }

            Spacer()

            // Botón desvincular
            Button {
                // TODO: Implementar desvinculación del médico
                print("[AjustesView] Desvincular: \(nombre)")
            } label: {
                Text("Desvincular")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AjustesView()
    }
}
