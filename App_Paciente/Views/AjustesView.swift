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
    @AppStorage("datosCompletados") var datosCompletados = false
    @AppStorage("permisosCompletados") var permisosCompletados = false
    @AppStorage("tutorialCompletado") var tutorialCompletado = false

    // MARK: - Estado (datos reales de Supabase)

    @State private var datosPerfil: [(etiqueta: String, valor: String)] = []
    @State private var medicosVinculados: [(nombre: String, telefono: String)] = []
    @State private var isLoading = true

    // MARK: - Colores

    private let tealTueri = Color(red: 0.051, green: 0.424, blue: 0.471)
    private let fondoPantalla = Color(red: 0.953, green: 0.957, blue: 0.965)
    private let grisTitulo = Color(red: 0.067, green: 0.094, blue: 0.153)
    private let grisTexto = Color(red: 0.420, green: 0.440, blue: 0.500)
    private let grisFondo = Color(red: 0.945, green: 0.949, blue: 0.957)
    private let grisBorde = Color(red: 0.953, green: 0.957, blue: 0.965)

    // MARK: - Formateador de fecha

    private static let formateadorFechaNacimiento: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    private static let parserFechaNacimiento: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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
        .task {
            await cargarDatos()
        }
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
                if isLoading {
                    ProgressView()
                        .tint(tealTueri)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
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
                if isLoading {
                    ProgressView()
                        .tint(tealTueri)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else if medicosVinculados.isEmpty {
                    Text("Sin médicos vinculados")
                        .font(.system(size: 15))
                        .foregroundStyle(grisTexto)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(medicosVinculados.enumerated()), id: \.offset) { index, medico in
                        MedicoRowView(
                            nombre: medico.nombre,
                            telefono: medico.telefono,
                            teal: tealTueri,
                            grisFondo: grisFondo,
                            grisTitulo: grisTitulo,
                            grisTexto: grisTexto
                        )

                        if index < medicosVinculados.count - 1 {
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
    }

    // MARK: - Bloque 3: Cerrar Sesión

    private var bloqueCerrarSesion: some View {
        Button {
            Task {
                do {
                    try await SupabaseManager.shared.client.auth.signOut()
                    HealthKitManager.shared.limpiarEstado()
                    isAuthenticated = false
                    datosCompletados = false
                    permisosCompletados = false
                    tutorialCompletado = false
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

    // MARK: - Carga de datos desde Supabase

    private func cargarDatos() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id

            // Queries en paralelo: perfil + médicos vinculados
            async let perfilQuery: PerfilRow = SupabaseManager.shared.client
                .from("perfiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            async let medicosQuery: [AsignacionConMedico] = SupabaseManager.shared.client
                .from("asignaciones_clinicas")
                .select("id_medico, perfiles!asignaciones_clinicas_id_medico_fkey(nombre_completo, telefono)")
                .eq("id_paciente", value: userId)
                .eq("estado", value: "activo")
                .execute()
                .value

            let perfil = try await perfilQuery
            let asignaciones = try await medicosQuery

            // Formatear sexo biológico
            let sexoDisplay: String
            switch perfil.sexoBiologico?.lowercased() {
            case "masculino": sexoDisplay = "Masculino"
            case "femenino": sexoDisplay = "Femenino"
            default: sexoDisplay = perfil.sexoBiologico ?? "—"
            }

            // Formatear fecha de nacimiento
            let fechaDisplay: String
            if let fechaStr = perfil.fechaNacimiento,
               let fecha = Self.parserFechaNacimiento.date(from: fechaStr) {
                fechaDisplay = Self.formateadorFechaNacimiento.string(from: fecha)
            } else {
                fechaDisplay = "—"
            }

            let datos: [(etiqueta: String, valor: String)] = [
                ("Nombre",              perfil.nombreCompleto),
                ("Sexo",                sexoDisplay),
                ("Fecha de Nacimiento", fechaDisplay),
                ("Cédula",              perfil.cedula ?? "—"),
                ("Teléfono",            perfil.telefono ?? "—"),
                ("Correo",              perfil.correoElectronico),
            ]

            let medicos = asignaciones.compactMap { asignacion -> (nombre: String, telefono: String)? in
                guard let medicoData = asignacion.perfiles else { return nil }
                return (
                    nombre: medicoData.nombreCompleto ?? "—",
                    telefono: medicoData.telefono ?? "—"
                )
            }

            await MainActor.run {
                datosPerfil = datos
                medicosVinculados = medicos
                isLoading = false
            }

            print("[AjustesView] ✅ Datos cargados. Médicos vinculados: \(medicos.count)")

        } catch {
            print("[AjustesView] ❌ Error: \(error.localizedDescription)")

            await MainActor.run {
                datosPerfil = [
                    ("Nombre", "—"), ("Sexo", "—"), ("Fecha de Nacimiento", "—"),
                    ("Cédula", "—"), ("Teléfono", "—"), ("Correo", "—"),
                ]
                medicosVinculados = []
                isLoading = false
            }
        }
    }
}

// MARK: - Modelos Codable para Supabase

/// Fila de la tabla `perfiles`.
private struct PerfilRow: Codable {
    let nombreCompleto: String
    let sexoBiologico: String?
    let fechaNacimiento: String?
    let cedula: String?
    let telefono: String?
    let correoElectronico: String

    enum CodingKeys: String, CodingKey {
        case nombreCompleto = "nombre_completo"
        case sexoBiologico = "sexo_biologico"
        case fechaNacimiento = "fecha_nacimiento"
        case cedula
        case telefono
        case correoElectronico = "correo_electronico"
    }
}

/// Datos del médico obtenidos vía FK join en la query de asignaciones.
private struct MedicoPerfilData: Codable {
    let nombreCompleto: String?
    let telefono: String?

    enum CodingKeys: String, CodingKey {
        case nombreCompleto = "nombre_completo"
        case telefono
    }
}

/// Fila de `asignaciones_clinicas` con join al perfil del médico.
private struct AsignacionConMedico: Codable {
    let idMedico: UUID
    let perfiles: MedicoPerfilData?

    enum CodingKeys: String, CodingKey {
        case idMedico = "id_medico"
        case perfiles
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
