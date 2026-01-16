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
import com.example.dyadespace.Employees.EmployeeMainScreen
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.authScreens.LoginScreen
import com.example.dyadespace.authScreens.ProjectViewModel
import com.example.dyadespace.authScreens.SignupScreen
import com.example.dyadespace.authScreens.TaskViewModel
import com.example.dyadespace.classes.UserRole
import com.example.dyadespace.manager.ManagerMainScreen
import com.example.dyadespace.manager.ProjectEmployeesScreen
import com.example.dyadespace.manager.ProjectTasksScreen
import com.example.dyadespace.manager.ProjectViewContent
import com.example.dyadespace.manager.TaskView

@Composable
fun AppNavGraph(viewModel: AuthViewModel) {

    val navController = rememberNavController()

    val isLoggedIn by viewModel.isLoggedIn.collectAsState()
    val userRole by viewModel.userRole.collectAsState()

    val projectViewModel: ProjectViewModel = viewModel()

    val taskViewModel: TaskViewModel = viewModel(
        factory = object : androidx.lifecycle.ViewModelProvider.Factory {
            override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T {
                @Suppress("UNCHECKED_CAST")
                return TaskViewModel(projectViewModel) as T
            }
        }
    )

    // 🌀 Splash / loading state
    if (isLoggedIn == null || (isLoggedIn == true && userRole == null)) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator()
        }
        return
    }

    // 🔑 ROLE-BASED ROUTING (SIDE-EFFECT, NOT startDestination)
    LaunchedEffect(isLoggedIn, userRole) {
        when {
            isLoggedIn != true -> {
                navController.navigate("login") {
                    popUpTo(0) { inclusive = true }
                }
            }

            userRole == UserRole.MANAGER -> {
                navController.navigate("manager") {
                    popUpTo(0) { inclusive = true }
                }
            }

            userRole == UserRole.EMPLOYEE -> {
                navController.navigate("employee") {
                    popUpTo(0) { inclusive = true }
                }
            }
        }
    }

    // 🚫 startDestination is STATIC
    NavHost(
        navController = navController,
        startDestination = "login"
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

        composable("employee") {
            EmployeeMainScreen(mainNavController = navController)
        }

        // 🌍 GLOBAL ROUTES (shared)
        composable(
            "projectView/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments!!.getString("projectId")!!
            ProjectViewContent(
                projectId = projectId,
                navController = navController,
                viewModel = viewModel,
                projectViewModel = projectViewModel,
                taskViewModel = taskViewModel
            )
        }

        composable(
            "taskView/{taskId}",
            arguments = listOf(navArgument("taskId") { type = NavType.StringType })
        ) { backStackEntry ->
            val taskId = backStackEntry.arguments!!.getString("taskId")!!
            TaskView(
                taskId = taskId,
                navController = navController,
                taskViewModel = taskViewModel
            )
        }

        composable(
            "projectEmployeesScreen/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments!!.getString("projectId")!!
            ProjectEmployeesScreen(
                projectId = projectId,
                navController = navController,
                projectViewModel = projectViewModel
            )
        }

        composable(
            "projectTasksScreen/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments!!.getString("projectId")!!
            ProjectTasksScreen(
                projectId = projectId,
                navController = navController,
                projectViewModel = projectViewModel,
                taskViewModel = taskViewModel
            )
        }
    }
}
