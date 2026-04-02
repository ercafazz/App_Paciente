//
//  ComplicacionOnboardingView.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/2/26.
//

import SwiftUI

/// Tutorial interactivo que guía al paciente para agregar la Complication de Tuēri
/// en la esfera de su Apple Watch. Corresponde a la Screen 5 del diseño.
struct ComplicacionOnboardingView: View {

    // MARK: - Bindings

    /// Notifica al flujo principal que el tutorial finalizó.
    @Binding var tutorialCompletado: Bool

    // MARK: - Estado

    @State private var pasoActual: Int = 0

    // MARK: - Colores

    private let tealTueri = Color(red: 0.051, green: 0.424, blue: 0.471)
    private let grisTexto = Color(red: 0.420, green: 0.440, blue: 0.500)
    private let grisTitulo = Color(red: 0.122, green: 0.161, blue: 0.216)
    private let grisBorde = Color(red: 0.898, green: 0.906, blue: 0.929)

    // MARK: - Datos

    private let pasos: [(titulo: String, descripcion: String)] = [
        ("1. Presiona firme",     "Mantén presionada tu esfera de Apple Watch."),
        ("2. Toca \"Editar\"",    "Selecciona el botón teal de \"Editar\"."),
        ("3. Elige un espacio",   "Desliza hasta un espacio vacío y tócalo."),
        ("4. Selecciona Tuēri",   "Busca y selecciona \"Tuēri\" para activarla."),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    encabezado
                    textoExplicativo
                        .padding(.bottom, 24)
                    carrusel
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            botonTodoListo
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .background(Color.white)
    }

    // MARK: - Encabezado

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("TueriLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Texto explicativo

    private var textoExplicativo: some View {
        VStack(spacing: 8) {
            Text("Añade Tuēri a tu esfera")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(grisTitulo)
                .multilineTextAlignment(.center)

            Text("Una Complication activa nos permite monitorear tus signos vitales en segundo plano para cuidarte mejor. Sigue estos pasos en tu reloj:")
                .font(.system(size: 14))
                .foregroundStyle(grisTexto)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Carrusel

    private var carrusel: some View {
        TabView(selection: $pasoActual) {
            ForEach(0..<pasos.count, id: \.self) { index in
                tarjetaPaso(index: index)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 340)
    }

    private func tarjetaPaso(index: Int) -> some View {
        VStack(spacing: 14) {
            ilustracion(para: index)
                .frame(height: 180)

            Text(pasos[index].titulo)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(grisTitulo)

            Text(pasos[index].descripcion)
                .font(.system(size: 13))
                .foregroundStyle(grisTexto)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(grisBorde, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Router de ilustraciones

    @ViewBuilder
    private func ilustracion(para paso: Int) -> some View {
        switch paso {
        case 0: VisualPresionaFirme(teal: tealTueri, gris: grisTitulo)
        case 1: VisualTocaEditar(teal: tealTueri, gris: grisTitulo)
        case 2: VisualEligeEspacio(teal: tealTueri, gris: grisTitulo)
        case 3: VisualSeleccionaTueri(teal: tealTueri, gris: grisTitulo)
        default: EmptyView()
        }
    }

    // MARK: - Botón

    private var botonTodoListo: some View {
        Button {
            tutorialCompletado = true
        } label: {
            Text("Todo Listo")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(tealTueri)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - WatchFrame (Carcasa reutilizable del Apple Watch)

/// Dibuja la carcasa del Apple Watch con correas, corona y fondo gris claro.
/// El contenido se inyecta en el centro de la pantalla.
private struct WatchFrame<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private let casoColor = Color(red: 0.122, green: 0.161, blue: 0.216)
    private let fondoPantalla = Color(red: 0.945, green: 0.949, blue: 0.957)

    var body: some View {
        ZStack {
            // Correa superior
            RoundedRectangle(cornerRadius: 6)
                .fill(casoColor)
                .frame(width: 38, height: 16)
                .offset(y: -70)

            // Correa inferior
            RoundedRectangle(cornerRadius: 6)
                .fill(casoColor)
                .frame(width: 38, height: 16)
                .offset(y: 70)

            // Corona (Digital Crown)
            RoundedRectangle(cornerRadius: 2)
                .fill(casoColor)
                .frame(width: 5, height: 18)
                .offset(x: 48)

            // Carcasa
            RoundedRectangle(cornerRadius: 22)
                .stroke(casoColor, lineWidth: 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(fondoPantalla)
                )
                .frame(width: 90, height: 115)

            // Contenido de la pantalla
            content
                .frame(width: 74, height: 100)
                .clipped()
        }
        .frame(width: 110, height: 160)
    }
}

// MARK: - Paso 1: Presiona Firme (anillos concéntricos)

private struct VisualPresionaFirme: View {
    let teal: Color
    let gris: Color

    var body: some View {
        WatchFrame {
            ZStack {
                Circle()
                    .stroke(teal.opacity(0.3), lineWidth: 2)
                    .frame(width: 50, height: 50)

                Circle()
                    .stroke(teal.opacity(0.5), lineWidth: 2)
                    .frame(width: 36, height: 36)

                Circle()
                    .fill(teal.opacity(0.2))
                    .frame(width: 24, height: 24)

                Circle()
                    .fill(teal)
                    .frame(width: 12, height: 12)
            }
        }
    }
}

// MARK: - Paso 2: Toca "Editar" (reloj con botón)

private struct VisualTocaEditar: View {
    let teal: Color
    let gris: Color

    var body: some View {
        WatchFrame {
            VStack(spacing: 10) {
                // Reloj simplificado
                ZStack {
                    Circle()
                        .stroke(gris.opacity(0.4), lineWidth: 1)
                        .frame(width: 30, height: 30)

                    // Manecilla
                    RoundedRectangle(cornerRadius: 1)
                        .fill(gris)
                        .frame(width: 2, height: 12)
                        .offset(y: -4)
                        .rotationEffect(.degrees(-15))
                }

                // Botón "Editar"
                Text("Editar")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(teal)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Paso 3: Elige un espacio (slots + dashed)

private struct VisualEligeEspacio: View {
    let teal: Color
    let gris: Color

    var body: some View {
        WatchFrame {
            VStack(spacing: 8) {
                // Slots ocupados
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gris.opacity(0.15))
                        .frame(width: 22, height: 22)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(gris.opacity(0.15))
                        .frame(width: 22, height: 22)
                }

                // Slot vacío destacado (dashed border)
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            teal,
                            style: StrokeStyle(lineWidth: 2, dash: [5, 3])
                        )
                        .frame(width: 36, height: 36)

                    Text("+")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(teal)
                }
            }
        }
    }
}

// MARK: - Paso 4: Selecciona Tuēri (lista con fila activa)

private struct VisualSeleccionaTueri: View {
    let teal: Color
    let gris: Color

    var body: some View {
        WatchFrame {
            VStack(spacing: 4) {
                // Fila genérica 1
                filaGenerica

                // Fila Tuēri (activa)
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(teal)
                            .frame(width: 16, height: 16)

                        Text("T")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text("Tuēri")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(gris)

                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(teal.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(teal, lineWidth: 1)
                )

                // Fila genérica 2
                filaGenerica
            }
            .padding(.horizontal, 4)
        }
    }

    private var filaGenerica: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(gris.opacity(0.2))
                .frame(width: 16, height: 16)

            RoundedRectangle(cornerRadius: 2)
                .fill(gris.opacity(0.2))
                .frame(width: 32, height: 6)

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.6))
        )
    }
}

// MARK: - Preview

#Preview {
    ComplicacionOnboardingView(tutorialCompletado: .constant(false))
}
