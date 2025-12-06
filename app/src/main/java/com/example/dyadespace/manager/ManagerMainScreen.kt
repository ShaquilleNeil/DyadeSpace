package com.example.dyadespace.manager

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import com.example.dyadespace.classes.BottomNavigation

@Composable
fun ManagerMainScreen() {

    val managerNavController = rememberNavController()


    Scaffold(
        bottomBar = {
            BottomNavigation(navController = managerNavController)
        }
    ) { innerPadding ->
        ManagerNavhost(
            navController = managerNavController,
            modifier = Modifier.padding(innerPadding)
        )
    }
}
