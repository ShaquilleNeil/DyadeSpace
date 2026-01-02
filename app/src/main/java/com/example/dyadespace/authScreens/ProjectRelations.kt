package com.example.dyadespace.authScreens

import com.example.dyadespace.classes.Employee
import com.example.dyadespace.classes.Tasks
import kotlinx.serialization.Serializable


@Serializable
data class ProjectEmployeeWithEmployee(
    val employees: Employee
)

@Serializable
data class ProjectTaskWithTask(
    val tasks: Tasks
)

@Serializable
data class ProjectTaskInsert(
    val project_id: String,
    val task_id: String
)

