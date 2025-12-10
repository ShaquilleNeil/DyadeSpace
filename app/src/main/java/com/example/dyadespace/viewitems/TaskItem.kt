package com.example.dyadespace.viewitems

import android.view.RoundedCorner
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.dyadespace.classes.Tasks

@Composable
fun TaskItem(tsk: Tasks ) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .height(140.dp)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        elevation = CardDefaults.cardElevation(4.dp),
        shape = RoundedCornerShape(25.dp)



    ) {
        Column(modifier = Modifier.padding(16.dp)) {

            Text(
                text = "${tsk.title}",
                style = MaterialTheme.typography.titleMedium
            )

            Text(
                text = tsk.description?: "",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = 6.dp)
            )

            Text(
                text = "Status: " + (tsk.status?: ""),
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(top = 4.dp)
            )
            Text(
                text = "Due :" + (tsk.deadline?: ""),
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

@Preview(showBackground = true)
@Composable
fun TaskItemPreview() {
    TaskItem(
        Tasks(
            id = "1",
            title = "Mix Concrete",
            description = "Prepare concrete mix for walkway slab",
            status = "in-progress",
            deadline = "2025-01-13",
            created_at = null,
            project_id = null
        )
    )
}
