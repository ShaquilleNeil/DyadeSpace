package com.example.dyadespace.manager

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.ui.theme.DyadeSpaceTheme
import com.example.dyadespace.viewitems.TaskItem
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavController


@Composable
fun ManagerTasks(viewModel: AuthViewModel, navController: NavController){
    LaunchedEffect(Unit) {
        viewModel.fetchRole {}
        viewModel.fetchMyTasks()
    }

    val tasks = viewModel.myTasks.collectAsState().value

    // UI-only state (filter)
    val tabs = listOf( "To-Do", "In Progress", "Done")
    var selectedTab by remember { mutableStateOf(0) }

    val filteredTasks = remember(selectedTab, tasks) {
        when (tabs[selectedTab]) {
            "To-Do" -> tasks.filter { it.status == "todo" }
            "In Progress" -> tasks.filter { it.status == "in-progress" }
            "Done" -> tasks.filter { it.status == "done" }
            else -> tasks
        }
    }


    Column(
        modifier = Modifier.fillMaxSize().padding(14.dp),
    ){


        // 🔹 Status picker
        TabRow(selectedTabIndex = selectedTab) {
            tabs.forEachIndexed { index, title ->
                Tab(
                    selected = selectedTab == index,
                    onClick = { selectedTab = index },
                    text = { Text(title) },
                    modifier = Modifier.padding(horizontal = 8.dp)
                )
            }
        }

        LazyColumn(modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) {
              items(filteredTasks) { tsk ->
                  TaskItem(tsk, navController = navController)
              }
        }

    }
}



@Preview(showBackground = true)
@Composable
fun ManagerTasksPreview() {
    DyadeSpaceTheme {
        ManagerTasks(viewModel(), NavController(LocalContext.current))

    }
}
