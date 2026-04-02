//
//  AutenticacionView.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/1/26.
//

import SwiftUI

/// Pantalla unificada de autenticación que combina Inicio de Sesión y Registro
/// en un solo componente con pestañas interactivas.
/// Corresponde a las Screens 1 y 2 del diseño de Tuēri.
struct AutenticacionView: View {

    // MARK: - Modo de autenticación

    private enum ModoAuth {
        case inicioSesion
        case registro
    }

    // MARK: - Bindings

    /// Se pone en `true` cuando el usuario inicia sesión o se registra exitosamente.
    @Binding var isAuthenticated: Bool

    // MARK: - Estado

    @State private var modoActual: ModoAuth = .inicioSesion
    @State private var correo = ""
    @State private var contrasena = ""
    @State private var nombreCompleto = ""
    @State private var contrasenaVisible = false
    @State private var estaCargando = false

    // Alertas
    @State private var mostrarAlertaPaciente = false
    @State private var mostrarAlertaError = false
    @State private var mensajeError = ""

    // MARK: - Colores del diseño

    private let tealTueri = Color(red: 0.051, green: 0.424, blue: 0.471)     // #0D6C78
    private let grisTexto = Color(red: 0.420, green: 0.440, blue: 0.500)      // #6B7280
    private let grisTitulo = Color(red: 0.122, green: 0.161, blue: 0.216)     // #1F2937
    private let grisBorde = Color(red: 0.898, green: 0.906, blue: 0.929)      // #E5E7EB
    private let grisFondoCampo = Color(red: 0.969, green: 0.973, blue: 0.980) // #F7F8FA
    private let grisFondoSegmento = Color(red: 0.945, green: 0.949, blue: 0.957) // #F1F3F4

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                encabezado
                controlSegmentado
                    .padding(.bottom, 28)
                formulario
                botonPrincipal
                    .padding(.top, 8)
                separadorGoogle
                botonGoogle
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.white)
        // ── Alerta: verificación de paciente ──
        .alert(
            "¿Eres un paciente?",
            isPresented: $mostrarAlertaPaciente
        ) {
            Button("Sí, soy paciente") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    modoActual = .registro
                }
            }
            Button("Soy personal de salud", role: .cancel) { }
        } message: {
            Text("Esta aplicación está diseñada exclusivamente para ser usada por pacientes. Si eres personal de salud, debes descargar la app Tuēri para médicos.")
        }
        // ── Alerta: errores ──
        .alert("Error", isPresented: $mostrarAlertaError) {
            Button("Entendido", role: .cancel) { }
        } message: {
            Text(mensajeError)
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

    // MARK: - Control Segmentado (Pestañas)

    private var controlSegmentado: some View {
        HStack(spacing: 4) {
            botonPestana(
                titulo: "Iniciar Sesión",
                activa: modoActual == .inicioSesion
            ) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    modoActual = .inicioSesion
                }
            }

            botonPestana(
                titulo: "Registrarse",
                activa: modoActual == .registro
            ) {
                // Interceptar: mostrar alerta antes de permitir cambio
                mostrarAlertaPaciente = true
            }
        }
        .padding(4)
        .background(grisFondoSegmento)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func botonPestana(
        titulo: String,
        activa: Bool,
        accion: @escaping () -> Void
    ) -> some View {
        Button(action: accion) {
            Text(titulo)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(activa ? grisTitulo : grisTexto)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if activa {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formulario Dinámico

    @ViewBuilder
    private var formulario: some View {
        switch modoActual {
        case .inicioSesion:
            formularioLogin
        case .registro:
            formularioRegistro
        }
    }

    // ── Login ──

    private var formularioLogin: some View {
        VStack(spacing: 20) {
            campoTexto(
                etiqueta: "CORREO ELECTRÓNICO",
                placeholder: "ejemplo@correo.com",
                texto: $correo,
                tipoContenido: .emailAddress,
                tipoTeclado: .emailAddress
            )

            campoClave(mostrarOlvide: true)
        }
    }

    // ── Registro ──

    private var formularioRegistro: some View {
        VStack(spacing: 20) {
            campoTexto(
                etiqueta: "NOMBRE COMPLETO",
                placeholder: "Juan Pérez",
                texto: $nombreCompleto,
                tipoContenido: .name,
                tipoTeclado: .default,
                autocorreccion: true
            )

            campoTexto(
                etiqueta: "CORREO ELECTRÓNICO",
                placeholder: "ejemplo@correo.com",
                texto: $correo,
                tipoContenido: .emailAddress,
                tipoTeclado: .emailAddress
            )

            campoClave(mostrarOlvide: false)
        }
    }

    // MARK: - Componentes de Campo

    /// Campo de texto reutilizable con etiqueta uppercase.
    private func campoTexto(
        etiqueta: String,
        placeholder: String,
        texto: Binding<String>,
        tipoContenido: UITextContentType,
        tipoTeclado: UIKeyboardType,
        autocorreccion: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(etiqueta)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(grisTexto)

            TextField(placeholder, text: texto)
                .font(.system(size: 15))
                .foregroundStyle(grisTitulo)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(grisFondoCampo)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .textContentType(tipoContenido)
                .keyboardType(tipoTeclado)
                .autocorrectionDisabled(!autocorreccion)
                .textInputAutocapitalization(
                    tipoContenido == .name ? .words : .never
                )
        }
    }

    /// Campo de contraseña con toggle de visibilidad y enlace opcional de "¿Olvidaste?".
    private func campoClave(mostrarOlvide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CONTRASEÑA")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(grisTexto)

                Spacer()

                if mostrarOlvide {
                    Button {
                        // TODO: Navegar a flujo de recuperación de contraseña
                    } label: {
                        Text("¿Olvidaste tu contraseña?")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tealTueri)
                    }
                }
            }

            HStack(spacing: 0) {
                Group {
                    if contrasenaVisible {
                        TextField("••••••••", text: $contrasena)
                    } else {
                        SecureField("••••••••", text: $contrasena)
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(grisTitulo)
                .textContentType(
                    modoActual == .registro ? .newPassword : .password
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button {
                    contrasenaVisible.toggle()
                } label: {
                    Image(systemName: contrasenaVisible ? "eye.slash" : "eye")
                        .font(.system(size: 16))
                        .foregroundStyle(grisTexto)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(grisFondoCampo)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Botón Principal

    private var botonPrincipal: some View {
        Button {
            Task {
                switch modoActual {
                case .inicioSesion:
                    await iniciarSesion()
                case .registro:
                    await registrarUsuario()
                }
            }
        } label: {
            Group {
                if estaCargando {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(modoActual == .inicioSesion ? "Entrar" : "Crear Cuenta")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(tealTueri)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(estaCargando || !formularioValido)
        .opacity(formularioValido ? 1.0 : 0.6)
        .padding(.top, 8)
    }

    // MARK: - Separador + Google

    private var separadorGoogle: some View {
        HStack(spacing: 14) {
            linea
            Text("O CONTINÚA CON")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(grisTexto)
            linea
        }
        .padding(.vertical, 28)
    }

    private var linea: some View {
        Rectangle()
            .fill(grisBorde)
            .frame(height: 1)
    }

    private var botonGoogle: some View {
        Button {
            // TODO: Implementar autenticación con Google vía Supabase Auth
        } label: {
            HStack(spacing: 10) {
                iconoGoogle
                Text("Google")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(grisTitulo)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(grisBorde, lineWidth: 1)
            )
        }
    }

    /// Ícono de Google multi-color dibujado con Path (sin dependencias externas).
    private var iconoGoogle: some View {
        Canvas { context, size in
            // Rojo (#EA4335)
            let rojo = Path { p in
                p.move(to: CGPoint(x: 10, y: 3.96))
                p.addCurve(
                    to: CGPoint(x: 16.84, y: 6.46),
                    control1: CGPoint(x: 11.48, y: 3.96),
                    control2: CGPoint(x: 14.56, y: 4.96)
                )
                p.addLine(to: CGPoint(x: 13.98, y: 9.32))
                p.addCurve(
                    to: CGPoint(x: 10, y: 7.92),
                    control1: CGPoint(x: 12.82, y: 8.41),
                    control2: CGPoint(x: 11.5, y: 7.92)
                )
                p.addCurve(
                    to: CGPoint(x: 4.39, y: 12.42),
                    control1: CGPoint(x: 7.39, y: 7.92),
                    control2: CGPoint(x: 5.18, y: 9.72)
                )
                p.addLine(to: CGPoint(x: 1.07, y: 15))
                p.addCurve(
                    to: CGPoint(x: 10, y: 3.96),
                    control1: CGPoint(x: 2.71, y: 8.87),
                    control2: CGPoint(x: 6.09, y: 3.96)
                )
                p.closeSubpath()
            }
            context.fill(rojo, with: .color(Color(red: 0.918, green: 0.263, blue: 0.208)))

            // Azul (#4285F4)
            let azul = Path { p in
                p.move(to: CGPoint(x: 19.58, y: 10.23))
                p.addCurve(
                    to: CGPoint(x: 19.42, y: 8.33),
                    control1: CGPoint(x: 19.58, y: 9.58),
                    control2: CGPoint(x: 19.52, y: 8.95)
                )
                p.addLine(to: CGPoint(x: 10, y: 8.33))
                p.addLine(to: CGPoint(x: 10, y: 12.09))
                p.addLine(to: CGPoint(x: 15.39, y: 12.09))
                p.addCurve(
                    to: CGPoint(x: 13.4, y: 15.09),
                    control1: CGPoint(x: 15.15, y: 13.32),
                    control2: CGPoint(x: 14.45, y: 14.35)
                )
                p.addLine(to: CGPoint(x: 16.63, y: 17.59))
                p.addCurve(
                    to: CGPoint(x: 19.58, y: 10.23),
                    control1: CGPoint(x: 18.51, y: 15.85),
                    control2: CGPoint(x: 19.58, y: 13.27)
                )
                p.closeSubpath()
            }
            context.fill(azul, with: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))

            // Amarillo (#FBBC05)
            let amarillo = Path { p in
                p.move(to: CGPoint(x: 4.39, y: 12.42))
                p.addCurve(
                    to: CGPoint(x: 4.39, y: 7.58),
                    control1: CGPoint(x: 4.06, y: 11.09),
                    control2: CGPoint(x: 4.06, y: 8.58)
                )
                p.addLine(to: CGPoint(x: 1.07, y: 5))
                p.addCurve(
                    to: CGPoint(x: 1.07, y: 15),
                    control1: CGPoint(x: -0.07, y: 7.30),
                    control2: CGPoint(x: -0.07, y: 12.70)
                )
                p.addLine(to: CGPoint(x: 4.39, y: 12.42))
                p.closeSubpath()
            }
            context.fill(amarillo, with: .color(Color(red: 0.984, green: 0.737, blue: 0.020)))

            // Verde (#34A853)
            let verde = Path { p in
                p.move(to: CGPoint(x: 10, y: 16.04))
                p.addCurve(
                    to: CGPoint(x: 13.40, y: 15.09),
                    control1: CGPoint(x: 11.35, y: 16.04),
                    control2: CGPoint(x: 12.52, y: 15.70)
                )
                p.addLine(to: CGPoint(x: 16.63, y: 17.59))
                p.addCurve(
                    to: CGPoint(x: 10, y: 20),
                    control1: CGPoint(x: 14.97, y: 19.11),
                    control2: CGPoint(x: 12.70, y: 20)
                )
                p.addCurve(
                    to: CGPoint(x: 1.07, y: 15),
                    control1: CGPoint(x: 6.09, y: 20),
                    control2: CGPoint(x: 2.71, y: 18.04)
                )
                p.addLine(to: CGPoint(x: 4.39, y: 12.42))
                p.addCurve(
                    to: CGPoint(x: 10, y: 16.04),
                    control1: CGPoint(x: 5.18, y: 14.55),
                    control2: CGPoint(x: 7.39, y: 16.04)
                )
                p.closeSubpath()
            }
            context.fill(verde, with: .color(Color(red: 0.204, green: 0.659, blue: 0.325)))
        }
        .frame(width: 20, height: 20)
    }

    // MARK: - Validación

    private var formularioValido: Bool {
        let correoValido = !correo.trimmingCharacters(in: .whitespaces).isEmpty
        let claveValida = contrasena.count >= 6

        switch modoActual {
        case .inicioSesion:
            return correoValido && claveValida
        case .registro:
            let nombreValido = !nombreCompleto.trimmingCharacters(in: .whitespaces).isEmpty
            return nombreValido && correoValido && claveValida
        }
    }

    // MARK: - Lógica de Autenticación (Mocks)

    /// Simula un inicio de sesión. Reemplazar con Supabase Auth.
    private func iniciarSesion() async {
        estaCargando = true
        defer { estaCargando = false }

        do {
            // Mock: simula latencia de red
            try await Task.sleep(for: .seconds(2))

            print("[AutenticacionView] ✅ Inicio de sesión exitoso para: \(correo)")
            isAuthenticated = true

        } catch {
            mensajeError = "No se pudo iniciar sesión: \(error.localizedDescription)"
            mostrarAlertaError = true
        }
    }

    /// Simula un registro de usuario. Reemplazar con Supabase Auth.
    private func registrarUsuario() async {
        estaCargando = true
        defer { estaCargando = false }

        do {
            // Mock: simula latencia de red
            try await Task.sleep(for: .seconds(2))

            print("[AutenticacionView] ✅ Registro exitoso para: \(nombreCompleto) (\(correo))")
            isAuthenticated = true

        } catch {
            mensajeError = "No se pudo crear la cuenta: \(error.localizedDescription)"
            mostrarAlertaError = true
        }
    }
}

// MARK: - Preview

#Preview("Inicio de Sesión") {
    AutenticacionView(isAuthenticated: .constant(false))
}
