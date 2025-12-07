package com.example.dyadespace.manager

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import com.example.dyadespace.classes.BottomNavigation

@Composable
fun ManagerMainScreen(mainNavController: NavHostController) {

    val managerNavController = rememberNavController() //gets it's own nav controller


    Scaffold(
        bottomBar = {
            BottomNavigation(navController = managerNavController)
        }
    ) { innerPadding ->
        ManagerNavhost(
            navController = managerNavController,
            mainNavController = mainNavController, //pass this to enable logout to come back from second nav host
            modifier = Modifier.padding(innerPadding)
        )
    }
}
