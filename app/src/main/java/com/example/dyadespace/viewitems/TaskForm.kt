package com.example.dyadespace.viewitems

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.dyadespace.classes.Tasks
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.classes.Employee


@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaskForm(
    projectId: String,
    allEmployees: List<Employee> ,
    onDismiss: () -> Unit,
    onSave: (Tasks) -> Unit
){
    var title by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var deadline by remember { mutableStateOf("") }
    var showDatePicker by remember { mutableStateOf(false) }
    var dropdownExpanded by remember { mutableStateOf(false) }
    var selectedEmployee by remember { mutableStateOf<Employee?>(null) }





    Column(
        modifier = Modifier.padding(16.dp)
            .fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ){

        Text("Add Task", style = MaterialTheme.typography.titleMedium, modifier = Modifier.align(Alignment.CenterHorizontally))

        TextField(
            value = title,
            onValueChange = { title = it },
            label = { Text("Title") },
            modifier = Modifier.fillMaxWidth()


        )

        TextField(
            value = description,
            onValueChange = { description = it },
            label = { Text("Description") },
            modifier = Modifier.fillMaxWidth()
        )

        //wrap texfield in a clickable container

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { showDatePicker = true }
        ) {
            TextField(
                value = deadline,
                onValueChange = {},
                label = { Text("Deadline") },
                readOnly = true,
                enabled = false,
                modifier = Modifier.fillMaxWidth()
            )
        }

        Text("Assign Employee(s)",
            style = MaterialTheme.typography.titleMedium)

        ExposedDropdownMenuBox(
            expanded = dropdownExpanded,
            onExpandedChange = { dropdownExpanded = !dropdownExpanded },
            modifier = Modifier.fillMaxWidth()

        ) {
            TextField(
                value = selectedEmployee?.let{
                    "${it.Employee_fn} ${it.Employee_ln}"
                } ?: "Select Employee",
                onValueChange = {},
                readOnly = true,
                trailingIcon = {
                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = dropdownExpanded)
                },
                modifier = Modifier.menuAnchor().fillMaxWidth()

            )

            ExposedDropdownMenu(
                expanded = dropdownExpanded,
                onDismissRequest = { dropdownExpanded = false }
            ) {
//                                Text("DEBUG: ${allEmployees.size} employees")
                allEmployees.forEach { emp ->
                    DropdownMenuItem(
                        text = { Text("${emp.Employee_fn} ${emp.Employee_ln}") },
                        onClick = {
                            selectedEmployee = emp
                            dropdownExpanded = false
                        }
                    )

                }
            }
        }
        
        Button(
            onClick = {
                val newTask = Tasks(
                    id = null,
                    title = title,
                    description = description,
                    status = "todo",
                    deadline = deadline,
                    project_id = projectId
                )
                onSave(newTask)

            },
            modifier = Modifier.width(200.dp).padding(top = 16.dp).align(Alignment.CenterHorizontally),
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
            Text("Save")
        }

    }


    if (showDatePicker) {
        val datePickerState = rememberDatePickerState()

        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        val millis = datePickerState.selectedDateMillis
                        if (millis != null) {
                            deadline = millis.toReadableDate()
                        }
                        showDatePicker = false
                    }
                ) {
                    Text("OK")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) {
                    Text("Cancel")
                }
            }
        ) {
            DatePicker(state = datePickerState)
        }
    }
    

}

fun Long.toReadableDate(): String {
    val formatter = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
    return formatter.format(java.util.Date(this))
}

@Preview(showBackground = true)
@Composable
fun AddTaskFormPreview() {
    TaskForm(
        projectId = "P123",
        allEmployees = listOf(
            Employee("E1", "Shaq", "Neil", "", "", "Manager", ""),
            Employee("E2", "Alex", "Martin", "", "", "Electrician", "")
        ),
        onDismiss = {},
        onSave = {}
    )
}