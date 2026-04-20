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
                splashCarga

            } else if !isAuthenticated {
                AutenticacionView(isAuthenticated: $isAuthenticated)

            } else if !datosCompletados {
                CompletarDatosView(datosCompletados: $datosCompletados)

            } else if !permisosCompletados {
                PermisosView(permisosCompletados: $permisosCompletados)

            } else if !tutorialCompletado {
                ComplicacionOnboardingView(tutorialCompletado: $tutorialCompletado)

            } else {
                NavigationStack {
                    DashboardView()
                }
            }
        }
        .task {
            // Si iOS relanzó la app en background (para HK delivery),
            // NO inicializar SupabaseManager ni validar sesión.
            // AppDelegate ya registró los observers — es todo lo que se necesita.
            // Esto evita cargar el Supabase SDK innecesariamente en background.
            let isBackground = await MainActor.run {
                UIApplication.shared.applicationState == .background
            }
            guard !isBackground else {
                print("[ContentView] ⏸️ Background launch — skip verificarSesion.")
                isCheckingSession = false
                return
            }
            await verificarSesion()
        }
        .onChange(of: tutorialCompletado) { completado in
            if completado {
                // El usuario acaba de terminar el onboarding (Día 1).
                // Los permisos ya fueron otorgados en PermisosView.
                // Configuramos sistema completo + forzamos bootstrap inicial
                // para que el dashboard tenga datos desde el primer momento.
                print("[ContentView] 🎓 Onboarding completado.")
                Task {
                    await HealthKitManager.shared.configurarSistemaHealthKitCompleto()
                    await HealthKitManager.shared.forzarSincronizacion()
                    await HealthKitManager.shared.flushBuffer()
                }
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

    private func verificarSesion() async {
        defer { isCheckingSession = false }

        // 1. Verificar sesión con Supabase
        guard let session = try? await SupabaseManager.shared.client.auth.session else {
            print("[ContentView] No hay sesión activa.")
            isAuthenticated = false
            return
        }

        print("[ContentView] Sesión activa: \(session.user.email ?? "sin email")")

        // 2. Asignar idPaciente para la tubería de HealthKit.
        //    Los tokens los maneja exclusivamente el SDK de Supabase en
        //    Keychain; EnvioLigero los consulta bajo demanda (v5.7).
        HealthKitManager.shared.idPaciente = session.user.id

        // 3. Verificar si el perfil existe en la BD
        let perfilExiste = (try? await SupabaseManager.shared.client
            .from("perfiles")
            .select()
            .eq("id", value: session.user.id)
            .single()
            .execute()) != nil

        if perfilExiste {
            print("[ContentView] ✅ Perfil encontrado. Usuario recurrente.")
            datosCompletados = true
            permisosCompletados = true
            tutorialCompletado = true

            // Configurar sistema HealthKit completo para usuario recurrente.
            // Esto re-valida permisos y asegura observers activos.
            await HealthKitManager.shared.configurarSistemaHealthKitCompleto()
            await HealthKitManager.shared.flushBuffer()
        } else {
            print("[ContentView] ⚠️ Sin perfil. Redirigiendo a Completar Datos.")
            datosCompletados = false
        }

        // 4. Autenticado en ambos casos
        isAuthenticated = true
    }
}

#Preview {
    ContentView()
}
