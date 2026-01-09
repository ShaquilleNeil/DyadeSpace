package com.example.dyadespace.ui.preview

import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.authScreens.ProjectViewModel
import com.example.dyadespace.authScreens.TaskViewModel
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.classes.Projects
import com.example.dyadespace.classes.Tasks

object previewData {
    fun authViewModel(): AuthViewModel =
        AuthViewModel().apply {
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


    fun projectViewModel(): ProjectViewModel =
        ProjectViewModel().apply {
            setFakeProjects(
                listOf(
                    Projects(
                        id = "p1",
                        name = "DyadeSpace HQ",
                        description = "Main office renovation",
                        address = "123 Main St, Montreal",
                        photo_url = null,
                        created_at = "2026-01-09"
                    ),
                    Projects(
                        id = "p2",
                        name = "Client Mobile App",
                        description = "iOS + Android rollout",
                        address = "Remote",
                        photo_url = null,
                        created_at = "2026-01-02"
                    )
                )
            )
        }


    fun taskViewModel(): TaskViewModel =
        TaskViewModel(projectViewModel()).apply {
            setFakeTasks(
                listOf(
                    Tasks(
                        id = "t1",
                        title = "Fix Manager Home preview",
                        description = "Ensure previews load without Supabase",
                        status = "Done",
                        deadline = "2026-01-15",
                        created_at = "2026-01-09",
                        project_id = "p1"
                    ),
                    Tasks(
                        id = "t2",
                        title = "Add search to projects",
                        description = "Search by name and address",
                        status = "In Progress",
                        deadline = "2026-01-20",
                        created_at = "2026-01-08",
                        project_id = "p1"
                    )
                )
            )
        }
}