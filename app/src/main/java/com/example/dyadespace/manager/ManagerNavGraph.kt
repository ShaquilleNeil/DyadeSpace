package com.example.dyadespace.manager

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

@Composable
fun ManagerNavhost(navController: NavHostController, mainNavController: NavHostController, modifier: Modifier = Modifier) {

    val viewModel: AuthViewModel = viewModel() //brings the viewmodel into the composable for currentemployee
    val projectViewModel: ProjectViewModel = viewModel()
    val taskViewModel: TaskViewModel = viewModel(
        factory = TaskViewModelFactory(projectViewModel)

    )




    NavHost(
        navController = navController,
        startDestination = BottomNavItem.Home.route,
        modifier = modifier
    ) {
        composable(BottomNavItem.Home.route) { ManagerHome(viewModel, projectViewModel, taskViewModel, mainNavController) }
        composable(BottomNavItem.Staff.route) { ManagerStaff(authViewModel = viewModel, taskViewModel = taskViewModel, navController = mainNavController) }
        composable(BottomNavItem.Profile.route) { ManagerProfile(viewModel, mainNavController) } //navcontroller is innner nav and mainnavcontroller is global
        composable(BottomNavItem.Tasks.route) { ManagerTasks(viewModel, mainNavController, taskViewModel) }
    }
}
