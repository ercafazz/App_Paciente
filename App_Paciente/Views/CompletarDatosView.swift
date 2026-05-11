//
//  CompletarDatosView.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/2/26.
//

import SwiftUI
import Supabase
import Auth
import PostgREST

// MARK: - Modelo para INSERT en tabla `perfiles`

/// Estructura que mapea exactamente a las columnas de la tabla `perfiles` en Supabase.
/// Solo se usa para el INSERT inicial tras el registro, por eso conforma a `Encodable`.
struct PerfilInsert: Encodable {
    let id: UUID
    let rol: String
    let nombreCompleto: String
    let correoElectronico: String
    let cedula: String
    let telefono: String
    let fechaNacimiento: String
    let sexoBiologico: String

    enum CodingKeys: String, CodingKey {
        case id
        case rol
        case nombreCompleto = "nombre_completo"
        case correoElectronico = "correo_electronico"
        case cedula
        case telefono
        case fechaNacimiento = "fecha_nacimiento"
        case sexoBiologico = "sexo_biologico"
    }
}

/// Pantalla de onboarding para capturar los datos demográficos y médicos
/// del paciente tras el registro. Corresponde a la Screen 3 del diseño de Tuēri.
struct CompletarDatosView: View {

    // MARK: - Sexo biológico

    private enum SexoBiologico: String, CaseIterable {
        case masculino = "Masculino"
        case femenino = "Femenino"
    }

    // MARK: - Tipo de cédula (nacionalidad)

    /// Prefijo de la cédula venezolana/extranjera. El `rawValue` es el
    /// carácter que se concatena antes del número al enviar a Supabase
    /// (ej. "V-12345678", "E-87654321").
    private enum TipoCedula: String, CaseIterable, Identifiable {
        case venezolano = "V"
        case extranjero = "E"

        var id: String { rawValue }

        /// Etiqueta larga para el menú desplegable.
        var descripcion: String {
            switch self {
            case .venezolano: return "Venezolano"
            case .extranjero: return "Extranjero"
            }
        }
    }

    // MARK: - Bindings

    /// Notifica al flujo principal que el paciente completó sus datos.
    @Binding var datosCompletados: Bool

    // MARK: - Estado del formulario

    @State private var tipoCedula: TipoCedula = .venezolano
    @State private var cedula = ""
    /// Pre-cargado con "+58 " (código de Venezuela, mercado principal hoy).
    /// El "+" es obligatorio en E.164; el espacio es solo cosmético — se
    /// elimina al persistir vía `TelefonoValidator.toCanonicalE164`.
    @State private var telefono = "+58 "
    @State private var dia = ""
    @State private var mes = ""
    @State private var anio = ""
    @State private var sexoSeleccionado: SexoBiologico?
    @State private var isSubmitting = false
    @State private var nombreUsuario = "Usuario"

    // Alertas
    @State private var mostrarAlertaError = false
    @State private var mensajeError = ""

    // MARK: - Colores del diseño

