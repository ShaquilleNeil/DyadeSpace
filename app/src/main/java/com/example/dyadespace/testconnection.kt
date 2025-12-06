package com.example.dyadespace

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import com.example.dyadespace.data.supabase.SupabaseClient

@Composable
fun TestConnectionScreen() {
    var result by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center
    ) {
        Text("Supabase Connection Test", style = MaterialTheme.typography.headlineSmall)

        Spacer(Modifier.height(20.dp))

        Button(onClick = {
            scope.launch {
                val ok = SupabaseClient.testConnection()
                result = if(ok) "Connected Successfully 🔥" else "Connection Failed ❌"
            }
        }, modifier = Modifier.fillMaxWidth()) {
            Text("Run Test")
        }

        result?.let {
            Spacer(Modifier.height(20.dp))
            Text(it, style = MaterialTheme.typography.bodyLarge)
        }
    }
}