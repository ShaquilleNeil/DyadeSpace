package com.example.dyadespace.Employees

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavController
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.authScreens.ProjectViewModel
import com.example.dyadespace.authScreens.TaskViewModel

@Composable
fun EmployeeHome(viewModel: AuthViewModel, projectViewModel: ProjectViewModel, taskViewModel: TaskViewModel, navController: NavController, isPreview: Boolean = false){


    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        Text("Employee Home")
    }
}