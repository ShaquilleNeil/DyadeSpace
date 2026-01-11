package com.example.dyadespace.classes

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Employee(
    val EID: String,

    @SerialName("Employee_fn")
    val Employee_fn: String,

    @SerialName("Employee_ln")
    val Employee_ln: String? = null,

    @SerialName("Employee_phone")
    val Employee_phone: String? = null,

    @SerialName("Employee_email")
    val Employee_email: String? = null,

    val role: String? = null,

    @SerialName("Avatar_url")
    val Avatar_url: String? = null,

    val created_at: String? = null
)
