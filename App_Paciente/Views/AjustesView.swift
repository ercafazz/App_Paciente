//
//  AjustesView.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/2/26.
//

import SwiftUI
import Supabase

/// Pantalla de ajustes del paciente. Muestra el perfil, los médicos vinculados
/// y la opción de cerrar sesión. Corresponde a la Screen 7 del diseño de Tueri.
struct AjustesView: View {

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @AppStorage("isAuthenticated") var isAuthenticated = false
    @AppStorage("datosCompletados") var datosCompletados = false
    @AppStorage("permisosCompletados") var permisosCompletados = false
    @AppStorage("tutorialCompletado") var tutorialCompletado = false

    // MARK: - Estado (datos reales de Supabase)

    @State private var datosPerfil: [(etiqueta: String, valor: String)] = []
    @State private var medicosVinculados: [MedicoVinculado] = []
    @State private var isLoading = true

    // Estado para alerta de confirmación de desvinculación
    @State private var medicoADesvincular: MedicoVinculado?
    @State private var mostrarAlertaDesvincular = false
    @State private var desvinculando = false

    // MARK: - Estado de edición

    @State private var isEditing = false
    @State private var isSaving = false

    // Campos editables (temporales mientras se edita)
    @State private var editNombre = ""
    @State private var editTelefono = ""
    @State private var editCorreo = ""

    // Valores originales para detectar cambios
    @State private var originalNombre = ""
    @State private var originalTelefono = ""
    @State private var originalCorreo = ""

    // Campos bloqueados (solo lectura, siempre)
    @State private var displaySexo = "—"
    @State private var displayFechaNacimiento = "—"
    @State private var displayCedula = "—"

    // Alertas
    @State private var mostrarAlertaExito = false
    @State private var mostrarAlertaError = false
    @State private var mensajeAlerta = ""

