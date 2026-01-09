package com.example.dyadespace.manager

import android.content.res.Configuration
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import com.example.dyadespace.authScreens.TaskViewModel
import com.example.dyadespace.ui.preview.previewData
import com.example.dyadespace.ui.theme.DyadeSpaceTheme

@Composable
fun TaskView(
    taskId: String,
    navController: NavController,
    taskViewModel: TaskViewModel,
) {

    LaunchedEffect(taskId) {
        taskViewModel.fetchTaskById(taskId)
    }

    val tsk = taskViewModel.taskbyid.collectAsState().value

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.fillMaxSize().padding(5.dp)
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
        )
        {

            Text(tsk?.title ?: "",
                style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(top = 10.dp).padding(bottom = 10.dp)
            )

            val statusColor = when (tsk?.status) {
                "in-progress" -> Color.Green
                "done" -> Color.Blue
                else -> Color.Red
            }

            val statusText = when (tsk?.status) {
                "todo" -> "To Do"
                "in-progress" -> "In Progress"
                "done" -> "Completed"
                else -> ""

            }
            Surface(
                modifier = Modifier
                    .align(Alignment.Start)
                    .padding(12.dp),
                shape = RoundedCornerShape(50),
                if (tsk?.status == "in-progress") Color.Yellow
                else if (tsk?.status == "completed") Color.Green
                else Color.Blue,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)

            ) {
                Text(
                    text = statusText,
                    style = MaterialTheme.typography.labelMedium,
                    color = Color.Black,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                )
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(14.dp)
                    .border(
                        width = 1.dp,
                        color = MaterialTheme.colorScheme.outline,
                        shape = RoundedCornerShape(10.dp)
                    )
                    .padding(10.dp)

            ){
                Icon(
                    imageVector = Icons.Filled.CalendarToday,
                    contentDescription = "Calendar Icon",
                    tint = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(22.dp),

                    )

                Column(
                    modifier = Modifier.fillMaxWidth().padding(start = 12.dp)
                ){
                    Text("Deadline",
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(bottom = 4.dp))
                    Text(tsk?.deadline?: "",
                        color = MaterialTheme.colorScheme.onSurface,
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(bottom = 4.dp))



                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(14.dp)
                    .border(
                        width = 1.dp,
                        color = MaterialTheme.colorScheme.outline,
                        shape = RoundedCornerShape(10.dp)
                    )
                    .padding(10.dp)

            ){
                Icon(
                    imageVector = Icons.Filled.Person,
                    contentDescription = "Person Icon",
                    tint = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.size(22.dp)

                )

                Column(
                    modifier = Modifier.fillMaxWidth().padding(start = 12.dp)
                ){
                    Text("Assigned To",
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.padding(bottom = 4.dp))
                    Text("Employee Name",
                        color = MaterialTheme.colorScheme.onSurface,
                        style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(bottom = 4.dp))



                }
            }

            Text("Description",
                style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(top = 10.dp).padding(all =  12.dp).align(Alignment.Start),
                color = MaterialTheme.colorScheme.onSurface
            )



            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(14.dp)
                    .border(
                        width = 1.dp,
                        color = MaterialTheme.colorScheme.outline,
                        shape = RoundedCornerShape(10.dp)
                    )
                    .padding(10.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {

                Text(tsk?.description ?: "",
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(bottom = 10.dp).align(Alignment.Start). padding(10.dp),
                    color = MaterialTheme.colorScheme.onSurface
                )
            }

            if (tsk?.status == "todo") {
                Button(
                    onClick = {
                        taskViewModel.updateTaskStatus(taskId, "in-progress")
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
                        taskViewModel.updateTaskStatus(taskId, "done")
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
                Text("Completed", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurface)
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
fun TaskViewPreview() {
    // Fake / mock data for preview only
    DyadeSpaceTheme() {
        Surface(
            color = MaterialTheme.colorScheme.background
        ) {
            val fakeViewModel = previewData.taskViewModel()
            TaskView(
                taskId = "preview",
                navController = NavController(LocalContext.current),
                taskViewModel = fakeViewModel
            )
        }

    }

}
