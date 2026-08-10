package com.example.dyadespace.viewitems

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
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
import com.example.dyadespace.classes.Employee


private class TaskEntryState {
    var title by mutableStateOf("")
    var description by mutableStateOf("")
    var deadline by mutableStateOf("")
    val pickedEmployees = mutableStateListOf<Employee>()
    var expanded by mutableStateOf(true)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaskForm(
    projectId: String?,
    allEmployees: List<Employee> ,
    selectedEmployee: Employee?,
    onDismiss: () -> Unit,
    onSave: (Tasks, List<String>) -> Unit
){
    val taskEntries = remember { mutableStateListOf(TaskEntryState()) }

    Column(
        modifier = Modifier.padding(16.dp)
            .fillMaxWidth()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ){

        Text("Add Task", style = MaterialTheme.typography.titleMedium, modifier = Modifier.align(Alignment.CenterHorizontally))

        taskEntries.forEachIndexed { index, entry ->
            if (entry.expanded) {
                TaskEntryFields(
                    entry = entry,
                    index = index,
                    showLabel = taskEntries.size > 1,
                    allEmployees = allEmployees,
                    selectedEmployee = selectedEmployee
                )
            } else {
                CollapsedTaskEntry(
                    entry = entry,
                    index = index,
                    onExpand = { entry.expanded = true }
                )
            }
        }

        OutlinedButton(
            onClick = {
                taskEntries.last().expanded = false
                taskEntries.add(TaskEntryState())
            },
            modifier = Modifier.fillMaxWidth()
        ){
            Text("+ Add Another Task")
        }

        Button(
            onClick = {
                taskEntries.forEach { entry ->
                    if (entry.title.isNotBlank()) {
                        val newTask = Tasks(
                            id = null,
                            title = entry.title,
                            description = entry.description,
                            status = "todo",
                            deadline = entry.deadline,
                            project_id = projectId
                        )

                        val finalEmployeeIds = if (selectedEmployee != null) {
                            listOf(selectedEmployee.EID)
                        } else {
                            entry.pickedEmployees.map { it.EID }
                        }
                        if (finalEmployeeIds.isNotEmpty()) {
                            onSave(newTask, finalEmployeeIds)
                        }
                    }
                }
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

}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TaskEntryFields(
    entry: TaskEntryState,
    index: Int,
    showLabel: Boolean,
    allEmployees: List<Employee>,
    selectedEmployee: Employee?
){
    var showDatePicker by remember { mutableStateOf(false) }
    var dropdownExpanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {

        if (showLabel) {
            Text("Task ${index + 1}", style = MaterialTheme.typography.titleSmall)
        }

        TextField(
            value = entry.title,
            onValueChange = { entry.title = it },
            label = { Text("Title") },
            modifier = Modifier.fillMaxWidth()


        )

        TextField(
            value = entry.description,
            onValueChange = { entry.description = it },
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
                value = entry.deadline,
                onValueChange = {},
                label = { Text("Deadline") },
                readOnly = true,
                enabled = false,
                modifier = Modifier.fillMaxWidth()
            )
        }

        if (selectedEmployee != null) {
            Text(
                "Assigned to: ${selectedEmployee.Employee_fn} ${selectedEmployee.Employee_ln}",
                style = MaterialTheme.typography.bodyMedium
            )
        } else {
            Text("Assign Employees", style = MaterialTheme.typography.titleMedium)

            ExposedDropdownMenuBox(
                expanded = dropdownExpanded,
                onExpandedChange = { dropdownExpanded = !dropdownExpanded }
            ) {
                TextField(
                    value = if (entry.pickedEmployees.isEmpty()) {
                        "Select Employees"
                    } else {
                        entry.pickedEmployees.joinToString(", ") { "${it.Employee_fn} ${it.Employee_ln}" }
                    },
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
                    allEmployees.forEach { emp ->
                        val isSelected = entry.pickedEmployees.contains(emp)
                        DropdownMenuItem(
                            leadingIcon = {
                                Checkbox(
                                    checked = isSelected,
                                    onCheckedChange = null
                                )
                            },
                            text = { Text("${emp.Employee_fn} ${emp.Employee_ln}") },
                            onClick = {
                                if (isSelected) {
                                    entry.pickedEmployees.remove(emp)
                                } else {
                                    entry.pickedEmployees.add(emp)
                                }
                            }
                        )
                    }
                }
            }
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
                            entry.deadline = millis.toReadableDate()
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

@Composable
private fun CollapsedTaskEntry(
    entry: TaskEntryState,
    index: Int,
    onExpand: () -> Unit
){
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onExpand() }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Task ${index + 1}: ${entry.title.ifBlank { "Untitled" }}",
                style = MaterialTheme.typography.bodyMedium
            )
            Icon(Icons.Filled.ExpandMore, contentDescription = "Expand")
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
    selectedEmployee = null,
    onDismiss = {},
    onSave = { task, empIds ->
        println("Task: $task, Employee IDs: $empIds")
    }
    )
}
