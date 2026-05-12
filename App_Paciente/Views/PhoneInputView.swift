//
//  PhoneInputView.swift
//  App_Paciente
//
//  Entrada de teléfono amistosa: selector de país (sheet con búsqueda)
//  + TextField que SOLO acepta dígitos.
//
//  El componente concatena `country.dial + subscriber` internamente y
//  notifica al padre via `onChange(e164, isValid)`. El padre se encarga
//  de bloquear botones y persistir el E.164 canónico.
//
//  Reutilizable entre onboarding y settings:
//    - `defaultE164` solo se lee al .onAppear. Para forzar re-parseo
//      (ej. al entrar a edit mode en AjustesView con un valor distinto),
//      cambia el `.id(...)` del PhoneInputView desde el padre.
//
//  La validación delegada a `TelefonoValidator` — fuente única de
//  verdad para el regex E.164 y la canonización.
//

import SwiftUI

struct PhoneInputView: View {

    // MARK: - Input del padre

    /// E.164 inicial. Si está vacío, default = Venezuela + subscriber "".
    /// Si trae un valor parseable, abre con el país y dígitos correctos.
    let defaultE164: String

    /// Pintar el campo en rojo + hint debajo. El padre decide cuándo
    /// mostrar error (típicamente: `!e164.isEmpty && !valido`).
    let showError: Bool

    /// Background del campo (default: gris claro de los formularios).
    let backgroundColor: Color

    /// Callback que recibe (E.164 compuesto, isValid). El padre lo guarda
    /// y lo usa para habilitar el botón Continuar/Guardar y para enviar
    /// a Supabase.
    let onChange: (_ e164: String, _ isValid: Bool) -> Void

    // MARK: - Estado interno

    @State private var country: Country = Countries.venezuela
    @State private var subscriber: String = ""
    @State private var showPicker = false

    // MARK: - Init

    init(
        defaultE164: String = "",
        showError: Bool = false,
        backgroundColor: Color = Color(red: 0.969, green: 0.973, blue: 0.980),
        onChange: @escaping (_ e164: String, _ isValid: Bool) -> Void
    ) {
        self.defaultE164 = defaultE164
        self.showError = showError
        self.backgroundColor = backgroundColor
        self.onChange = onChange
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                botonPais
                Divider().frame(height: 24)
                campoNumerico
            }
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if showError {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red, lineWidth: 1)
                }
            }

            if showError {
                Text("Número inválido. Ingresa al menos 8 dígitos.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 4)
            }
        }
        .onAppear {
            // Parsear el default UNA SOLA VEZ al montar. Si el padre quiere
            // re-parsear, debe forzar remount con `.id(...)`.
            if !defaultE164.isEmpty {
                let parsed = Countries.parseE164(defaultE164)
                country = parsed.country
                subscriber = parsed.subscriber
            }
            // Emitir estado inicial — para que el padre conozca la validez
            // desde el primer render (ej. botón Continuar en onboarding
            // arranca deshabilitado porque subscriber está vacío).
            emitirCambio()
        }
        .onChange(of: country) { _, _ in emitirCambio() }
        .onChange(of: subscriber) { _, _ in emitirCambio() }
        .sheet(isPresented: $showPicker) {
            CountryPickerSheet(seleccionado: country) { nuevo in
                country = nuevo
                showPicker = false
            }
        }
    }

    // MARK: - Subvistas

    private var botonPais: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 6) {
                Text(country.flag)
                    .font(.system(size: 18))
                Text(country.dial)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.122, green: 0.161, blue: 0.216))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Código de país: \(country.name) \(country.dial). Toca para cambiar.")
    }

    private var campoNumerico: some View {
        TextField("412 1234567", text: $subscriber)
            .font(.system(size: 15))
            .foregroundStyle(Color(red: 0.122, green: 0.161, blue: 0.216))
            .keyboardType(.numberPad)
            .textContentType(.telephoneNumber)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 48)
            .onChange(of: subscriber) { _, nuevo in
                // Filtro defensivo: el numberPad ya impide letras en iOS,
                // pero si el usuario PEGA texto desde el portapapeles
                // (clipboard puede contener "+58-412..."), nos quedamos
                // solo con los dígitos. También topamos a 15 — el máximo
                // de E.164 incluyendo código país.
                let soloDigitos = String(nuevo.filter(\.isNumber).prefix(15))
                if soloDigitos != nuevo {
                    subscriber = soloDigitos
                }
            }
    }

    // MARK: - Lógica

    private func emitirCambio() {
        let e164 = subscriber.isEmpty ? "" : "\(country.dial)\(subscriber)"
        onChange(e164, TelefonoValidator.isE164Valid(e164))
    }
}

// MARK: - ════════════════════════════════════════════════
// MARK:   Sheet del selector de país
// MARK: - ════════════════════════════════════════════════

/// Sheet modal con `List` + búsqueda nativa (`.searchable`).
/// Buscable por nombre, dial code o ISO ("VE", "+58", "venezuela").
private struct CountryPickerSheet: View {

    let seleccionado: Country
    let onPick: (Country) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Country] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Countries.paraPicker }
        return Countries.paraPicker.filter { c in
            c.name.lowercased().contains(q) ||
            c.dial.contains(q) ||
            c.iso.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { c in
                Button {
                    onPick(c)
                } label: {
                    HStack(spacing: 14) {
                        Text(c.flag)
                            .font(.system(size: 22))
                        Text(c.name)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(red: 0.122, green: 0.161, blue: 0.216))
                        Spacer()
                        Text(c.dial)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if c.iso == seleccionado.iso {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.051, green: 0.424, blue: 0.471))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    c.iso == seleccionado.iso
                        ? Color(red: 0.94, green: 0.98, blue: 0.97)
                        : Color.clear
                )
            }
            .listStyle(.plain)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Buscar país o código…"
            )
            .navigationTitle("Código de país")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(Color(red: 0.051, green: 0.424, blue: 0.471))
                }
            }
            .overlay {
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("Sin resultados")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Preview

#Preview("Vacío") {
    StateContainer()
}

private struct StateContainer: View {
    @State private var e164 = ""
    @State private var valido = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhoneInputView(showError: !e164.isEmpty && !valido) { nuevo, ok in
                e164 = nuevo
                valido = ok
            }
            Text("E.164: \(e164.isEmpty ? "(vacío)" : e164)")
                .font(.caption)
            Text("Válido: \(valido ? "✅" : "❌")")
                .font(.caption)
        }
        .padding()
    }
}
