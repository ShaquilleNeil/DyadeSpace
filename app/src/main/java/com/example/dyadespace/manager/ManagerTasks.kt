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
import androidx.compose.ui.Alignment


@Composable
fun ManagerTasks(viewModel: AuthViewModel){
    LaunchedEffect(Unit) {
        viewModel.fetchRole {}
        viewModel.fetchMyTasks()
    }

    val tasks = viewModel.myTasks.collectAsState().value

    Column(
        modifier = Modifier.fillMaxSize().padding(14.dp),
    ){

                Text("My Tasks", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 14.dp).padding(bottom = 14.dp).align(Alignment.CenterHorizontally))
        LazyColumn(modifier = Modifier.fillMaxWidth()) {
              items(tasks) { tsk ->
                  TaskItem(tsk)
              }
        }

    }
}



@Preview(showBackground = true)
@Composable
fun ManagerTasksPreview() {
    DyadeSpaceTheme {
        ManagerTasks(viewModel())

    }
}
