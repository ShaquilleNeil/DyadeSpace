package com.example.dyadespace

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.example.dyadespace.navigation.AppNavGraph
import com.example.dyadespace.ui.theme.DyadeSpaceTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            DyadeSpaceTheme(
                darkTheme = false
            ) {
                // Single entry point into your app's navigation
                AppNavGraph()
            }
        }
    }
}
