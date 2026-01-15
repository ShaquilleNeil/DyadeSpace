package com.example.dyadespace.viewitems

import android.content.res.Configuration
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.example.dyadespace.classes.Employee

@Composable
fun EmployeeRow(
    emp: Employee,
    onRemove: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {

        AsyncImage(
            model = emp.Avatar_url,
            contentDescription = "Employee Avatar",
            modifier = Modifier.size(56.dp).clip(CircleShape),
            contentScale = ContentScale.Crop

        )
        Spacer(modifier = Modifier.width(16.dp))


        // Name + role
        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = "${emp.Employee_fn} ${emp.Employee_ln}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface
            )

            Text(
                text = emp.role ?: "unknown",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Remove action
        Text(
            text = "Remove",
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.labelMedium,
            modifier = Modifier.clickable {
                onRemove()
            }
        )
    }
}


@Preview(showBackground = true, name = "Light", uiMode = Configuration.UI_MODE_NIGHT_NO)
@Preview(
    showBackground = true,
    name = "Dark",
    uiMode = Configuration.UI_MODE_NIGHT_YES
)
@Composable
fun EmployeeRowPreview() {
    EmployeeRow(
        emp = Employee(
            EID = "E1",
            Employee_fn = "Shaq",
            Employee_ln = "Neil",
            Employee_phone = "123-4567",
            Employee_email = "shaq@example.com",
            role = "Manager",
            Avatar_url = null
        ),
        onRemove = { }
    )
}

