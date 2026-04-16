import SwiftUI
import GoogleSignIn
import os

// MARK: - AppDelegate

/// Intercepta el arranque nativo de iOS para registrar observers de HealthKit
/// ANTES de que cualquier vista se cargue. Esto cubre el caso crítico de
/// background wake: iOS relanza la app sin UI y HealthKit necesita un
/// observer registrado para entregar los datos pendientes.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Registrar observers + background delivery de forma SÍNCRONA.
        // NO solicitar permisos aquí (requiere UI async).
        HealthKitManager.shared.registrarObservadores()
        print("[AppDelegate] ✅ didFinishLaunchingWithOptions — observers registrados.")
        return true
    }

    /// iOS envía este callback ANTES de matar la app por memoria.
    /// Si lo vemos en los logs, confirma que es presión del sistema.
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        let memMB = Double(os_proc_available_memory()) / 1_048_576.0
        print("[AppDelegate] ⚠️⚠️⚠️ MEMORY WARNING — disponible: \(String(format: "%.1f", memMB)) MB")
    }
}

// MARK: - App Entry Point

@main
struct App_PacienteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // La app volvió a primer plano — AQUÍ sí hay memoria suficiente.
                // 1. Enviar lotes que se bufferearon en background.
                // 2. Sincronizar si hay datos nuevos pendientes.
                print("[App] 🟢 scenePhase → active")
                Task {
                    await HealthKitManager.shared.flushBuffer()
                    await HealthKitManager.shared.sincronizarSiNecesario()
                }

            case .background:
                print("[App] 🔴 scenePhase → background")

            default:
                break
            }
        }
    }
}