    private let tealTueri = Color(red: 0.051, green: 0.424, blue: 0.471)
    private let grisTexto = Color(red: 0.420, green: 0.440, blue: 0.500)
    private let grisTitulo = Color(red: 0.122, green: 0.161, blue: 0.216)
    private let grisBorde = Color(red: 0.898, green: 0.906, blue: 0.929)
    private let grisFondoCampo = Color(red: 0.969, green: 0.973, blue: 0.980)
    private let grisFondoSegmento = Color(red: 0.945, green: 0.949, blue: 0.957)

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                encabezado
                seccionTitulo
                    .padding(.bottom, 28)
                formulario
                    .padding(.bottom, 28)
                botonCompletar
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.white)
        .alert("Error", isPresented: $mostrarAlertaError) {
            Button("Entendido", role: .cancel) { }
        } message: {
            Text(mensajeError)
        }
        .task {
            await cargarNombreUsuario()
        }
    }

    // MARK: - Encabezado (Logo + Branding)

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image("TueriLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .padding(.bottom, 4)

            Text("Tuēri")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(grisTitulo)

            Text("Cuidamos de ti, estés donde estés.")
                .font(.system(size: 16))
                .foregroundStyle(grisTexto)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Título de sección

    private var seccionTitulo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("¡Casi listo, \(nombreUsuario)!")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(grisTitulo)

            Text("Para que tu médico pueda monitorearte con precisión, necesitamos algunos datos adicionales.")
                .font(.system(size: 14))
                .foregroundStyle(grisTexto)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Formulario

    private var formulario: some View {
        VStack(spacing: 20) {
            campoCedula
            campoTelefono
            campoFechaNacimiento
            campoSexoBiologico
        }
    }

    // ── Cédula ──

    private var campoCedula: some View {
        VStack(alignment: .leading, spacing: 8) {
            etiqueta("CÉDULA DE IDENTIDAD")

            HStack(spacing: 10) {
                // ── Selector V / E ──
                // `Menu` muestra un popover nativo con las dos opciones.
                // En el label solo se ve la letra seleccionada (V o E)
                // + chevron, imitando el diseño de referencia.
                Menu {
                    ForEach(TipoCedula.allCases) { opcion in
                        Button {
                            tipoCedula = opcion
                        } label: {
                            if tipoCedula == opcion {
                                Label(opcion.descripcion, systemImage: "checkmark")
                            } else {
                                Text(opcion.descripcion)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(tipoCedula.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(grisTitulo)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(grisTexto)
                    }
                    .frame(width: 64, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tealTueri, lineWidth: 1.5)
                    )
                }
                .accessibilityLabel("Tipo de cédula")
                .accessibilityHint("Selecciona V para venezolano o E para extranjero")

                // ── Input numérico ──
                // `onChange` filtra cualquier carácter no numérico para
                // que el valor persistido sea exclusivamente dígitos.
                // El prefijo "V-"/"E-" se añade al enviar a Supabase.
                TextField("12439016", text: $cedula)
                    .font(.system(size: 15))
                    .foregroundStyle(grisTitulo)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .background(grisFondoCampo)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: cedula) { _, newValue in
                        let soloDigitos = newValue.filter(\.isNumber)
                        if soloDigitos != newValue {
                            cedula = soloDigitos
                        }
                    }
            }
        }
    }

    // ── Teléfono ──

    private var campoTelefono: some View {
        VStack(alignment: .leading, spacing: 8) {
            etiqueta("TELÉFONO DE CONTACTO")

            TextField("+58 412 1234567", text: $telefono)
                .font(.system(size: 15))
                .foregroundStyle(grisTitulo)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(grisFondoCampo)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .autocorrectionDisabled()

            // Error inline — solo se muestra si el usuario tocó el campo
            // (ya escribió algo distinto al prefijo por defecto) y aún no
            // cumple E.164. Evita mostrar rojo apenas se abre la pantalla.
            if mostrarErrorTelefono {
                Text("Formato inválido. Usa el código de país. Ejemplo: +58 412 1234567")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Solo se muestra el mensaje rojo si el usuario ya editó el campo
    /// (no está exactamente en "+58 ") y el valor actual no es E.164.
    private var mostrarErrorTelefono: Bool {
        let trimmed = telefono.trimmingCharacters(in: .whitespaces)
        guard trimmed != "+58" && !trimmed.isEmpty else { return false }
        return !TelefonoValidator.isE164Valid(telefono)
    }

    // ── Fecha de Nacimiento (Día / Mes / Año) ──

    private var campoFechaNacimiento: some View {
        VStack(alignment: .leading, spacing: 8) {
            etiqueta("FECHA DE NACIMIENTO")

            HStack(spacing: 0) {
                // Día
                campoFechaSegmento(
                    placeholder: "Día",
                    texto: $dia,
                    maxDigitos: 2
                )

                separadorFecha

                // Mes
                campoFechaSegmento(
                    placeholder: "Mes",
                    texto: $mes,
                    maxDigitos: 2
                )

                separadorFecha

                // Año
                campoFechaSegmento(
                    placeholder: "Año",
                    texto: $anio,
                    maxDigitos: 4
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func campoFechaSegmento(
        placeholder: String,
        texto: Binding<String>,
        maxDigitos: Int
    ) -> some View {
        TextField(placeholder, text: texto)
            .font(.system(size: 15))
            .foregroundStyle(grisTitulo)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(grisFondoCampo)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .keyboardType(.numberPad)
            .autocorrectionDisabled()
            .onChange(of: texto.wrappedValue) { _, newValue in
                let soloDigitos = String(newValue.filter(\.isNumber).prefix(maxDigitos))
                if soloDigitos != newValue {
                    texto.wrappedValue = soloDigitos
                }
            }
    }

    private var separadorFecha: some View {
        Text("/")
            .font(.system(size: 18, weight: .light))
            .foregroundStyle(grisTexto)
            .padding(.horizontal, 8)
    }

    // ── Sexo Biológico ──

    private var campoSexoBiologico: some View {
        VStack(alignment: .leading, spacing: 8) {
            etiqueta("SEXO BIOLÓGICO")

            HStack(spacing: 4) {
                ForEach(SexoBiologico.allCases, id: \.self) { opcion in
                    botonSexo(opcion)
                }
            }
            .padding(4)
            .background(grisFondoSegmento)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func botonSexo(_ opcion: SexoBiologico) -> some View {
        let activo = sexoSeleccionado == opcion

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                sexoSeleccionado = opcion
            }
        } label: {
            Text(opcion.rawValue)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(activo ? grisTitulo : grisTexto)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if activo {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Botón Completar Perfil

    private var botonCompletar: some View {
        Button {
            Task {
                await guardarDatos()
            }
        } label: {
            Group {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Completar Perfil")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(tealTueri)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isSubmitting || !formularioValido)
        .opacity(formularioValido ? 1.0 : 0.6)
    }

    // MARK: - Componentes auxiliares

    private func etiqueta(_ texto: String) -> some View {
        Text(texto)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(grisTexto)
    }

    // MARK: - Validación

    private var formularioValido: Bool {
        let cedulaValida = !cedula.trimmingCharacters(in: .whitespaces).isEmpty
        // El teléfono se considera válido SOLO si cumple E.164 estricto —
        // misma regla que App_Medico, para que el botón "Llamar" del médico
        // funcione siempre con `tel:<telefono>`.
        let telefonoValido = TelefonoValidator.isE164Valid(telefono)
        let fechaValida = !dia.isEmpty && !mes.isEmpty && !anio.isEmpty && anio.count == 4
        let sexoValido = sexoSeleccionado != nil

        return cedulaValida && telefonoValido && fechaValida && sexoValido
    }

    // MARK: - Carga del nombre del usuario (blindada)

    /// Resuelve el primer nombre del usuario probando varias fuentes de metadata.
    ///
    /// **Por qué es tan defensivo**:
    /// La lectura anterior fallaba en un caso puntual — usuario recién
    /// registrado con email/password — porque terminaba con `nombre_completo = ""`
    /// en el JWT. El valor llegaba vacío por una combinación de:
    ///
    ///   1. Los claims OIDC que Supabase pobla automáticamente cuando el
    ///      proveedor es Google (`full_name`, `name`, `given_name`, `picture`)
    ///      NO existen para email/password → cualquier normalización backend
    ///      (trigger `handle_new_user` que copia `full_name → nombre_completo`,
    ///      por ejemplo) termina con string vacío.
    ///   2. El código original no filtraba el caso string-vacío-pero-presente:
    ///      `"".components(separatedBy: " ").first == ""` → el saludo quedaba
    ///      como "¡Casi listo, !".
    ///
    /// Estrategia actual — probar en orden y quedarse con el primer candidato
    /// NO vacío:
    ///   · `nombre_completo`  (lo que mete nuestro signUp manual)
    ///   · `full_name`        (lo que mete Google OIDC)
    ///   · `name`             (fallback de Google OIDC)
    ///   · prefijo del email  (último recurso: "juan@mail.com" → "Juan")
    ///   · "Usuario"          (valor hardcodeado por si TODO falla)
    private func cargarNombreUsuario() async {
        guard let session = try? await SupabaseManager.shared.client.auth.session else {
            print("[CompletarDatosView] ⚠️ Sin sesión al cargar nombreUsuario.")
            return
        }

        let meta = session.user.userMetadata

        // 🔍 DIAGNÓSTICO TEMPORAL — borra este bloque cuando confirmes la causa.
        // Imprime TODO lo que venga en userMetadata para comparar flujos
        // (email/password vs Google) y saber qué clave contiene el nombre.
        print("[CompletarDatosView] 🔍 userMetadata dump:")
        print("   provider (app_metadata): \(session.user.appMetadata["provider"]?.stringValue ?? "?")")
        print("   email: \(session.user.email ?? "?")")
        print("   claves en userMetadata: \(Array(meta.keys).sorted())")
        for (clave, valor) in meta {
            print("     · \(clave) = \(valor)")
        }

        // Candidatos en orden de preferencia. Se filtran strings vacíos/whitespace.
        let candidatos: [String?] = [
            meta["nombre_completo"]?.stringValue,
            meta["full_name"]?.stringValue,
            meta["name"]?.stringValue,
            session.user.email.flatMap { email in
                email.split(separator: "@").first.map { String($0).capitalized }
            }
        ]

        let nombreCrudo = candidatos
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let nombre = nombreCrudo else {
            print("[CompletarDatosView] ⚠️ Ningún candidato de nombre disponible. Usando default.")
            return
        }

        // Extraer el primer token no vacío (blindado contra espacios duplicados).
        let primerNombre = nombre
            .components(separatedBy: " ")
            .first { !$0.isEmpty } ?? nombre

        await MainActor.run {
            nombreUsuario = primerNombre
        }
        print("[CompletarDatosView] 👤 Saludo resuelto como: \(primerNombre)")
    }

    // MARK: - Lógica (Supabase INSERT)

    /// Obtiene la sesión actual, construye el perfil y lo inserta en la tabla `perfiles`.
    private func guardarDatos() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            // 1. Obtener sesión y datos del usuario autenticado
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id
            let email = session.user.email ?? ""

            // 2. Resolver el nombre desde userMetadata con fallback chain.
            //    · email+password → lo guardamos en `nombre_completo` al hacer signUp.
            //    · Google OAuth → viene en `full_name` / `name` / `given_name`.
            //    · Último recurso: prefijo del email capitalizado.
            let meta = session.user.userMetadata
            let candidatos: [String?] = [
                meta["nombre_completo"]?.stringValue,
                meta["full_name"]?.stringValue,
                meta["name"]?.stringValue,
                meta["given_name"]?.stringValue,
            ]
            let nombreResuelto = candidatos
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty })

            let nombre: String
            if let nombreResuelto {
                nombre = nombreResuelto
            } else if let prefijo = email.split(separator: "@").first, !prefijo.isEmpty {
                nombre = prefijo.prefix(1).uppercased() + prefijo.dropFirst()
            } else {
                nombre = "Paciente"
            }

            // 3. Formatear fecha a YYYY-MM-DD (requerido por SQL date)
            let diaPad = dia.count == 1 ? "0\(dia)" : dia
            let mesPad = mes.count == 1 ? "0\(mes)" : mes
            let fechaFormateada = "\(anio)-\(mesPad)-\(diaPad)"

            // 4. Construir el perfil
            //    La cédula se envía con el prefijo de nacionalidad:
            //      · Venezolano → "V-12345678"
            //      · Extranjero → "E-12345678"
            //    El input solo captura dígitos; el prefijo lo añadimos aquí.
            let cedulaNumerica = cedula.trimmingCharacters(in: .whitespaces)
            let cedulaConPrefijo = "\(tipoCedula.rawValue)-\(cedulaNumerica)"

            // Persistir SIEMPRE la versión canónica E.164 (sin espacios,
            // sin guiones, sin paréntesis). `formularioValido` ya garantiza
            // que `toCanonicalE164` no será nil, pero blindamos con guard
            // para que el INSERT nunca lleve un teléfono malformado.
            guard let telefonoCanonico = TelefonoValidator.toCanonicalE164(telefono) else {
                mensajeError = "Número de teléfono inválido. Usa el formato internacional, ej. +58 412 1234567."
                mostrarAlertaError = true
                return
            }

            let perfilInsert = PerfilInsert(
                id: userId,
                rol: "paciente",
                nombreCompleto: nombre,
                correoElectronico: email,
                cedula: cedulaConPrefijo,
                telefono: telefonoCanonico,
                fechaNacimiento: fechaFormateada,
                sexoBiologico: sexoSeleccionado?.rawValue ?? ""
            )

            // 5. INSERT en Supabase
            try await SupabaseManager.shared.client
                .from("perfiles")
                .insert(perfilInsert)
                .execute()

            print("[CompletarDatosView] ✅ Perfil insertado en Supabase:")
            print("  ID: \(userId)")
            print("  Nombre: \(nombre)")
            print("  Cédula: \(cedulaConPrefijo)")
            print("  Fecha: \(fechaFormateada)")
            print("  Sexo: \(sexoSeleccionado?.rawValue ?? "N/A")")

            // 6. Avanzar en el onboarding (MainActor ya que estamos en contexto de View)
            await MainActor.run {
                datosCompletados = true
            }

        } catch {
            let descripcion = error.localizedDescription.lowercased()

            if descripcion.contains("duplicate") || descripcion.contains("already exists")
                || descripcion.contains("unique") {
                mensajeError = "Ya existe un perfil con esta cédula. Si crees que es un error, contacta a soporte."
            } else if descripcion.contains("network") || descripcion.contains("offline") {
                mensajeError = "Sin conexión a internet. Verifica tu red e intenta de nuevo."
            } else {
                mensajeError = "No se pudo guardar el perfil: \(error.localizedDescription)"
            }

            mostrarAlertaError = true
            print("[CompletarDatosView] ❌ Error al insertar perfil: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    CompletarDatosView(datosCompletados: .constant(false))
}
