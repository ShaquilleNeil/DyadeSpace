package com.example.dyadespace.manager

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Surface
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.navigation.NavController
import com.example.dyadespace.authScreens.TaskViewModel
import com.example.dyadespace.ui.preview.previewData


@Composable
fun ManagerTasks(viewModel: AuthViewModel, navController: NavController, taskViewModel: TaskViewModel){
    LaunchedEffect(Unit) {
        viewModel.fetchRole ()
        taskViewModel.fetchMyTasks()
    }

    val tasks = taskViewModel.myTasks.collectAsState().value

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
    )
    {

        if (filteredTasks.isEmpty()) {
            androidx.compose.foundation.layout.Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f), // 👈 takes LazyColumn’s space
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "No tasks found",
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
        else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f) // 👈 same space as empty state
                    .padding(top = 10.dp)
            ) {
                items(filteredTasks) { tsk ->
                    TaskItem(tsk, navController = navController, showRemove = false, onRemove = {

                    }
                    )
                }
            }
        }


        // 🔹 Status picker
//        TabRow(selectedTabIndex = selectedTab) {
//            tabs.forEachIndexed { index, title ->
//                Tab(
//                    selected = selectedTab == index,
//                    onClick = { selectedTab = index },
//                    text = { Text(title) },
//                    modifier = Modifier.padding(horizontal = 8.dp)
//                )
//            }
//        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            tabs.forEachIndexed { index, title ->
                FilterChip(
                    selected = selectedTab == index,
                    onClick = { selectedTab = index },
                    modifier = Modifier.weight(1f),
                    label = {
                        Text(
                            text = title,
                            maxLines = 1,
                            softWrap = false,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                )
            }
        }



    }



}



@Preview(showBackground = true, name = "Light", uiMode = Configuration.UI_MODE_NIGHT_NO)
@Preview(
    showBackground = true,
    name = "Dark",
    uiMode = Configuration.UI_MODE_NIGHT_YES
)
@Composable
fun ManagerTasksPreview() {
    val faket = previewData.taskViewModel()
    DyadeSpaceTheme() {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background
        ) {
            ManagerTasks(viewModel(), NavController(LocalContext.current), faket)
        }
    }

}
