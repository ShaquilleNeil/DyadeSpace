package com.example.dyadespace.authScreens

//view model scopes to begin auths
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.dyadespace.data.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch //coroutines do work in the background
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.postgrest.from




class AuthViewModel : ViewModel() {

    private val _authMessage = MutableStateFlow<String?>(null) //mutable state flow, a value that can change over time
    val authMessage = _authMessage //the underscore means only a viewmodel can change this variable(it's liek a toast)



    //sign up functions

    //Supabase operations (auth + database insert) happen over the network, and network calls take time — they’re not instant like adding two numbers. Kotlin protects the app from freezing by forcing long-running or waiting code to run asynchronously.
    //
    //So, suspend means:
    //
    //“This function might pause while waiting (like waiting for network response), but won't block the UI thread.”
    //
    //A phone app can't freeze while waiting for the internet, right?
    //If we didn't use suspend and called it directly inside Compose, the UI could lock up — no animations, no typing, looks like the app crashed.
    fun signUp( firstName: String,
                lastName: String,
                phone: String,
                role: String = "employee",
                email: String,
                password: String) {
        viewModelScope.launch { //starts a coroutine inside the viewmodel -
            // We use viewModelScope.launch because Supabase functions are suspend calls,
            // and running them in a coroutine keeps the UI thread free so the app stays smooth.
            try {
                //supabase sign up call
                val result = SupabaseClient.client.auth.signUpWith(Email){
                    this.email = email
                    this.password = password
                }

                val userId = result?.id.toString(); // grab the user id to use in database

                //insert into employees tables
                SupabaseClient.client.from("employees").insert(
                    mapOf(
                        "EID" to userId,
                        "Employee_fn" to firstName,
                        "Employee_ln" to lastName,
                        "Employee_phone" to phone,
                        "Employee_email" to email,
                        "role" to role,
                        "Avatar_url" to "" // optional placeholder
                    )
                )


                _authMessage.value = "Sign up successful"
            } catch (e: Exception) {
                _authMessage.value = e.message
            }

        }
    }

    fun logIn(email: String, password: String){
        viewModelScope.launch{
            try{
                SupabaseClient.client.auth.signInWith(Email){
                    this.email = email
                    this.password = password
                }
                _authMessage.value = "Sign in successful"

            } catch (e: Exception){
                _authMessage.value = e.message
            }

        }
    }

}