    // Estado para eliminar cuenta
    @State private var mostrarAlertaEliminar = false
    @State private var eliminandoCuenta = false

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
                        .padding(.bottom, 12)
                    bloqueEliminarCuenta
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
        .alert("Desvincular medico", isPresented: $mostrarAlertaDesvincular) {
            Button("Cancelar", role: .cancel) {
                medicoADesvincular = nil
            }
            Button("Desvincular", role: .destructive) {
                guard let medico = medicoADesvincular else { return }
                Task {
                    await desvincularMedico(medico)
                }
            }
        } message: {
            if let medico = medicoADesvincular {
                Text("Deseas desvincular a \(medico.nombre)? Ya no podra monitorear tus signos vitales.")
            }
        }
        .alert("Cambios guardados", isPresented: $mostrarAlertaExito) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(mensajeAlerta)
        }
        .alert("Error", isPresented: $mostrarAlertaError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(mensajeAlerta)
        }
        .alert("Eliminar cuenta", isPresented: $mostrarAlertaEliminar) {
            Button("Cancelar", role: .cancel) { }
            Button("Eliminar", role: .destructive) {
                Task { await eliminarCuenta() }
            }
        } message: {
            Text("Esta accion es irreversible. Se borraran todos tus signos vitales y tu historial.")
        }
    }

    // MARK: - Barra de Navegacion Custom

    private var barraNavegacion: some View {
        ZStack {
            // Titulo centrado
            Text("Ajustes")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(grisTitulo)

            // Boton Volver a la izquierda
            HStack {
                Button {
                    if isEditing {
                        // Cancelar edicion y restaurar valores originales
                        cancelarEdicion()
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(isEditing ? "Cancelar" : "Volver")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .foregroundStyle(tealTueri)
                }

                Spacer()

                // Boton Editar / Guardar a la derecha
                if !isLoading {
                    if isEditing {
                        if isSaving {
                            ProgressView()
                                .tint(tealTueri)
                        } else {
                            Button {
                                Task { await guardarCambios() }
                            } label: {
                                Text("Guardar")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(tealTueri)
                            }
                            .disabled(!hayCambios)
                            .opacity(hayCambios ? 1.0 : 0.4)
                        }
                    } else {
                        Button {
                            iniciarEdicion()
                        } label: {
                            Text("Editar")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(tealTueri)
                        }
                    }
                }
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
                } else if isEditing {
                    // === MODO EDICION ===
                    perfilRowEditable(etiqueta: "Nombre", texto: $editNombre)
                    Divider().background(grisBorde).padding(.horizontal, 18)

                    perfilRowBloqueado(etiqueta: "Sexo", valor: displaySexo)
                    Divider().background(grisBorde).padding(.horizontal, 18)

                    perfilRowBloqueado(etiqueta: "Fecha de Nacimiento", valor: displayFechaNacimiento)
                    Divider().background(grisBorde).padding(.horizontal, 18)

                    perfilRowBloqueado(etiqueta: "Cedula", valor: displayCedula)
                    Divider().background(grisBorde).padding(.horizontal, 18)

                    perfilRowEditable(etiqueta: "Telefono", texto: $editTelefono, teclado: .phonePad)
                    Divider().background(grisBorde).padding(.horizontal, 18)

                    perfilRowEditable(etiqueta: "Correo", texto: $editCorreo, teclado: .emailAddress)

                } else {
                    // === MODO LECTURA ===
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

    // MARK: - Fila editable (TextField)

    private func perfilRowEditable(
        etiqueta: String,
        texto: Binding<String>,
        teclado: UIKeyboardType = .default
    ) -> some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 15))
                .foregroundStyle(grisTitulo)
                .frame(width: 80, alignment: .leading)

            Spacer()

            TextField(etiqueta, text: texto)
                .font(.system(size: 15))
                .foregroundStyle(grisTitulo)
                .multilineTextAlignment(.trailing)
                .keyboardType(teclado)
                .autocorrectionDisabled()
                .textInputAutocapitalization(
                    teclado == .emailAddress ? .never : .words
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    // MARK: - Fila bloqueada (solo lectura, estilo atenuado)

    private func perfilRowBloqueado(etiqueta: String, valor: String) -> some View {
        HStack {
            Text(etiqueta)
                .font(.system(size: 15))
                .foregroundStyle(grisTitulo)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(grisTexto.opacity(0.5))
                Text(valor)
                    .font(.system(size: 15))
                    .foregroundStyle(grisTexto.opacity(0.6))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(grisFondo.opacity(0.3))
    }

    // MARK: - Bloque 2: Medicos Vinculados

    private var bloqueMedicos: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Etiqueta de seccion
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
                    Text("Sin medicos vinculados")
                        .font(.system(size: 15))
                        .foregroundStyle(grisTexto)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(medicosVinculados.enumerated()), id: \.element.idMedico) { index, medico in
                        MedicoRowView(
                            nombre: medico.nombre,
                            telefono: medico.telefono,
                            desvinculando: desvinculando && medicoADesvincular?.idMedico == medico.idMedico,
                            teal: tealTueri,
                            grisFondo: grisFondo,
                            grisTitulo: grisTitulo,
                            grisTexto: grisTexto
                        ) {
                            medicoADesvincular = medico
                            mostrarAlertaDesvincular = true
                        }

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

    // MARK: - Bloque 3: Cerrar Sesion

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
                    print("[AjustesView] Sesion cerrada exitosamente.")
                } catch {
                    print("[AjustesView] Error al cerrar sesion: \(error.localizedDescription)")
                }
            }
        } label: {
            Text("Cerrar Sesion")
                .font(.system(size: 16))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Bloque 4: Eliminar Cuenta

    private var bloqueEliminarCuenta: some View {
        Button(role: .destructive) {
            mostrarAlertaEliminar = true
        } label: {
            HStack {
                if eliminandoCuenta {
                    ProgressView()
                        .tint(.red)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                    Text("Eliminar cuenta")
                        .font(.system(size: 16))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .disabled(eliminandoCuenta)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Eliminar cuenta via Edge Function

    private func eliminarCuenta() async {
        await MainActor.run { eliminandoCuenta = true }
        defer { Task { @MainActor in eliminandoCuenta = false } }

        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let token = session.accessToken

            guard let url = URL(
                string: "https://aqopgqcpdmbmgkxmgvoy.supabase.co/functions/v1/delete-user-account"
            ) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if (200...299).contains(http.statusCode) {
                print("[AjustesView] Cuenta eliminada exitosamente.")

                // Cerrar sesion local y limpiar estado
                try await SupabaseManager.shared.client.auth.signOut()
                HealthKitManager.shared.limpiarEstado()

                await MainActor.run {
                    isAuthenticated = false
                    datosCompletados = false
                    permisosCompletados = false
                    tutorialCompletado = false
                    dismiss()
                }
            } else {
                let respuesta = String(data: data, encoding: .utf8) ?? ""
                print("[AjustesView] Error al eliminar cuenta (HTTP \(http.statusCode)): \(respuesta)")
                await MainActor.run {
                    mensajeAlerta = "No se pudo eliminar la cuenta. Intenta de nuevo."
                    mostrarAlertaError = true
                }
            }

        } catch {
            print("[AjustesView] Error de red al eliminar cuenta: \(error.localizedDescription)")
            await MainActor.run {
                mensajeAlerta = "Error de conexion. Verifica tu internet e intenta de nuevo."
                mostrarAlertaError = true
            }
        }
    }

    // MARK: - Deteccion de cambios

    private var hayCambios: Bool {
        editNombre.trimmingCharacters(in: .whitespaces) != originalNombre ||
        editTelefono.trimmingCharacters(in: .whitespaces) != originalTelefono ||
        editCorreo.trimmingCharacters(in: .whitespaces) != originalCorreo
    }

    private var cambioNombre: Bool {
        editNombre.trimmingCharacters(in: .whitespaces) != originalNombre
    }

    private var cambioTelefono: Bool {
        editTelefono.trimmingCharacters(in: .whitespaces) != originalTelefono
    }

    private var cambioCorreo: Bool {
        editCorreo.trimmingCharacters(in: .whitespaces) != originalCorreo
    }

    // MARK: - Iniciar / Cancelar edicion

    private func iniciarEdicion() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
    }

    private func cancelarEdicion() {
        // Restaurar valores originales
        editNombre = originalNombre
        editTelefono = originalTelefono
        editCorreo = originalCorreo
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
    }

    // MARK: - Guardar cambios

    private func guardarCambios() async {
        guard hayCambios else { return }

        await MainActor.run { isSaving = true }
        defer { Task { @MainActor in isSaving = false } }

        var mensajes: [String] = []
        var huboError = false

        // 1. Si cambio nombre o telefono -> Edge Function
        if cambioNombre || cambioTelefono {
            do {
                let session = try await SupabaseManager.shared.client.auth.session
                let token = session.accessToken

                guard let url = URL(
                    string: "https://aqopgqcpdmbmgkxmgvoy.supabase.co/functions/v1/update-user-profile"
                ) else {
                    huboError = true
                    mensajes.append("URL de Edge Function invalida.")
                    return
                }

                var body: [String: String] = [:]
                if cambioNombre {
                    body["nombre_completo"] = editNombre.trimmingCharacters(in: .whitespaces)
                }
                if cambioTelefono {
                    body["telefono"] = editTelefono.trimmingCharacters(in: .whitespaces)
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 15
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if (200...299).contains(http.statusCode) {
                    // Actualizar valores originales localmente
                    if cambioNombre {
                        originalNombre = editNombre.trimmingCharacters(in: .whitespaces)
                    }
                    if cambioTelefono {
                        originalTelefono = editTelefono.trimmingCharacters(in: .whitespaces)
                    }
                    mensajes.append("Perfil actualizado correctamente.")
                    print("[AjustesView] Perfil actualizado via Edge Function.")
                } else {
                    let respuesta = String(data: data, encoding: .utf8) ?? ""
                    print("[AjustesView] Error al actualizar perfil (HTTP \(http.statusCode)): \(respuesta)")
                    huboError = true
                    mensajes.append("No se pudo actualizar el perfil.")
                }
            } catch {
                print("[AjustesView] Error de red al actualizar perfil: \(error.localizedDescription)")
                huboError = true
                mensajes.append("Error de conexion al actualizar el perfil.")
            }
        }

        // 2. Si cambio el correo -> Supabase Auth updateUser
        if cambioCorreo {
            do {
                let nuevoCorreo = editCorreo.trimmingCharacters(in: .whitespaces)
                try await SupabaseManager.shared.client.auth.update(
                    user: UserAttributes(email: nuevoCorreo)
                )
                originalCorreo = nuevoCorreo
                mensajes.append("Se envio un correo de confirmacion a \(nuevoCorreo). Revisa tu bandeja de entrada para completar el cambio.")
                print("[AjustesView] Cambio de correo solicitado a: \(nuevoCorreo)")
            } catch {
                print("[AjustesView] Error al cambiar correo: \(error.localizedDescription)")
                huboError = true
                mensajes.append("No se pudo actualizar el correo electronico.")
            }
        }

        // 3. Refrescar la lista de datos del perfil
        await refrescarDatosPerfil()

        // 4. Mostrar resultado
        await MainActor.run {
            mensajeAlerta = mensajes.joined(separator: "\n")
            if huboError {
                mostrarAlertaError = true
            } else {
                mostrarAlertaExito = true
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditing = false
                }
            }
        }
    }

    // MARK: - Carga de datos desde Supabase

    private func cargarDatos() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id

            // Queries en paralelo: perfil + medicos vinculados
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

            // Formatear sexo biologico
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
                ("Cedula",              perfil.cedula ?? "—"),
                ("Telefono",            perfil.telefono ?? "—"),
                ("Correo",              perfil.correoElectronico),
            ]

            let medicos = asignaciones.compactMap { asignacion -> MedicoVinculado? in
                guard let medicoData = asignacion.perfiles else { return nil }
                return MedicoVinculado(
                    idMedico: asignacion.idMedico,
                    nombre: medicoData.nombreCompleto ?? "—",
                    telefono: medicoData.telefono ?? "—"
                )
            }

            await MainActor.run {
                datosPerfil = datos
                medicosVinculados = medicos
                isLoading = false

                // Inicializar campos editables y sus originales
                editNombre = perfil.nombreCompleto
                originalNombre = perfil.nombreCompleto

                editTelefono = perfil.telefono ?? ""
                originalTelefono = perfil.telefono ?? ""

                editCorreo = perfil.correoElectronico
                originalCorreo = perfil.correoElectronico

                // Campos bloqueados
                displaySexo = sexoDisplay
                displayFechaNacimiento = fechaDisplay
                displayCedula = perfil.cedula ?? "—"
            }

            print("[AjustesView] Datos cargados. Medicos vinculados: \(medicos.count)")

        } catch {
            print("[AjustesView] Error: \(error.localizedDescription)")

            await MainActor.run {
                datosPerfil = [
                    ("Nombre", "—"), ("Sexo", "—"), ("Fecha de Nacimiento", "—"),
                    ("Cedula", "—"), ("Telefono", "—"), ("Correo", "—"),
                ]
                medicosVinculados = []
                isLoading = false
            }
        }
    }

    // MARK: - Refrescar datos del perfil (tras guardar)

    private func refrescarDatosPerfil() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id

            let perfil: PerfilRow = try await SupabaseManager.shared.client
                .from("perfiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            let sexoDisplay: String
            switch perfil.sexoBiologico?.lowercased() {
            case "masculino": sexoDisplay = "Masculino"
            case "femenino": sexoDisplay = "Femenino"
            default: sexoDisplay = perfil.sexoBiologico ?? "—"
            }

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
                ("Cedula",              perfil.cedula ?? "—"),
                ("Telefono",            perfil.telefono ?? "—"),
                ("Correo",              perfil.correoElectronico),
            ]

            await MainActor.run {
                datosPerfil = datos
                editNombre = perfil.nombreCompleto
                originalNombre = perfil.nombreCompleto
                editTelefono = perfil.telefono ?? ""
                originalTelefono = perfil.telefono ?? ""
                editCorreo = perfil.correoElectronico
                originalCorreo = perfil.correoElectronico
            }
        } catch {
            print("[AjustesView] Error al refrescar perfil: \(error.localizedDescription)")
        }
    }

    // MARK: - Desvinculacion via Edge Function

    private func desvincularMedico(_ medico: MedicoVinculado) async {
        desvinculando = true
        defer {
            Task { @MainActor in
                desvinculando = false
                medicoADesvincular = nil
            }
        }

        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let token = session.accessToken

            guard let url = URL(
                string: "https://aqopgqcpdmbmgkxmgvoy.supabase.co/functions/v1/desvincular-medico"
            ) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15

            let body = ["id_medico": medico.idMedico.uuidString]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else { return }

            if (200...299).contains(http.statusCode) {
                print("[AjustesView] Medico desvinculado: \(medico.nombre)")
                // Remover de la lista localmente (sin re-query)
                await MainActor.run {
                    medicosVinculados.removeAll { $0.idMedico == medico.idMedico }
                }
            } else {
                let respuesta = String(data: data, encoding: .utf8) ?? ""
                print("[AjustesView] Error desvinculando (HTTP \(http.statusCode)): \(respuesta)")
            }

        } catch {
            print("[AjustesView] Error de red: \(error.localizedDescription)")
        }
    }
}

