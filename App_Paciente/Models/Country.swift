//
//  Country.swift
//  App_Paciente
//
//  Catálogo de códigos de país para el selector de teléfono.
//
//  La lista es ESPEJO EXACTO de App_Medico/lib/countryCodes.ts —
//  mismos ISO, mismos dial codes, mismos emojis. Si agregas un país
//  aquí, agrégalo también allá (y al revés). De lo contrario, un
//  paciente podría guardar un teléfono cuyo país el médico no
//  reconoce y la app del médico mostraría el +código sin bandera.
//
//  Default operativo: Venezuela (+58). Tuēri opera principalmente
//  en Venezuela; ofrecer otro país requiere una acción explícita.
//

import Foundation

struct Country: Identifiable, Hashable, Sendable {
    /// Código ISO 3166-1 alpha-2 (uso interno; no se muestra).
    let iso: String
    /// Nombre en español para mostrar y filtrar.
    let name: String
    /// Prefijo internacional con "+" incluido (ej. "+58").
    let dial: String
    /// Emoji de bandera (Unicode regional indicator pair).
    let flag: String

    var id: String { iso }
}

enum Countries {

    /// Default operativo de la app.
    static let venezuela = Country(iso: "VE", name: "Venezuela", dial: "+58", flag: "🇻🇪")

    /// Lista completa. Sin orden particular — el `paraPicker`
    /// hace su propio ordering (Venezuela primero, resto alfabético).
    static let all: [Country] = [
        Country(iso: "AR", name: "Argentina",            dial: "+54",  flag: "🇦🇷"),
        Country(iso: "AU", name: "Australia",            dial: "+61",  flag: "🇦🇺"),
        Country(iso: "AT", name: "Austria",              dial: "+43",  flag: "🇦🇹"),
        Country(iso: "BE", name: "Bélgica",              dial: "+32",  flag: "🇧🇪"),
        Country(iso: "BO", name: "Bolivia",              dial: "+591", flag: "🇧🇴"),
        Country(iso: "BR", name: "Brasil",               dial: "+55",  flag: "🇧🇷"),
        Country(iso: "CA", name: "Canadá",               dial: "+1",   flag: "🇨🇦"),
        Country(iso: "CL", name: "Chile",                dial: "+56",  flag: "🇨🇱"),
        Country(iso: "CN", name: "China",                dial: "+86",  flag: "🇨🇳"),
        Country(iso: "CO", name: "Colombia",             dial: "+57",  flag: "🇨🇴"),
        Country(iso: "CR", name: "Costa Rica",           dial: "+506", flag: "🇨🇷"),
        Country(iso: "CU", name: "Cuba",                 dial: "+53",  flag: "🇨🇺"),
        Country(iso: "CZ", name: "Chequia",              dial: "+420", flag: "🇨🇿"),
        Country(iso: "DK", name: "Dinamarca",            dial: "+45",  flag: "🇩🇰"),
        Country(iso: "EC", name: "Ecuador",              dial: "+593", flag: "🇪🇨"),
        Country(iso: "SV", name: "El Salvador",          dial: "+503", flag: "🇸🇻"),
        Country(iso: "ES", name: "España",               dial: "+34",  flag: "🇪🇸"),
        Country(iso: "US", name: "Estados Unidos",       dial: "+1",   flag: "🇺🇸"),
        Country(iso: "FI", name: "Finlandia",            dial: "+358", flag: "🇫🇮"),
        Country(iso: "FR", name: "Francia",              dial: "+33",  flag: "🇫🇷"),
        Country(iso: "DE", name: "Alemania",             dial: "+49",  flag: "🇩🇪"),
        Country(iso: "GR", name: "Grecia",               dial: "+30",  flag: "🇬🇷"),
        Country(iso: "GT", name: "Guatemala",            dial: "+502", flag: "🇬🇹"),
        Country(iso: "HN", name: "Honduras",             dial: "+504", flag: "🇭🇳"),
        Country(iso: "HK", name: "Hong Kong",            dial: "+852", flag: "🇭🇰"),
        Country(iso: "HU", name: "Hungría",              dial: "+36",  flag: "🇭🇺"),
        Country(iso: "IN", name: "India",                dial: "+91",  flag: "🇮🇳"),
        Country(iso: "ID", name: "Indonesia",            dial: "+62",  flag: "🇮🇩"),
        Country(iso: "IE", name: "Irlanda",              dial: "+353", flag: "🇮🇪"),
        Country(iso: "IL", name: "Israel",               dial: "+972", flag: "🇮🇱"),
        Country(iso: "IT", name: "Italia",               dial: "+39",  flag: "🇮🇹"),
        Country(iso: "JP", name: "Japón",                dial: "+81",  flag: "🇯🇵"),
        Country(iso: "MX", name: "México",               dial: "+52",  flag: "🇲🇽"),
        Country(iso: "NI", name: "Nicaragua",            dial: "+505", flag: "🇳🇮"),
        Country(iso: "NO", name: "Noruega",              dial: "+47",  flag: "🇳🇴"),
        Country(iso: "NZ", name: "Nueva Zelanda",        dial: "+64",  flag: "🇳🇿"),
        Country(iso: "NL", name: "Países Bajos",         dial: "+31",  flag: "🇳🇱"),
        Country(iso: "PA", name: "Panamá",               dial: "+507", flag: "🇵🇦"),
        Country(iso: "PY", name: "Paraguay",             dial: "+595", flag: "🇵🇾"),
        Country(iso: "PE", name: "Perú",                 dial: "+51",  flag: "🇵🇪"),
        Country(iso: "PL", name: "Polonia",              dial: "+48",  flag: "🇵🇱"),
        Country(iso: "PT", name: "Portugal",             dial: "+351", flag: "🇵🇹"),
        Country(iso: "PR", name: "Puerto Rico",          dial: "+1",   flag: "🇵🇷"),
        Country(iso: "GB", name: "Reino Unido",          dial: "+44",  flag: "🇬🇧"),
        Country(iso: "DO", name: "República Dominicana", dial: "+1",   flag: "🇩🇴"),
        Country(iso: "RO", name: "Rumania",              dial: "+40",  flag: "🇷🇴"),
        Country(iso: "RU", name: "Rusia",                dial: "+7",   flag: "🇷🇺"),
        Country(iso: "SG", name: "Singapur",             dial: "+65",  flag: "🇸🇬"),
        Country(iso: "ZA", name: "Sudáfrica",            dial: "+27",  flag: "🇿🇦"),
        Country(iso: "SE", name: "Suecia",               dial: "+46",  flag: "🇸🇪"),
        Country(iso: "CH", name: "Suiza",                dial: "+41",  flag: "🇨🇭"),
        Country(iso: "TH", name: "Tailandia",            dial: "+66",  flag: "🇹🇭"),
        Country(iso: "TR", name: "Turquía",              dial: "+90",  flag: "🇹🇷"),
        Country(iso: "UA", name: "Ucrania",              dial: "+380", flag: "🇺🇦"),
        Country(iso: "UY", name: "Uruguay",              dial: "+598", flag: "🇺🇾"),
        venezuela,
    ]

