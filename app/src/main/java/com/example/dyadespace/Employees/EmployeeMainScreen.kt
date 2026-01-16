package com.example.dyadespace.Employees

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import com.example.dyadespace.classes.BottomNavItem
import com.example.dyadespace.classes.BottomNavigation
import com.example.dyadespace.manager.ManagerNavhost

@Composable
fun EmployeeMainScreen(mainNavController: NavHostController) {

    val employeeNavController = rememberNavController() //gets it's own nav controller

    println("🧑‍🔧 EMPLOYEE MAIN SCREEN")

    Scaffold(
        bottomBar = {
            BottomNavigation(navController = employeeNavController, items = BottomNavItem.EmployeeBottomNavItems)
        }
    ) { innerPadding ->
        EmployeeNavhost(
            navController = employeeNavController,
            mainNavController = mainNavController, //pass this to enable logout to come back from second nav host
            modifier = Modifier.padding(innerPadding)
        )
    }

}