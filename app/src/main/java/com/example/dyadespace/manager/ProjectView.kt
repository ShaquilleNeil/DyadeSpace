package com.example.dyadespace.manager

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import coil.compose.AsyncImage
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.classes.Projects
import com.example.dyadespace.viewitems.EmployeeItem
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Icon
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.clip

/* ---------------------------------------------------
   UI-ONLY COMPOSABLE (PREVIEWABLE)
--------------------------------------------------- */
@Composable
fun ProjectViewUi(project: Projects, employees: List<Employee> ) {

    var employeesExpanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .padding(16.dp),
        horizontalAlignment = Alignment.Start
    ) {



        AsyncImage(
            model = project.photo_url,
            contentDescription = "Project Image",
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(8.dp))

        )

        Text(
            text = project.name ?: "Unnamed Project",
            modifier = Modifier.padding(bottom = 12.dp)
                .align(Alignment.Start),
            style = MaterialTheme.typography.titleLarge
        )


        Text(

            text = project.address ?: "",
            modifier = Modifier.padding(top = 8.dp).align(Alignment.Start),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.primary,
            fontWeight =  androidx.compose.ui.text.font.FontWeight.Bold
        )

        Text(
            text = project.description ?: "",
            modifier = Modifier.padding(top = 16.dp),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.primary
        )

        HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

        /* ---------- EMPLOYEES HEADER (CLICKABLE) ---------- */
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { employeesExpanded = !employeesExpanded }
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Employees (${employees.size})",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f)
            )

            Icon(
                imageVector = if (employeesExpanded)
                    Icons.Default.ExpandLess
                else
                    Icons.Default.ExpandMore,
                contentDescription = null
            )
        }

        /* ---------- COLLAPSIBLE EMPLOYEE ROW ---------- */
        AnimatedVisibility(visible = employeesExpanded) {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(employees) { emp ->
                    EmployeeItem(emp)
                }
            }
        }

//        HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

        /* ---------- TASKS HEADER ---------- */
        Text(
            text = "Tasks",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 40.dp)
        )
    }
}

/* ---------------------------------------------------
   RUNTIME SCREEN (NAV + VIEWMODEL)
--------------------------------------------------- */
@Composable
fun ProjectViewContent(
    projectId: String,
    navController: NavController,
    viewModel: AuthViewModel
) {
    LaunchedEffect(projectId) {
        viewModel.fetchProjectById(projectId)
        viewModel.fetchProjectEmployees(projectId)
    }

    val project by viewModel.aproject.collectAsState()
    val employees by viewModel.projectemployees.collectAsState()


    if (project == null) {
        Text("Loading project…")
    } else {
        ProjectViewUi(project = project!!, employees = employees)
    }
}

/* ---------------------------------------------------
   PREVIEW (FAKE DATA ONLY)
--------------------------------------------------- */
@Preview(showBackground = true)
@Composable
fun ProjectViewPreview() {
    ProjectViewUi(
        project = Projects(
            id = "P123",
            name = "Downtown Office Renovation",
            description = "Complete interior renovation including electrical, drywall, and finishes.",
            address = "Montreal, QC",
            photo_url = "https://picsum.photos/1200/800"
        ),
        employees = listOf(
            Employee(
                EID = "E1",
                Employee_fn = "Shaq",
                Employee_ln = "Neil",
                Employee_phone = "123-4567",
                Employee_email = "shaq@example.com",
                role = "Manager",
                Avatar_url = "https://picsum.photos/200?1"
            ),
            Employee(
                EID = "E2",
                Employee_fn = "Alex",
                Employee_ln = "Martin",
                Employee_phone = "555-9876",
                Employee_email = "alex@example.com",
                role = "Electrician",
                Avatar_url = "https://picsum.photos/200?2"
            ),
            Employee(
                EID = "E3",
                Employee_fn = "Jamie",
                Employee_ln = "Lopez",
                Employee_phone = "555-2222",
                Employee_email = "jamie@example.com",
                role = "Foreman",
                Avatar_url = "https://picsum.photos/200?3"
            )
        )
    )
}