    /// Lista para el picker:
    ///  1) Venezuela primero (mercado principal).
    ///  2) Resto alfabético en español (es_ES).
    static let paraPicker: [Country] = {
        let resto = all
            .filter { $0.iso != venezuela.iso }
            .sorted { a, b in
                a.name.compare(b.name, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es")) == .orderedAscending
            }
        return [venezuela] + resto
    }()

    /// Lista pre-ordenada por longitud de `dial` descendente.
    /// La usa `parseE164` para evitar que "+1" gane antes que "+58".
    /// Se calcula una sola vez (lazy let estática).
    private static let porLongitudDeDial: [Country] = paraPicker.sorted {
        $0.dial.count > $1.dial.count
    }

    /// Resuelve un país a partir de un E.164 canónico ("+584121234567").
    ///
    /// Algoritmo: probamos prefijos de mayor a menor longitud para evitar
    /// matches prematuros (ej. "+1" vs "+58", "+5" vs "+591"). En caso de
    /// dial ambiguo (varios países comparten "+1"), nos quedamos con el
    /// primero del orden de `paraPicker` (que es alfabético, así que
    /// EE.UU. gana sobre Canadá / Puerto Rico / República Dominicana —
    /// asunción razonable cuando solo tenemos el número).
    ///
    /// Retorno:
    ///  · `country`: mejor coincidencia (o Venezuela si no hay match).
    ///  · `subscriber`: dígitos después del dial.
    ///  · `matched`: true si pudimos resolver país.
    ///
    /// Si la entrada no empieza por "+", caemos al default (Venezuela)
    /// y devolvemos los dígitos crudos como `subscriber` — útil para
    /// teléfonos legacy guardados como "04121234567" antes del E.164.
    static func parseE164(_ e164: String) -> (country: Country, subscriber: String, matched: Bool) {
        let trimmed = e164.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("+") else {
            let digits = String(trimmed.filter(\.isNumber))
            return (venezuela, digits, false)
        }

        for c in porLongitudDeDial where trimmed.hasPrefix(c.dial) {
            let resto = String(trimmed.dropFirst(c.dial.count))
            let subscriber = String(resto.filter(\.isNumber))
            return (c, subscriber, true)
        }

        // Empieza con "+" pero ningún dial conocido pegó.
        // Preservamos dígitos para que el usuario los vea, no los tiramos.
        let digits = String(trimmed.filter(\.isNumber))
        return (venezuela, digits, false)
    }
}
