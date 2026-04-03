import SwiftUI

struct ContentView: View {
    // Memoria del teléfono para todo el flujo de Onboarding
    @AppStorage("isAuthenticated") var isAuthenticated = false
    @AppStorage("datosCompletados") var datosCompletados = false
    @AppStorage("permisosCompletados") var permisosCompletados = false
    @AppStorage("tutorialCompletado") var tutorialCompletado = false
    
    var body: some View {
        if !isAuthenticated {
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
}

#Preview {
    ContentView()
}
