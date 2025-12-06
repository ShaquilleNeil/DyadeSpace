package com.example.dyadespace.data.supabase
import com.example.dyadespace.BuildConfig
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.storage.Storage

object SupabaseClient {

    private val SUPABASE_URL = BuildConfig.SUPABASE_URL
    private val SUPABASE_KEY = BuildConfig.SUPABASE_ANON_KEY

    val client = createSupabaseClient(
        supabaseUrl = SUPABASE_URL,
        supabaseKey = SUPABASE_KEY
    ) {
        install(Auth)
        install(Postgrest)
        install(Storage)
    }

    suspend fun testConnection(): Boolean {
        return try {
            client.postgrest["employees"].select()  // or any existing table you have
            true
        } catch (e: Exception) {
            println("Supabase connection error: ${e.message}")
            false
        }
    }

}