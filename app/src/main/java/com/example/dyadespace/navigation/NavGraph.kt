package com.example.dyadespace.navigation

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.example.dyadespace.authScreens.LoginScreen
import com.example.dyadespace.authScreens.SignupScreen
import com.example.dyadespace.MainActivity
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.manager.ManagerHome

/*
 NavGraph is the central routing system of the app.
 It decides which screen is visible and how the user moves around.

 Think of it like:
 - Login -> Signup -> Home
 - A map of all screens and how to travel between them.
*/

@Composable
fun AppNavGraph(navController: NavHostController) {


    //shared variable for auth
    val authViewModel: AuthViewModel = viewModel()


    /*
     NavHost:
     - Holds all the screens (routes)
     - Controls navigation using the navController
     - startDestination = the first screen shown when the app opens
    */
    NavHost(
        navController = navController,
        startDestination = "login"      // User sees Login first
    ) {
        /*
         composable("login"):
         - A screen registered in navigation
         - When navController.navigate("login") is called,
           LoginScreen() becomes visible
        */
        composable("login") {
            LoginScreen(
                navController = navController,
                viewModel = authViewModel
            )
        }

        /*
         composable("signup"):
         - Opens Signup screen
         - Used when user taps "Create Account"
        */
        composable("signup") {
            SignupScreen(
                navController = navController,
                viewModel = authViewModel
            )
        }

        /*
         composable("home"):
         - The main app screen after authentication
         - We'll build this after login works
        */
        composable("home") {
            ManagerHome() // placeholder for now
        }
    }
}
