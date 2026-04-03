//
//  SupabaseManager.swift
//  App_Paciente
//
//  Created by Ernesto Carmona Fazzolari on 4/1/26.
//

import Foundation
import Supabase

/// Actor encargado de gestionar toda la comunicación con Supabase.
/// Al ser un `actor`, Swift garantiza que el acceso a su estado interno
/// sea seguro entre hilos, ideal para llamadas de red en segundo plano.
actor SupabaseManager {

    // MARK: - Singleton

    static let shared = SupabaseManager()

    // MARK: - Credenciales (llenar con tus valores de Supabase)

    private static let supabaseURL: String = "https://aqopgqcpdmbmgkxmgvoy.supabase.co"
    private static let supabaseAnonKey: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFxb3BncWNwZG1ibWdreG1ndm95Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MjcxNDIsImV4cCI6MjA5MDQwMzE0Mn0.O3Lt-rDU_658DvJ5zR6rxu6pg-j7HNsbLZ8gOODtZcQ"

    // MARK: - Cliente de Supabase

    /// Cliente expuesto de solo lectura para que otras capas (Auth, Storage, etc.)
    /// puedan acceder directamente. El envío de lotes sigue usando `enviarLote()`.
    let client: SupabaseClient

    // MARK: - Inicialización

    private init() {
        guard
            let url = URL(string: Self.supabaseURL),
            !Self.supabaseURL.isEmpty,
            !Self.supabaseAnonKey.isEmpty
        else {
            fatalError(
                """
                [SupabaseManager] ⚠️ Credenciales no configuradas.
                Abre SupabaseManager.swift y llena 'supabaseURL' y 'supabaseAnonKey'
                con los valores de tu proyecto en supabase.com → Settings → API.
                """
            )
        }

        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: Self.supabaseAnonKey
        )

        print("[SupabaseManager] Cliente inicializado para: \(Self.supabaseURL)")
    }

    // MARK: - Envío de Lotes

    /// Inserta un lote de signos vitales en la tabla `lotes_signos_vitales`.
    ///
    /// - Parameter lote: El lote empaquetado con promedios, máximos y mínimos
    ///   calculados desde las lecturas de HealthKit.
    /// - Throws: Error de red, serialización o respuesta de Supabase.
    func enviarLote(_ lote: LoteSignosVitales) async throws {
        print("[SupabaseManager] Enviando lote para paciente: \(lote.idPaciente)")
        print("[SupabaseManager] Intervalo: \(lote.inicioIntervalo) → \(lote.finIntervalo)")

        do {
            try await client
                .from("lotes_signos_vitales")
                .insert(lote)
                .execute()

            print("[SupabaseManager] ✅ Lote enviado exitosamente.")

        } catch let error as URLError {
            print("[SupabaseManager] ❌ Error de red (URLError): \(error.localizedDescription)")
            print("[SupabaseManager] Código: \(error.code.rawValue)")
            throw error

        } catch let error as DecodingError {
            print("[SupabaseManager] ❌ Error de decodificación: \(error)")
            throw error

        } catch {
            print("[SupabaseManager] ❌ Error al insertar lote: \(error)")
            print("[SupabaseManager] Descripción: \(error.localizedDescription)")
            throw error
        }
    }
}
