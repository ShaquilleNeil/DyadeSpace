package com.example.dyadespace.manager

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.dyadespace.ui.theme.DyadeSpaceTheme

@Composable
fun ManagerProjects(){
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center
    ){
        Text("Manager Projects", style = MaterialTheme.typography.headlineMedium)

    }
}


//preview
@Preview(showBackground = true)
@Composable
fun ManagerProjectsPreview() {
    DyadeSpaceTheme {
        ManagerProjects()
    }
}