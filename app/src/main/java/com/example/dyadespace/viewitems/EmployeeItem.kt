package com.example.dyadespace.viewitems

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults.cardColors
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.example.dyadespace.classes.Employee

@Composable
fun EmployeeItem(emp: Employee) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
               modifier = Modifier.padding(horizontal = 12.dp)


        ){
            AsyncImage(
                model = emp.Avatar_url,
                contentDescription = "Employee Avatar",
                modifier = Modifier.size(56.dp).clip(CircleShape),
                contentScale = ContentScale.Crop

            )

            Spacer(modifier = Modifier.height(6.dp))

            Text(emp.Employee_fn,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1

            )

            Text(emp.role,
                style = MaterialTheme.typography.labelSmall,
                color = Color.Gray,
                maxLines = 1

            )

        }





}

@Preview(showBackground = true)
@Composable
fun EmployeeItemPreview() {

    EmployeeItem(
        Employee(
            EID = "123",
            Employee_fn = "Shaq",
            Employee_ln = "Neil",
            Employee_phone = "123-4567",
            Employee_email = "john.quincy.adams@examplepetstore.com",
            role = "Manager",
            Avatar_url = "https://picsum.photos/200",

        )
    )

}