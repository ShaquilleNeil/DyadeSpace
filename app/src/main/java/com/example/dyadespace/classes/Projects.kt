package com.example.dyadespace.classes
import kotlinx.serialization.Serializable

@Serializable
data class Projects (
    val id: String? = null,
    val name: String? = null,
    val description: String? = null,
    val address: String? = null,
    val photo_url: String? = null,
    val created_at: String? = null
)
