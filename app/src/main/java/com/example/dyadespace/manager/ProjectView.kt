package com.example.dyadespace.manager

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import coil.compose.AsyncImage
import com.example.dyadespace.authScreens.AuthViewModel
import androidx.compose.runtime.getValue


@Composable
fun ProjectViewContent(
    projectId: String,
    navController: NavController,
    viewModel: AuthViewModel
) {
    // Fetch project when projectId changes
    LaunchedEffect(projectId) {
        viewModel.fetchProjectById(projectId)
    }

    val project by viewModel.aproject.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .safeDrawingPadding(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        if (project == null) {
            Text("Loading project...")
        } else {
            project!!.name?.let { Text(it) }

            AsyncImage(
                model = project!!.photo_url,
                contentDescription = "Project Image",
                contentScale = ContentScale.Crop,
                modifier = Modifier .fillMaxWidth()
                    .aspectRatio(16f / 9f)
                    .height(500.dp)
            )
        }
    }
}


@Preview(showBackground = true)
@Composable
fun ProjectViewPreview() {
    ProjectViewContent(projectId = "123",navController = NavController(LocalContext.current), viewModel = AuthViewModel())
}
