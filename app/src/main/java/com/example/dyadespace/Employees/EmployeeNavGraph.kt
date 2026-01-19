package com.example.dyadespace.Employees

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.authScreens.ProjectViewModel
import com.example.dyadespace.authScreens.TaskViewModel
import com.example.dyadespace.classes.BottomNavItem
import com.example.dyadespace.classes.TaskViewModelFactory
import com.example.dyadespace.manager.ManagerHome
import com.example.dyadespace.manager.ManagerProfile
import com.example.dyadespace.manager.ManagerTasks

@Composable
fun EmployeeNavhost(navController: NavHostController, mainNavController: NavHostController, modifier: Modifier = Modifier) {

    val viewModel: AuthViewModel = viewModel() //brings the viewmodel into the composable for currentemployee
    val projectViewModel: ProjectViewModel = viewModel()
    val taskViewModel: TaskViewModel = viewModel(
        factory = TaskViewModelFactory(projectViewModel)

    )




    NavHost(
        navController = navController,
        startDestination = BottomNavItem.EmployeeHome.route,
        modifier = modifier
    ) {
        composable(BottomNavItem.EmployeeHome.route) { EmployeeHome(viewModel, taskViewModel, mainNavController) }
        composable(BottomNavItem.EmployeeProfile.route) { EmployeeProfile(viewModel, mainNavController) } //navcontroller is innner nav and mainnavcontroller is global

    }
}