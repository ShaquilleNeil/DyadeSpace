package com.example.dyadespace.navigation

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.dyadespace.TestConnectionScreen
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.authScreens.LoginScreen
import com.example.dyadespace.authScreens.SignupScreen
import com.example.dyadespace.manager.ManagerMainScreen
import com.example.dyadespace.manager.ProjectViewContent

@Composable
fun AppNavGraph() {

    val navController = rememberNavController()
    val authViewModel: AuthViewModel = viewModel()
    val isLoggedIn = authViewModel.isLoggedIn.value

    NavHost(
        navController = navController,
        startDestination = if (isLoggedIn) "manager" else "login"
    ) {
        composable("login") {
            LoginScreen(
                navController = navController,
                viewModel = authViewModel
            )
        }

        composable("signup") {
            SignupScreen(
                navController = navController,
                viewModel = authViewModel
            )
        }


        composable("manager") {
            ManagerMainScreen(mainNavController = navController)
        }

        //create route to pass project id to project view
        composable("projectView/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ){ backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")
            // Use the projectId as needed
            ProjectViewContent(projectId = projectId!!, navController = navController, viewModel = authViewModel)
        }


        composable("TestConnectionScreen") {
            TestConnectionScreen()
        }
    }
}
