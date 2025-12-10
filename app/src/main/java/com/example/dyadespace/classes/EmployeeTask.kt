package com.example.dyadespace.classes

import kotlinx.serialization.Serializable

@Serializable
data class EmployeeTask(
    val id: String,          // task id (FK → tasks.id)
    val EID: String,         // employee id (FK → employees.EID)
    val created_at: String? = null
)
