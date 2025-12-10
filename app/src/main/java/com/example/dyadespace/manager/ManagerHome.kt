package com.example.dyadespace.manager

import android.R
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
import com.example.dyadespace.classes.Tasks
import com.example.dyadespace.viewitems.ProjectItem
import com.example.dyadespace.viewitems.TaskItem


@Composable
fun ManagerHome(viewModel: AuthViewModel){

    //runs once the screen loads to fire the fetch role again
    LaunchedEffect(Unit) {
        viewModel.fetchRole { }
        viewModel.fetchAllEmployees()
        viewModel.fetchAllTasks()
        viewModel.fetchAllProjects()
    }
    val employee = viewModel.currentEmployee.collectAsState().value
    val employees = viewModel.employees.collectAsState().value
    val tasks = viewModel.allTasks.collectAsState().value
    val projects = viewModel.projects.collectAsState().value



    println("🟢 ManagerHome employee = $employee")


    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp)

    ){

        Text("Projects", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 24.dp))
        LazyColumn(modifier = Modifier.fillMaxWidth()) {
            items(projects) { prj ->
                ProjectItem(prj)
            }
        }


//        Text("Recent Tasks", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 24.dp))
//        LazyColumn(modifier = Modifier.fillMaxWidth()) {
//              items(tasks) { tsk ->
//                  TaskItem(tsk)
//              }
//        }

//        Text("Employee List", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 24.dp))
//        LazyColumn(modifier = Modifier.fillMaxWidth()) {
//            items(employees) { emp ->
//                EmployeeItem(emp)
//            }
//        }


    }
}

//@Composable
//fun EmployeeItem(emp: Employee) {
//    Card(
//        modifier = Modifier
//            .fillMaxWidth()
//            .padding(horizontal = 16.dp, vertical = 8.dp),
//        elevation = CardDefaults.cardElevation(4.dp)
//    ) {
//        Column(modifier = Modifier.padding(16.dp)) {
//
//            Text(
//                text = "${emp.Employee_fn} ${emp.Employee_ln}",
//                style = MaterialTheme.typography.titleMedium
//            )
//
//            Text(
//                text = emp.Employee_email ?: "",
//                style = MaterialTheme.typography.bodyMedium,
//                modifier = Modifier.padding(top = 6.dp)
//            )
//
//            Text(
//                text = emp.role ?: "",
//                style = MaterialTheme.typography.labelMedium,
//                modifier = Modifier.padding(top = 4.dp)
//            )
//        }
//    }
//}



@Preview(showBackground = true)
@Composable
fun ManagerHomePreview() {
    val fakeVM = AuthViewModel().apply {
        setFakeEmployee(
            Employee(
                EID = "123",
                Employee_fn = "Shaq",
                Employee_ln = "Neil",
                Employee_phone = "123-4567",
                Employee_email = "shaq@mail.com",
                role = "manager",
                Avatar_url = null,
                created_at = "Now"
            )
        )
    }

    ManagerHome(viewModel = fakeVM)
}
