package com.example.dyadespace.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import com.example.dyadespace.manager.ProjectEmployeesScreen
import com.example.dyadespace.manager.ProjectViewContent
import com.example.dyadespace.manager.TaskView

@Composable
fun AppNavGraph(viewModel: AuthViewModel) {

    val navController = rememberNavController()
    val isLoggedIn by viewModel.isLoggedIn.collectAsState()


    if (isLoggedIn == null) {
        // You can replace this with a splash / loader later
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator()
        }
        return
    }

    // 2️⃣ Decide start destination ONCE
    val startDestination = if (isLoggedIn == true) {
        "manager"
    } else {
        "login"
    }

    androidx.compose.runtime.key(isLoggedIn){
        NavHost(
            navController = navController,
            startDestination = startDestination
        ) {
            composable("login") {
                LoginScreen(
                    navController = navController,
                    viewModel = viewModel
                )
            }

            composable("signup") {
                SignupScreen(
                    navController = navController,
                    viewModel = viewModel
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
                ProjectViewContent(projectId = projectId!!, navController = navController, viewModel = viewModel)
            }


            //create route to pass task id to task viiew
            composable("taskView/{taskId}",
                arguments = listOf(navArgument("taskId") { type = NavType.StringType })
            ){
                    backStackEntry ->
                val taskId = backStackEntry.arguments?.getString("taskId")
                // Use the taskId as needed

                TaskView(taskId = taskId!!, navController = navController, viewModel = viewModel)

            }

            composable("projectEmployeesScreen/{projectId}",
                arguments = listOf(navArgument("projectId") { type = NavType.StringType })
            ){ backStackEntry ->
                val projectId = backStackEntry.arguments?.getString("projectId")
                // Use the projectId as needed
                ProjectEmployeesScreen(projectId = projectId!!, navController = navController, viewModel = viewModel)

            }



            composable("TestConnectionScreen") {
                TestConnectionScreen()
            }
        }
    }


}
