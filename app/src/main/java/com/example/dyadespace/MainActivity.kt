package com.example.dyadespace

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.navigation.AppNavGraph
import com.example.dyadespace.ui.theme.DyadeSpaceTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        enableEdgeToEdge()

        setContent {
            val viewModel: AuthViewModel =
                androidx.lifecycle.viewmodel.compose.viewModel()


            DyadeSpaceTheme(darkTheme = false) {
                AppNavGraph(viewModel = viewModel)
            }
        }
    }
}
