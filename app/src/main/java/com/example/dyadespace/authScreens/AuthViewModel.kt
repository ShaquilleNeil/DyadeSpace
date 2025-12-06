package com.example.dyadespace.authScreens

//view model scopes to begin auths
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.dyadespace.data.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch //coroutines do work in the background
import io.github.jan.supabase.auth.providers.builtin.Email



class AuthViewModel : ViewModel() {

    private val _authMessage = MutableStateFlow<String?>(null) //mutable state flow, a value that can change over time
    val authMessage = _authMessage //the underscore means only a viewmodel can change this variable(it's liek a toast)


    //sign up functions
    fun signUp(email: String, password: String) {
        viewModelScope.launch { //starts a coroutine inside the viewmodel -
            // We use viewModelScope.launch because Supabase functions are suspend calls,
            // and running them in a coroutine keeps the UI thread free so the app stays smooth.
            try {
                //supabase sign up call
                SupabaseClient.client.auth.signUpWith(Email){
                    this.email = email
                    this.password = password
                }
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