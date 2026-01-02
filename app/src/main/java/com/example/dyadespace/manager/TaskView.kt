package com.example.dyadespace.manager

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.example.dyadespace.authScreens.AuthViewModel
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.platform.LocalContext

@Composable
fun TaskView(
    taskId: String,
    navController: NavController,
    viewModel: AuthViewModel
){

    LaunchedEffect(taskId) {
        viewModel.fetchTaskById(taskId)
    }

    val tsk = viewModel.taskbyid.collectAsState().value



    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxSize().padding(5.dp)
            .safeDrawingPadding()
            .verticalScroll(rememberScrollState())
    ){

        Text(tsk?.title ?: "",
            style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(top = 10.dp).padding(bottom = 10.dp)
            )

        val statusColor = when (tsk?.status) {
            "in-progress" -> Color.Green
            "done" -> Color.Blue
            else -> Color.Red
        }

        Surface(
            modifier = Modifier
                .align(Alignment.Start)
                .padding(12.dp),
            shape = RoundedCornerShape(50),
            statusColor

        ) {
            Text(
                text = tsk?.status ?: "",
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
            )
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
                .padding(14.dp)
                .background(color = androidx.compose.ui.graphics.Color.LightGray, shape = androidx.compose.foundation.shape.RoundedCornerShape(10.dp))
                .padding(10.dp)

        ){
            Icon(
                imageVector = Icons.Filled.CalendarToday,
                contentDescription = "Calendar Icon",
                tint = Color.Red,
                modifier = Modifier.size(22.dp)

            )

            Column(
                modifier = Modifier.fillMaxWidth().padding(start = 12.dp)
            ){
                Text("Deadline",
                    color = Color.White,
                    modifier = Modifier.padding(bottom = 4.dp))
                Text(tsk?.deadline?: "",
                    color = Color.White,
                    style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(bottom = 4.dp))



            }
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
                .padding(14.dp)
                .background(color = androidx.compose.ui.graphics.Color.LightGray, shape = androidx.compose.foundation.shape.RoundedCornerShape(10.dp))
                .padding(10.dp)

        ){
            Icon(
                imageVector = Icons.Filled.Person,
                contentDescription = "Person Icon",
                tint = Color.Red,
                modifier = Modifier.size(22.dp)

            )

            Column(
                modifier = Modifier.fillMaxWidth().padding(start = 12.dp)
            ){
                Text("Assigned To",
                    color = Color.White,
                    modifier = Modifier.padding(bottom = 4.dp))
                Text("Employee Name",
                    color = Color.White,
                    style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                    modifier = Modifier.padding(bottom = 4.dp))



            }
        }

        Text("Description",
            style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(top = 10.dp).padding(all =  12.dp).align(Alignment.Start)
        )



        Column(
            modifier = Modifier.fillMaxWidth()
                .padding(14.dp)
                .background(color = androidx.compose.ui.graphics.Color.LightGray, shape = androidx.compose.foundation.shape.RoundedCornerShape(10.dp)),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {

            Text(tsk?.description ?: "",
                style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(bottom = 10.dp).align(Alignment.Start). padding(10.dp)
            )
        }

        if (tsk?.status == "todo") {
            Button(
                onClick = {
                    viewModel.updateTaskStatus(taskId, "in-progress")
                },
                modifier = Modifier.width(200.dp).padding(top = 16.dp),
                shape = MaterialTheme.shapes.medium,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.Green,
                    contentColor = Color.White
                ),
                elevation = ButtonDefaults.buttonElevation(
                    defaultElevation = 10.dp,
                    pressedElevation = 15.dp,
                    disabledElevation = 0.dp)
            ){
                Text("Accept")
            }
        } else if (tsk?.status == "in-progress") {
            Button(
                onClick = {
                    viewModel.updateTaskStatus(taskId, "done")
                },
                modifier = Modifier.width(200.dp).padding(top = 16.dp).padding(bottom = 16.dp),
                shape = MaterialTheme.shapes.medium,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.Blue,
                    contentColor = Color.White
                ),
                elevation = ButtonDefaults.buttonElevation(
                    defaultElevation = 10.dp,
                    pressedElevation = 15.dp,
                    disabledElevation = 0.dp)
            ){
                Text("Mark as Complete")
            }
        } else {
            Text("Task is already completed")
        }




    }

}


@Preview(showBackground = true)
@Composable
fun TaskViewPreview() {
    // Fake / mock data for preview only
    val fakeViewModel = AuthViewModel()
    TaskView(
        taskId = "preview",
        navController = NavController(LocalContext.current),
        viewModel = fakeViewModel
    )
}
