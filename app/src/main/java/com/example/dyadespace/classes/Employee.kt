package com.example.dyadespace.classes

import kotlinx.serialization.Serializable

@Serializable
data class Employee(
    val EID: String,
    val Employee_fn: String,
    val Employee_ln: String? = null,
    val Employee_phone: String? = null,
    val Employee_email: String,
    val role: String,
    val Avatar_url: String? = null,
    val created_at: String? = null
)
