package com.example.dyadespace.manager

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.example.dyadespace.authScreens.AuthViewModel
import io.github.jan.supabase.realtime.Column

@Composable
fun ProjectView(navController: NavController, viewModel: AuthViewModel){

    Column(
        modifier = Modifier.fillMaxSize().padding(14.dp),
    ){
        Text("Project View!!")
    }
}


@Preview(showBackground = true)
@Composable
fun ProjectViewPreview(){}