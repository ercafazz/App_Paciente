import SwiftUI

struct ContentView: View {
    @AppStorage("permisosCompletados") var permisosCompletados = false
    
    var body: some View {
        if permisosCompletados {
            VStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                Text("¡App Conectada al Watch!")
                    .font(.title)
                    .bold()
                    .padding()
            }
        } else {
            PermisosView(permisosCompletados: $permisosCompletados)
        }
    }
}

#Preview {
    ContentView()
}
