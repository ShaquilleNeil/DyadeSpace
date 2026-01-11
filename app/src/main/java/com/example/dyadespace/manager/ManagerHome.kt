package com.example.dyadespace.manager

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.classes.Employee
import coil.compose.AsyncImage
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController
import com.example.dyadespace.classes.Tasks
import com.example.dyadespace.viewitems.ProjectItem
import com.example.dyadespace.viewitems.TaskItem
import com.example.dyadespace.R
import com.example.dyadespace.authScreens.ProjectViewModel
import com.example.dyadespace.authScreens.TaskViewModel
import com.example.dyadespace.ui.preview.previewData
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import com.example.dyadespace.ui.theme.DyadeSpaceTheme


@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ManagerHome(viewModel: AuthViewModel, projectViewModel: ProjectViewModel, taskViewModel: TaskViewModel, navController: NavController, isPreview: Boolean = false){

    //runs once the screen loads to fire the fetch role again
    LaunchedEffect(Unit) {
        if(!isPreview){
            viewModel.fetchRole { }
            viewModel.fetchAllEmployees()
            taskViewModel.fetchAllTasks()
            projectViewModel.fetchAllProjects()
        }

    }
    val employee = viewModel.currentEmployee.collectAsState().value
    val employees = viewModel.employees.collectAsState().value
    val tasks = taskViewModel.allTasks.collectAsState().value
    val projects = projectViewModel.projects.collectAsState().value


//variable to hold the search query
    var searchQuery by remember { mutableStateOf("") }



    //filtered list that takes the filtered projects
    val filteredProjects = projects.filter { project ->
        project.name?.contains(searchQuery, ignoreCase = true) ?: false
    }


    val displayedProjects =
        if (searchQuery.isBlank()) projects else filteredProjects



    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(5.dp)
    ) {

        Text(
            text = stringResource(R.string.projects),
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier
                .padding(top = 10.dp, bottom = 10.dp)
                .align(Alignment.CenterHorizontally)
        )

        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            shape = RoundedCornerShape(12.dp),
            elevation = CardDefaults.cardElevation(0.dp)
        )
        {
            TextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp), // 👈 compact height
                placeholder = {
                    Text(
                        text = stringResource(R.string.search),
                        style = MaterialTheme.typography.bodySmall
                    )
                },
                leadingIcon = {
                    Icon(
                        Icons.Filled.Search,
                        contentDescription = null
                    )
                },
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,   // 👈 grey bg
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,

                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    disabledIndicatorColor = Color.Transparent,

                    cursorColor = MaterialTheme.colorScheme.primary
                ),
                textStyle = MaterialTheme.typography.bodySmall
            )
        }








        LazyColumn(
            modifier = Modifier.fillMaxWidth()
        ) {
            items(displayedProjects) { project ->
                ProjectItem(project, navController)
            }
        }
    }
}






@Preview(showBackground = true)
@Composable
fun ManagerHomePreview() {
    DyadeSpaceTheme {
        val fakeVM = previewData.authViewModel()
        val fakep = previewData.projectViewModel()
        val faket = previewData.taskViewModel()

        ManagerHome(
            viewModel = fakeVM,
            navController = rememberNavController(),
            projectViewModel = fakep,
            taskViewModel = faket,
            isPreview = true
        )
    }
}
