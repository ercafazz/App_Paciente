//
//  TelefonoValidator.swift
//  App_Paciente
//
//  Validación E.164 para el campo `perfiles.telefono`.
//
//  La columna `perfiles.telefono` se comparte con App_Medico (React Native),
//  donde el médico tiene un botón "Llamar" que abre el dialer con
//  `tel:<telefono>`. Si el número no está en E.164, el dialer falla o
//  abre un número malformado — por eso la app del paciente DEBE guardar
//  siempre la versión canónica.
//
//  Definición espejo del validador en App_Medico (RN):
//    Regex E.164 estricto: ^\+[1-9]\d{7,14}$
//    · "+" obligatorio
//    · Código de país sin "0" al inicio (primer dígito 1-9)
//    · Total 8-15 dígitos sin contar el "+"
//
//  Entrada: se aceptan espacios, guiones y paréntesis (ej. "+58 412-1234567")
//  → se eliminan antes de validar/persistir.
//

import Foundation

enum TelefonoValidator {

    /// Regex E.164 estricto — espejo exacto del validador RN.
    /// Se compila una sola vez (lazy static) para no pagar el coste por llamada.
    private static let regex: NSRegularExpression = {
        // Forzamos el unwrap: si este patrón no compila en runtime,
        // hay un bug literal en el código fuente.
        try! NSRegularExpression(pattern: "^\\+[1-9]\\d{7,14}$")
    }()

    /// Elimina espacios, guiones y paréntesis. Conserva el resto tal cual
    /// (incluido el "+") para que `isE164Valid` decida si es válido.
    private static func limpiar(_ s: String) -> String {
        let separadores: Set<Character> = [" ", "-", "(", ")", "\u{00A0}"] // nbsp
        return String(s.filter { !separadores.contains($0) })
    }

    /// `true` si la cadena, una vez limpia de separadores, cumple E.164.
    static func isE164Valid(_ s: String) -> Bool {
        let limpio = limpiar(s.trimmingCharacters(in: .whitespacesAndNewlines))
        let range = NSRange(limpio.startIndex..., in: limpio)
        return regex.firstMatch(in: limpio, range: range) != nil
    }

    /// Devuelve la versión canónica E.164 (sin separadores) si la entrada
    /// es válida; `nil` en caso contrario.
    ///
    /// Esta es la forma que SIEMPRE debe persistirse en `perfiles.telefono`.
    static func toCanonicalE164(_ s: String) -> String? {
        let limpio = limpiar(s.trimmingCharacters(in: .whitespacesAndNewlines))
        return isE164Valid(limpio) ? limpio : nil
    }
}