// MARK: - Modelo de medico vinculado

private struct MedicoVinculado {
    let idMedico: UUID
    let nombre: String
    let telefono: String
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

/// Datos del medico obtenidos via FK join en la query de asignaciones.
private struct MedicoPerfilData: Codable {
    let nombreCompleto: String?
    let telefono: String?

    enum CodingKeys: String, CodingKey {
        case nombreCompleto = "nombre_completo"
        case telefono
    }
}

/// Fila de `asignaciones_clinicas` con join al perfil del medico.
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

/// Fila del bloque de medicos: icono + nombre/telefono + boton desvincular.
private struct MedicoRowView: View {
    let nombre: String
    let telefono: String
    let desvinculando: Bool
    let teal: Color
    let grisFondo: Color
    let grisTitulo: Color
    let grisTexto: Color
    let onDesvincular: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icono circular
            ZStack {
                Circle()
                    .fill(grisFondo)
                    .frame(width: 40, height: 40)

                Image(systemName: "stethoscope")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(teal)
            }

            // Nombre y telefono
            VStack(alignment: .leading, spacing: 2) {
                Text(nombre)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(grisTitulo)

                Text(telefono)
                    .font(.system(size: 12))
                    .foregroundStyle(grisTexto)
            }

            Spacer()

            // Boton desvincular
            if desvinculando {
                ProgressView()
                    .tint(.red)
            } else {
                Button(action: onDesvincular) {
                    Text("Desvincular")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                }
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
