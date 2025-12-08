package com.example.dyadespace.classes

import kotlinx.serialization.Serializable

@Serializable
data class Tasks(
    val id: String,
    val title: String,
    val description: String? = null,
    val status: String? = null,
    val deadline: String,
    val created_at: String? = null,   // MUST BE INCLUDED
    val project_id: String? = null
)