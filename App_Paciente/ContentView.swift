import SwiftUI
import Supabase
import Auth

struct ContentView: View {
    // Memoria del teléfono para todo el flujo de Onboarding
    @AppStorage("isAuthenticated") var isAuthenticated = false
    @AppStorage("datosCompletados") var datosCompletados = false
    @AppStorage("permisosCompletados") var permisosCompletados = false
    @AppStorage("tutorialCompletado") var tutorialCompletado = false

    // Estado de carga mientras se valida la sesión con Supabase
    @State private var isCheckingSession = true

    var body: some View {
        Group {
            if isCheckingSession {
                // Pantalla de carga mientras validamos la sesión
                splashCarga

            } else if !isAuthenticated {
                // Paso 1: Autenticación
                AutenticacionView(isAuthenticated: $isAuthenticated)

            } else if !datosCompletados {
                // Paso 2: Pantalla de completar datos
                CompletarDatosView(datosCompletados: $datosCompletados)

            } else if !permisosCompletados {
                // Paso 3: Permisos del Watch
                PermisosView(permisosCompletados: $permisosCompletados)

            } else if !tutorialCompletado {
                // Paso 4: Tutorial de Complications
                ComplicacionOnboardingView(tutorialCompletado: $tutorialCompletado)

            } else {
                // Paso 5: Todo listo. ¡Entramos a la app con NavigationStack!
                NavigationStack {
                    DashboardView()
                }
            }
        }
        .task {
            await verificarSesion()
        }
        .onChange(of: tutorialCompletado) { _, completado in
            // Cuando un usuario nuevo termina el onboarding, activar la tubería de HealthKit
            if completado {
                HealthKitManager.shared.configurarObservadores()
                print("[ContentView] ✅ Onboarding finalizado. Observadores de HealthKit activados.")
            }
        }
    }

    // MARK: - Splash de carga

    private var splashCarga: some View {
        VStack(spacing: 16) {
            Image("TueriLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            ProgressView()
                .tint(Color(red: 0.051, green: 0.424, blue: 0.471))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    // MARK: - Validación silenciosa de sesión

    /// Verifica con Supabase si hay una sesión activa y si el perfil del paciente
    /// ya existe, sincronizando el estado local antes de mostrar cualquier vista.
    private func verificarSesion() async {
        defer { isCheckingSession = false }

        // 1. Intentar obtener la sesión actual
        guard let session = try? await SupabaseManager.shared.client.auth.session else {
            // No hay sesión → enviar a login
            print("[ContentView] No hay sesión activa. Redirigiendo a login.")
            isAuthenticated = false
            return
        }

        print("[ContentView] Sesión activa encontrada para: \(session.user.email ?? "sin email")")

        // 2. Conectar la tubería de HealthKit con el ID del paciente
        HealthKitManager.shared.idPaciente = session.user.id

        // 3. Verificar si el perfil existe en la BD
        let perfilExiste = (try? await SupabaseManager.shared.client
            .from("perfiles")
            .select()
            .eq("id", value: session.user.id)
            .single()
            .execute()) != nil

        if perfilExiste {
            print("[ContentView] ✅ Perfil encontrado. Sincronizando estado completo.")
            datosCompletados = true
            permisosCompletados = true
            tutorialCompletado = true

            // 4. Activar observadores de HealthKit (la tubería de datos completa)
            HealthKitManager.shared.configurarObservadores()
            print("[ContentView] ✅ Observadores de HealthKit activados.")
        } else {
            print("[ContentView] ⚠️ Perfil no encontrado. El usuario deberá completar sus datos.")
            datosCompletados = false
        }

        // 5. En ambos casos, el usuario está autenticado
        isAuthenticated = true
    }
}

#Preview {
    ContentView()
}
