package com.example.dyadespace.manager

import android.content.res.Configuration
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Divider
import androidx.compose.material3.DockedSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.example.dyadespace.R
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.authScreens.ProjectViewModel
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.ui.theme.DyadeSpaceTheme
import com.example.dyadespace.viewitems.EmployeeRow

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProjectEmployeesScreen(
    projectId: String,
    navController: NavController,
    projectViewModel: ProjectViewModel,
) {
    LaunchedEffect(projectId) {
        projectViewModel.fetchProjectEmployees(projectId)
    }

    val project by projectViewModel.aproject.collectAsState()
    val employees by projectViewModel.projectemployees.collectAsState()

    var searchQuery by remember { mutableStateOf("") }
    val filteredEmployees = employees.filter { employee ->
        employee.Employee_fn?.contains(searchQuery, ignoreCase = true) ?: false ||
                employee.Employee_ln?.contains(searchQuery, ignoreCase = true) ?: false
    }

    val displayedEmployees = if (searchQuery.isBlank()) employees else filteredEmployees






    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ){
        Column(modifier = Modifier.fillMaxWidth().safeDrawingPadding())
        {

            Text(
                text = project?.name ?: "Loading project…",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(start = 16.dp)
            )

            Text("Employees(${employees.size} )",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, top = 4.dp)
            )

            DockedSearchBar(
                inputField = {
                    OutlinedTextField(
                        value = searchQuery,
                        onValueChange = { searchQuery = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text(stringResource(R.string.search)) },
                        leadingIcon = {
                            Icon(Icons.Filled.Search, contentDescription = null)
                        },
                        singleLine = true,
                        shape = RoundedCornerShape(12.dp),   // ⬅️ smaller radius
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color.Transparent,
                            unfocusedBorderColor = Color.Transparent
                        )
                    )

                },
                expanded = false,              // 🔒 never expands
                onExpandedChange = {},         // 🔒 ignore expansion
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                content = {
                    // intentionally empty — no suggestions
                }
            )

            Divider()

            ProjectEmployeesUi(
                employees = displayedEmployees,
                onRemove = { emp ->
                    // viewModel.removeEmployeeFromProject(projectId, emp.EID)
                }
            )
        }
    }


}


@Composable
fun ProjectEmployeesUi(
    employees: List<Employee>,
    onRemove: (Employee) -> Unit = {}
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize()
    ) {
        items(employees) { emp ->
            EmployeeRow(
                emp = emp,
                onRemove = { onRemove(emp) }
            )
            HorizontalDivider()
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
fun ProjectEmployeesPreview() {
    DyadeSpaceTheme {
        Surface {
            ProjectEmployeesUi(
                employees = listOf(
                    Employee(
                        EID = "E1",
                        Employee_fn = "Shaq",
                        Employee_ln = "Neil",
                        Employee_phone = "123-4567",
                        Employee_email = "shaq@example.com",
                        role = "Manager",
                        Avatar_url = null
                    ),
                    Employee(
                        EID = "E2",
                        Employee_fn = "Alex",
                        Employee_ln = "Martin",
                        Employee_phone = "555-9876",
                        Employee_email = "alex@example.com",
                        role = "Electrician",
                        Avatar_url = null
                    )
                )
            )
        }
    }
}