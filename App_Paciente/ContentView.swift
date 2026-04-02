import SwiftUI

struct ContentView: View {
    // Memoria del teléfono para recordar en qué paso va el paciente
    @AppStorage("isAuthenticated") var isAuthenticated = false
    @AppStorage("datosCompletados") var datosCompletados = false // NUEVA MEMORIA
    @AppStorage("permisosCompletados") var permisosCompletados = false
    
    var body: some View {
        if !isAuthenticated {
            // Paso 1: Autenticación (Login / Registro)
            AutenticacionView(isAuthenticated: $isAuthenticated)
            
        } else if !datosCompletados {
            // Paso 2: Pantalla de completar datos (Screen 3)
            CompletarDatosView(datosCompletados: $datosCompletados)
            
        } else if !permisosCompletados {
            // Paso 3: Permisos del Watch (Screen 4)
            PermisosView(permisosCompletados: $permisosCompletados)
            
        } else {
            // Paso 4: Todo listo. (Aquí irá el Dashboard real)
            VStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                
                Text("¡Onboarding Completado!")
                    .font(.title)
                    .bold()
                    .padding()
                
                // Botón temporal para resetear toda la app y probar desde cero
                Button("Resetear Prueba") {
                    isAuthenticated = false
                    datosCompletados = false
                    permisosCompletados = false
                }
                .padding(.top, 40)
                .foregroundColor(.red)
            }
        }
    }
}

#Preview {
    ContentView()
}
